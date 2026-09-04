import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const InsulinApp());
}

class InsulinApp extends StatefulWidget {
  const InsulinApp({super.key});

  @override
  State<InsulinApp> createState() => _InsulinAppState();
}

class _InsulinAppState extends State<InsulinApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? true;
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  Future<void> _toggleTheme(bool isDark) async {
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Insulin Calculator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: CalculatorScreen(
        isDarkMode: _themeMode == ThemeMode.dark,
        onThemeChanged: _toggleTheme,
      ),
    );
  }
}

class CalculatorScreen extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onThemeChanged;

  const CalculatorScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final TextEditingController _bgController = TextEditingController();
  final TextEditingController _carbController = TextEditingController();

  // Settings Controllers
  final TextEditingController _ratioController = TextEditingController(text: '8');
  final TextEditingController _targetBgController = TextEditingController(text: '150');
  final TextEditingController _correctionFactorController = TextEditingController(text: '40');

  String _roundingMode = '0.5';
  bool _showTips = true;

  double _correctionDose = 0.0;
  double _carbDose = 0.0;
  double _rawTotalDose = 0.0;
  double _displayTotalDose = 0.0;
  double _totalCarbsSum = 0.0;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isFirstLaunch = prefs.getBool('hasSeenGuide') ?? false;

    setState(() {
      _ratioController.text = prefs.getString('savedCarbRatio') ?? '8';
      _targetBgController.text = prefs.getString('savedTargetBg') ?? '150';
      _correctionFactorController.text = prefs.getString('savedCorrectionFactor') ?? '40';
      _roundingMode = prefs.getString('savedRoundingMode') ?? '0.5';
      _showTips = prefs.getBool('showAppTips') ?? true;
    });

    // Automatically trigger user guide on first ever launch
    if (!isFirstLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showGuideDialog();
        prefs.setBool('hasSeenGuide', true);
      });
    }
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is String) {
      await prefs.setString(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    }
  }

  Future<void> _resetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('savedCarbRatio');
    await prefs.remove('savedTargetBg');
    await prefs.remove('savedCorrectionFactor');
    await prefs.remove('savedRoundingMode');
    await prefs.remove('showAppTips');

    setState(() {
      _ratioController.text = '8';
      _targetBgController.text = '150';
      _correctionFactorController.text = '40';
      _roundingMode = '0.5';
      _showTips = true;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings reset to defaults')),
      );
    }
  }

  void _showGuideDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.teal),
            SizedBox(width: 8),
            Text('Welcome & User Guide'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('How to use your Insulin Calculator:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text('1. Enter Current Blood Sugar\nInput your measured blood sugar level (mg/dL).'),
              SizedBox(height: 8),
              Text('2. Adding Carbs Made Easy\nYou can type math addition in the carb field (e.g. 15 + 25 + 10) to automatically sum your meal!'),
              SizedBox(height: 8),
              Text('3. Advanced Formula Settings\nExpand Advanced Settings to adjust your Carb Ratio, Target Blood Sugar, Correction Factor, or Dosage Rounding.'),
              SizedBox(height: 8),
              Text('4. App Tips Toggle\nEnable App Tips inside Advanced Settings if you want helpful inline hints.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got It!', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  double _applyRounding(double rawDose) {
    if (_roundingMode == '0.5') {
      return (rawDose * 2).round() / 2;
    } else if (_roundingMode == '1.0') {
      return rawDose.roundToDouble();
    }
    return rawDose;
  }

  double _parseCarbInput(String input) {
    if (input.trim().isEmpty) return 0.0;

    List<String> parts = input.split('+');
    double sum = 0.0;

    for (String part in parts) {
      double value = double.tryParse(part.trim()) ?? 0.0;
      sum += value;
    }

    return sum;
  }

  void _calculateDose() {
    final double bg = double.tryParse(_bgController.text) ?? 0.0;
    final double carbs = _parseCarbInput(_carbController.text);

    final double ratio = double.tryParse(_ratioController.text) ?? 8.0;
    final double targetBg = double.tryParse(_targetBgController.text) ?? 150.0;
    final double correctionFactor = double.tryParse(_correctionFactorController.text) ?? 40.0;

    setState(() {
      _totalCarbsSum = carbs;

      if (bg > targetBg && correctionFactor > 0) {
        _correctionDose = (bg - targetBg) / correctionFactor;
      } else {
        _correctionDose = 0.0;
      }

      if (ratio > 0) {
        _carbDose = carbs / ratio;
      } else {
        _carbDose = 0.0;
      }

      _rawTotalDose = _correctionDose + _carbDose;
      _displayTotalDose = _applyRounding(_rawTotalDose);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insulin Dose Calculator'),
        centerTitle: true,
        actions: [
          Row(
            children: [
              Icon(
                widget.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                size: 20,
              ),
              Switch(
                value: widget.isDarkMode,
                onChanged: widget.onThemeChanged,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current Blood Sugar Input
            TextField(
              controller: _bgController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Current Blood Sugar (mg/dL)',
                hintText: 'e.g., 210',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.water_drop, color: Colors.redAccent),
              ),
            ),
            if (_showTips) ...[
              const SizedBox(height: 4),
              const Text(
                '💡 Tip: Correction dose applies if blood sugar exceeds your target value.',
                style: TextStyle(fontSize: 12, color: Colors.teal),
              ),
            ],
            const SizedBox(height: 16),

            // Total Carbs Input
            TextField(
              controller: _carbController,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                labelText: 'Total Carbs (grams)',
                hintText: 'e.g., 15 + 30 + 12',
                helperText: 'Add multiple items using + (e.g. 20 + 15)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.restaurant, color: Colors.orangeAccent),
              ),
            ),
            if (_showTips) ...[
              const SizedBox(height: 4),
              const Text(
                '💡 Tip: You can type multiple numbers with plus signs to add meal items together automatically.',
                style: TextStyle(fontSize: 12, color: Colors.teal),
              ),
            ],
            const SizedBox(height: 16),

            // Expandable Advanced Settings Section
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ExpansionTile(
                leading: const Icon(Icons.settings, color: Colors.teal),
                title: const Text(
                  'Advanced Formula Settings',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('Customize ratio, target sugar, tips & guide'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // App Tips Switch
                        SwitchListTile(
                          title: const Text('Show App Tips'),
                          subtitle: const Text('Displays helpful hints under input fields'),
                          value: _showTips,
                          activeColor: Colors.teal,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (bool val) {
                            setState(() {
                              _showTips = val;
                            });
                            _saveSetting('showAppTips', val);
                          },
                        ),
                        const Divider(height: 24),

                        // Open User Guide Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _showGuideDialog,
                            icon: const Icon(Icons.menu_book),
                            label: const Text('Open User Guide'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const Divider(height: 24),

                        // Dosage Rounding Segmented Button
                        const Text(
                          'Dosage Rounding Preference',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'none', label: Text('Exact')),
                            ButtonSegment(value: '0.5', label: Text('Nearest 0.5')),
                            ButtonSegment(value: '1.0', label: Text('Nearest 1.0')),
                          ],
                          selected: {_roundingMode},
                          onSelectionChanged: (Set<String> newSelection) {
                            setState(() {
                              _roundingMode = newSelection.first;
                            });
                            _saveSetting('savedRoundingMode', _roundingMode);
                          },
                        ),
                        const SizedBox(height: 16),

                        // Carb Ratio Input
                        TextField(
                          controller: _ratioController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (val) => _saveSetting('savedCarbRatio', val),
                          decoration: const InputDecoration(
                            labelText: 'Carb Ratio (1 Unit per X grams)',
                            hintText: 'e.g., 8',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.tune, color: Colors.tealAccent),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Target Blood Sugar Input
                        TextField(
                          controller: _targetBgController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (val) => _saveSetting('savedTargetBg', val),
                          decoration: const InputDecoration(
                            labelText: 'Target Blood Sugar (mg/dL)',
                            hintText: 'e.g., 150',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.center_focus_strong, color: Colors.blueAccent),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Correction Factor Input
                        TextField(
                          controller: _correctionFactorController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (val) => _saveSetting('savedCorrectionFactor', val),
                          decoration: const InputDecoration(
                            labelText: 'Correction Factor (1 Unit drops X mg/dL)',
                            hintText: 'e.g., 40',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.trending_down, color: Colors.purpleAccent),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Reset Settings Button
                        Center(
                          child: OutlinedButton.icon(
                            onPressed: _resetSettings,
                            icon: const Icon(Icons.restart_alt, color: Colors.redAccent),
                            label: const Text('Reset Settings to Default'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Calculate Button
            ElevatedButton(
              onPressed: _calculateDose,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              child: const Text('Calculate Dose', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 24),

            // Results Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Text('Total Recommended Dose', style: TextStyle(fontSize: 16, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text(
                      '${_displayTotalDose.toStringAsFixed(1)} Units',
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                    if (_roundingMode != 'none' && _rawTotalDose != _displayTotalDose) ...[
                      const SizedBox(height: 4),
                      Text(
                        '(Exact calculation: ${_rawTotalDose.toStringAsFixed(2)} u)',
                        style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                    ],
                    const Divider(height: 24),
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Calculated Total Carbs:'),
                            Text('${_totalCarbsSum.toStringAsFixed(1)} g', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Correction Dose: ${_correctionDose.toStringAsFixed(1)} u'),
                            Text('Carb Dose: ${_carbDose.toStringAsFixed(1)} u'),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
