import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';

CupertinoThemeData getNativeTheme() {
  return CupertinoThemeData(
    textTheme: CupertinoTextThemeData(
      textStyle: TextStyle(
        // Uses native system font fallback depending on the device OS
        fontFamilyFallback: Platform.isAndroid
            ? const ['sans-serif', 'Noto Color Emoji']
            : const ['.SF UI Text', 'Apple Color Emoji'],
      ),
    ),
  );
}

void main() {
  runApp(const InsulinApp());
}

class InsulinApp extends StatefulWidget {
  const InsulinApp({super.key});

  @override
  State<InsulinApp> createState() => _InsulinAppState();
}

class _InsulinAppState extends State<InsulinApp> {
  bool _isDarkMode = true;

  static const Color primaryCoral = Color(0xFFFF3B30);
  static const Color secondaryOrange = Color(0xFFFF9500);

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? true;
    });
  }

  Future<void> _toggleTheme(bool isDark) async {
    setState(() {
      _isDarkMode = isDark;
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
        brightness: _isDarkMode ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: _isDarkMode
            ? const Color(0xFF000000)
            : const Color(0xFFF2F2F7),
        primaryColor: primaryCoral,
      ),
      home: CalculatorScreen(
        isDarkMode: _isDarkMode,
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
  late final TextEditingController _bgController;
  late final TextEditingController _carbController;
  late final TextEditingController _ratioController;
  late final TextEditingController _targetBgController;
  late final TextEditingController _correctionFactorController;

  int _roundingSegment = 1; // 0: None, 1: 0.5, 2: 1.0
  bool _showTips = true;

  double _correctionDose = 0.0;
  double _carbDose = 0.0;
  double _rawTotalDose = 0.0;
  double _displayTotalDose = 0.0;
  double _totalCarbsSum = 0.0;

  static const Color primaryCoral = Color(0xFFFF3B30);
  static const Color secondaryOrange = Color(0xFFFF9500);

  @override
  void initState() {
    super.initState();
    _bgController = TextEditingController();
    _carbController = TextEditingController();
    _ratioController = TextEditingController(text: '8');
    _targetBgController = TextEditingController(text: '150');
    _correctionFactorController = TextEditingController(text: '40');
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ratioController.text = prefs.getString('savedCarbRatio') ?? '8';
      _targetBgController.text = prefs.getString('savedTargetBg') ?? '150';
      _correctionFactorController.text = prefs.getString('savedCorrectionFactor') ?? '40';
      _roundingSegment = prefs.getInt('savedRoundingSegment') ?? 1;
      _showTips = prefs.getBool('showAppTips') ?? true;
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is String) {
      await prefs.setString(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _carbController.dispose();
    _ratioController.dispose();
    _targetBgController.dispose();
    _correctionFactorController.dispose();
    super.dispose();
  }

  void _showGuideDialog() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('User Guide'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8.0),
          child: Text(
            '1. Blood Sugar: Enter current mg/dL.\n\n'
            '2. Carbs: Sum items with plus signs (e.g., 15 + 25 + 10).\n\n'
            '3. Settings: Adjust Carb Ratio, Target, and Rounding below.',
            textAlign: TextAlign.left,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Got It', style: TextStyle(color: primaryCoral)),
          ),
        ],
      ),
    );
  }

  double _applyRounding(double rawDose) {
    if (_roundingSegment == 1) {
      return (rawDose * 2).round() / 2;
    } else if (_roundingSegment == 2) {
      return rawDose.roundToDouble();
    }
    return rawDose;
  }

  double _parseCarbInput(String input) {
    if (input.trim().isEmpty) return 0.0;
    List<String> parts = input.split('+');
    double sum = 0.0;
    for (String part in parts) {
      final trimmed = part.trim();
      if (trimmed.isNotEmpty) {
        double value = double.tryParse(trimmed) ?? 0.0;
        sum += value;
      }
    }
    return sum;
  }

  void _calculateDose() {
    final String bgText = _bgController.text.trim();
    final String carbText = _carbController.text.trim();

    if (bgText.isEmpty && carbText.isEmpty) {
      setState(() {
        _correctionDose = 0.0;
        _carbDose = 0.0;
        _rawTotalDose = 0.0;
        _displayTotalDose = 0.0;
        _totalCarbsSum = 0.0;
      });
      return;
    }

    final double bg = double.tryParse(bgText) ?? 0.0;
    final double carbs = _parseCarbInput(carbText);

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

  Widget _buildIOSCard({required List<Widget> children}) {
    final isDark = widget.isDarkMode;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildIOSTextField({
    required TextEditingController controller,
    required String placeholder,
    required IconData icon,
    required Color iconColor,
    TextInputType keyboardType = TextInputType.number,
    Function(String)? onChanged,
  }) {
    final isDark = widget.isDarkMode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              onChanged: onChanged,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
              ),
              decoration: InputDecoration.collapsed(
                hintText: placeholder,
                hintStyle: TextStyle(
                  color: isDark ? const Color(0xFF8E8E93) : const Color(0xFFC7C7CC),
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        elevation: 0.5,
        title: const Text(
          'Insulin Calculator',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Icon(
                  isDark ? CupertinoIcons.moon_fill : CupertinoIcons.sun_max_fill,
                  size: 18,
                  color: isDark ? secondaryOrange : primaryCoral,
                ),
                const SizedBox(width: 6),
                CupertinoSwitch(
                  value: widget.isDarkMode,
                  activeColor: primaryCoral,
                  onChanged: widget.onThemeChanged,
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildIOSCard(
              children: [
                _buildIOSTextField(
                  controller: _bgController,
                  placeholder: 'Blood Sugar (mg/dL)',
                  icon: CupertinoIcons.drop_fill,
                  iconColor: primaryCoral,
                ),
                Divider(height: 1, indent: 48, color: isDark ? Colors.white10 : Colors.black12),
                _buildIOSTextField(
                  controller: _carbController,
                  placeholder: 'Total Carbs (e.g. 15 + 30)',
                  icon: CupertinoIcons.add_circled_solid,
                  iconColor: secondaryOrange,
                  keyboardType: TextInputType.text,
                ),
              ],
            ),
            if (_showTips) ...[
              const Padding(
                padding: EdgeInsets.only(left: 12, top: 6, bottom: 12),
                child: Text(
                  '💡 Tip: Type multiple numbers with + to sum items automatically.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ] else
              const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                color: primaryCoral,
                borderRadius: BorderRadius.circular(12),
                onPressed: _calculateDose,
                child: const Text(
                  'Calculate Dose',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 16),

            _buildIOSCard(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Text(
                        'RECOMMENDED DOSE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_displayTotalDose.toStringAsFixed(1)} Units',
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.bold,
                          color: secondaryOrange,
                        ),
                      ),
                      if (_roundingSegment != 0 && _rawTotalDose != _displayTotalDose) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Exact: ${_rawTotalDose.toStringAsFixed(2)} u',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Column(
                            children: [
                              const Text('Correction', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              const SizedBox(height: 2),
                              Text('${_correctionDose.toStringAsFixed(1)} u', style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                          Container(height: 24, width: 1, color: isDark ? Colors.white10 : Colors.black12),
                          Column(
                            children: [
                              const Text('Carbs', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              const SizedBox(height: 2),
                              Text('${_totalCarbsSum.toStringAsFixed(1)} g', style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                          Container(height: 24, width: 1, color: isDark ? Colors.white10 : Colors.black12),
                          Column(
                            children: [
                              const Text('Carb Dose', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              const SizedBox(height: 2),
                              Text('${_carbDose.toStringAsFixed(1)} u', style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            const Padding(
              padding: EdgeInsets.only(left: 12, bottom: 6),
              child: Text(
                'FORMULA SETTINGS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
            ),

            _buildIOSCard(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Show Tips', style: TextStyle(fontSize: 16)),
                      CupertinoSwitch(
                        value: _showTips,
                        activeColor: primaryCoral,
                        onChanged: (val) {
                          setState(() => _showTips = val);
                          _saveSetting('showAppTips', val);
                        },
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, indent: 16, color: isDark ? Colors.white10 : Colors.black12),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Rounding Mode', style: TextStyle(fontSize: 13, color: Colors.grey)),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: CupertinoSegmentedControl<int>(
                          selectedColor: primaryCoral,
                          borderColor: primaryCoral,
                          groupValue: _roundingSegment,
                          children: const {
                            0: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Exact', style: TextStyle(fontSize: 13))),
                            1: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Nearest 0.5', style: TextStyle(fontSize: 13))),
                            2: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Nearest 1.0', style: TextStyle(fontSize: 13))),
                          },
                          onValueChanged: (val) {
                            setState(() {
                              _roundingSegment = val;
                              _calculateDose();
                            });
                            _saveSetting('savedRoundingSegment', val);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, indent: 16, color: isDark ? Colors.white10 : Colors.black12),
                _buildIOSTextField(
                  controller: _ratioController,
                  placeholder: 'Carb Ratio (1u per X grams)',
                  icon: CupertinoIcons.slider_horizontal_3,
                  iconColor: secondaryOrange,
                  onChanged: (val) => _saveSetting('savedCarbRatio', val),
                ),
                Divider(height: 1, indent: 48, color: isDark ? Colors.white10 : Colors.black12),
                _buildIOSTextField(
                  controller: _targetBgController,
                  placeholder: 'Target Blood Sugar (mg/dL)',
                  icon: CupertinoIcons.scope,
                  iconColor: primaryCoral,
                  onChanged: (val) => _saveSetting('savedTargetBg', val),
                ),
                Divider(height: 1, indent: 48, color: isDark ? Colors.white10 : Colors.black12),
                _buildIOSTextField(
                  controller: _correctionFactorController,
                  placeholder: 'Correction Factor',
                  icon: CupertinoIcons.graph_square_fill,
                  iconColor: secondaryOrange,
                  onChanged: (val) => _saveSetting('savedCorrectionFactor', val),
                ),
                Divider(height: 1, indent: 16, color: isDark ? Colors.white10 : Colors.black12),
                CupertinoButton(
                  onPressed: _showGuideDialog,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.book, size: 18, color: primaryCoral),
                      SizedBox(width: 6),
                      Text('Open User Guide', style: TextStyle(color: primaryCoral, fontSize: 16)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
