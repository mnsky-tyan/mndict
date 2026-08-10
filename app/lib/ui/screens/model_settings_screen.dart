import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_settings.dart';
import '../widgets/glass_container.dart';

class ModelSettingsScreen extends StatefulWidget {
  final AppSettings settings;

  const ModelSettingsScreen({super.key, required this.settings});

  @override
  State<ModelSettingsScreen> createState() => _ModelSettingsScreenState();
}

class _ModelSettingsScreenState extends State<ModelSettingsScreen> {
  late double _temperature;
  late double _topP;
  late int _topK;

  @override
  void initState() {
    super.initState();
    _temperature = widget.settings.temperature;
    _topP = widget.settings.topP;
    _topK = widget.settings.topK;
  }

  void _saveSettings() {
    widget.settings.setModelParams(
      temp: _temperature,
      p: _topP,
      k: _topK,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Settings saved!', style: GoogleFonts.outfit()),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Model Settings',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          // Background Gradient (matching main app)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE0C3FC),
                  Color(0xFF8EC5FC),
                ],
              ),
            ),
          ),
          
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: GlassContainer(
                padding: const EdgeInsets.all(30),
                borderRadius: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Adjust LLM Parameters',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 30),
                    
                    // Temperature
                    Text(
                      'Temperature: ${_temperature.toStringAsFixed(2)}',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    Slider(
                      value: _temperature,
                      min: 0.0,
                      max: 2.0,
                      divisions: 20,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white.withOpacity(0.3),
                      onChanged: (value) => setState(() => _temperature = value),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Top P
                    Text(
                      'Top P: ${_topP.toStringAsFixed(2)}',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    Slider(
                      value: _topP,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white.withOpacity(0.3),
                      onChanged: (value) => setState(() => _topP = value),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Top K
                    Text(
                      'Top K: $_topK',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    Slider(
                      value: _topK.toDouble(),
                      min: 1,
                      max: 100,
                      divisions: 99,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white.withOpacity(0.3),
                      onChanged: (value) => setState(() => _topK = value.toInt()),
                    ),
                    
                    const SizedBox(height: 30),
                    
                    // Save Button
                    Center(
                      child: ElevatedButton(
                        onPressed: _saveSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4FACFE),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                        ),
                        child: Text('Save Settings', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
