import 'package:flutter/material.dart';
import '../../services/app_settings.dart';
import '../theme/glass_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/glass_page.dart';

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
        content: Text('Settings saved!',
            style: GlassText.body(GlassPalette.light, 14,
                weight: FontWeight.w500)),
        backgroundColor: GlassPalette.light.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.settings.isDarkMode;
    final p = dark ? GlassPalette.dark : GlassPalette.light;

    return GlassPage(
      palette: p,
      title: 'Model Settings',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: GlassContainer(
          solid: true,
          borderRadius: 26,
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Adjust LLM Parameters',
                  style: GlassText.display(p, 20)),
              const SizedBox(height: 6),
              Text(
                'These control how the model writes. Higher temperature is more creative, lower is more literal.',
                style: GlassText.body(p, 12.5,
                    height: 1.5, color: p.textSecondary),
              ),
              const SizedBox(height: 22),

              _ParamSlider(
                palette: p,
                label: 'Temperature',
                valueLabel: _temperature.toStringAsFixed(2),
                slider: Slider(
                  value: _temperature,
                  min: 0.0,
                  max: 2.0,
                  divisions: 20,
                  onChanged: (value) =>
                      setState(() => _temperature = value),
                ),
              ),

              _ParamSlider(
                palette: p,
                label: 'Top P',
                valueLabel: _topP.toStringAsFixed(2),
                slider: Slider(
                  value: _topP,
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  onChanged: (value) => setState(() => _topP = value),
                ),
              ),

              _ParamSlider(
                palette: p,
                label: 'Top K',
                valueLabel: '$_topK',
                slider: Slider(
                  value: _topK.toDouble(),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  onChanged: (value) => setState(() => _topK = value.toInt()),
                ),
              ),

              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'Save Settings',
                  onTap: _saveSettings,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParamSlider extends StatelessWidget {
  final GlassPalette palette;
  final String label;
  final String valueLabel;
  final Widget slider;

  const _ParamSlider({
    required this.palette,
    required this.label,
    required this.valueLabel,
    required this.slider,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: GlassText.body(p, 14, weight: FontWeight.w500)),
            const Spacer(),
            GlassContainer(
              blur: 0,
              sheen: false,
              borderRadius: 12,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              child: Text(
                valueLabel,
                style: GlassText.body(p, 12.5,
                    weight: FontWeight.w600, color: p.accent),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: p.accent,
            inactiveTrackColor: p.hairline,
            thumbColor: p.isDark ? p.textPrimary : Colors.white,
            overlayColor: p.accent.withValues(alpha: 0.15),
            trackHeight: 3,
          ),
          child: slider,
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}
