import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/app_settings.dart';
import '../../services/model_downloader.dart';
import '../screens/model_settings_screen.dart';
import '../screens/placeholder_screen.dart';
import '../theme/glass_theme.dart';
import 'aurora_orb.dart';
import 'glass_container.dart';
import 'pressable.dart';
class SideMenu extends StatefulWidget {
  final AppSettings settings;
  final Function(bool) onThemeChanged;
  final Function(double) onFontSizeChanged;
  final Function(String, String) onModelChanged;

  const SideMenu({
    super.key,
    required this.settings,
    required this.onThemeChanged,
    required this.onFontSizeChanged,
    required this.onModelChanged,
  });

  @override
  State<SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<SideMenu> {
  final ModelDownloader _downloader = ModelDownloader();

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    final pad = MediaQuery.of(context).padding;

    // Standalone panel content: the app hosts this inside its own
    // scale-reveal overlay instead of a Material Drawer. The panel is
    // painted glass — a real backdrop blur here re-blurs the scaling app
    // every frame of the reveal and reads as a whole-screen blur flash.
    // Rounded corners + a soft inner rim: the panel is a floating card,
    // not a full-bleed sheet, so every edge is deliberately drawn.
    return Material(
      type: MaterialType.transparency,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: p.surface.withValues(alpha: p.isDark ? 0.90 : 0.96),
          borderRadius: BorderRadius.circular(33),
          border: Border.all(
            color: p.isDark
                ? const Color(0x2EFFFFFF)
                : const Color(0xA6FFFFFF),
            width: 1,
          ),
        ),
        child: SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, pad.bottom + 24),
              children: [
                // Header
                Pressable(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              const PlaceholderScreen(title: "User Account")),
                    );
                  },
                  pressedScale: 0.98,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                    child: Row(
                      children: [
                        GlassContainer(
                          width: 52,
                          height: 52,
                          borderRadius: 26,
                          blur: 0,
                          sheen: false,
                          padding: EdgeInsets.zero,
                          child: Center(
                            // The orb is the app's brand mark — it anchors
                            // the menu the way it anchors the search page.
                            child: AuroraOrb(size: 32),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('mndict',
                                  style: GlassText.display(p, 22)),
                              const SizedBox(height: 2),
                              Text('Offline AI dictionary',
                                  style: GlassText.body(p, 13,
                                      color: p.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 26),
                Text('PREFERENCES', style: GlassText.eyebrow(p)),
                const SizedBox(height: 10),
                GlassContainer(
                  blur: 0,
                  sheen: false,
                  borderRadius: 20,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      // Font size
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 16, 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 22,
                              child: FaIcon(FontAwesomeIcons.textHeight,
                                  size: 14, color: p.textSecondary),
                            ),
                            const SizedBox(width: 12),
                            Text('Text size',
                                style: GlassText.body(p, 14.5,
                                    weight: FontWeight.w500)),
                            const SizedBox(width: 8),
                            Text('A',
                                style: GlassText.body(p, 11,
                                    color: p.textSecondary)),
                            Expanded(
                              child: SliderTheme(
                                data: _sliderTheme(p),
                                child: Slider(
                                  value: widget.settings.fontSize,
                                  min: 12.0,
                                  max: 24.0,
                                  divisions: 6,
                                  label:
                                      widget.settings.fontSize.round().toString(),
                                  onChanged: (value) {
                                    setState(() {
                                      widget.settings.setFontSize(value);
                                    });
                                    widget.onFontSizeChanged(value);
                                  },
                                ),
                              ),
                            ),
                            Text('A',
                                style: GlassText.body(p, 17,
                                    weight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 14), color: p.hairline),
                      // Dark mode
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 22,
                              child: FaIcon(FontAwesomeIcons.moon,
                                  size: 14, color: p.textSecondary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text('Dark mode',
                                  style: GlassText.body(p, 14.5,
                                      weight: FontWeight.w500)),
                            ),
                            CupertinoSwitch(
                              value: widget.settings.isDarkMode,
                              activeTrackColor: p.accent,
                              onChanged: (value) {
                                setState(() {
                                  widget.settings.setDarkMode(value);
                                });
                                widget.onThemeChanged(value);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),
                Text('AI MODEL', style: GlassText.eyebrow(p)),
                const SizedBox(height: 10),
                ...AppSettings.availableModels.map((model) {
                  final selected =
                      model.filename == widget.settings.selectedModelFilename;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassContainer(
                      blur: 0,
                      sheen: false,
                      borderRadius: 18,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      border: selected
                          ? Border.all(color: p.accent, width: 1.2)
                          : null,
                      child: Pressable(
                        onTap: () async {
                          final isDownloaded = await _downloader
                              .isModelDownloaded(model.filename,
                                  expectedMB: model.sizeMB);
                          if (isDownloaded) {
                            _selectModel(model);
                          } else {
                            _showDownloadDialog(model);
                          }
                        },
                        pressedScale: 0.98,
                        child: Row(
                          children: [
                            _ModelCheck(palette: p, selected: selected),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    model.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GlassText.body(p, 14,
                                        weight: FontWeight.w600,
                                        color: selected
                                            ? p.accent
                                            : p.textPrimary),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    model.filename,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GlassText.body(p, 10.5,
                                        color: p.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('~${model.sizeMB.toInt()} MB',
                                style: GlassText.body(p, 10.5,
                                    color: p.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 14),
                Text('MORE', style: GlassText.eyebrow(p)),
                const SizedBox(height: 10),
                GlassContainer(
                  blur: 0,
                  sheen: false,
                  borderRadius: 20,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      _MenuRow(
                        palette: p,
                        icon: FontAwesomeIcons.gear,
                        label: 'Configuration',
                        onTap: () => _push(const PlaceholderScreen(
                            title: "Configuration")),
                      ),
                      _hairline(p),
                      _MenuRow(
                        palette: p,
                        icon: FontAwesomeIcons.language,
                        label: 'Language (English)',
                        onTap: () => _push(const PlaceholderScreen(
                            title: "Language")),
                      ),
                      _hairline(p),
                      _MenuRow(
                        palette: p,
                        icon: FontAwesomeIcons.image,
                        label: 'Background',
                        onTap: () => _push(const PlaceholderScreen(
                            title: "Background")),
                      ),
                      _hairline(p),
                      _MenuRow(
                        palette: p,
                        icon: FontAwesomeIcons.sliders,
                        label: 'Model Settings',
                        onTap: () => _push(ModelSettingsScreen(
                            settings: widget.settings)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  Widget _hairline(GlassPalette p) => Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: p.hairline);

  void _push(Widget screen) {
    Navigator.push(
        context, CupertinoPageRoute<void>(builder: (context) => screen));
  }

  SliderThemeData _sliderTheme(GlassPalette p) {
    return SliderThemeData(
      activeTrackColor: p.accent,
      inactiveTrackColor: p.hairline,
      thumbColor: p.isDark ? p.textPrimary : Colors.white,
      overlayColor: p.accent.withValues(alpha: 0.15),
      trackHeight: 3,
    );
  }

  void _selectModel(ModelConfig model) {
    setState(() {
      widget.settings.setSelectedModel(model.filename);
    });
    widget.onModelChanged(model.url, model.filename);
  }

  void _showDownloadDialog(ModelConfig model) {
    final p = GlassScope.of(context).palette;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadDialog(
          model: model,
          palette: p,
          onCompleted: () => _selectModel(model)),
    );
  }
}

class _ModelCheck extends StatelessWidget {
  final GlassPalette palette;
  final bool selected;

  const _ModelCheck({required this.palette, required this.selected});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? p.accent : Colors.transparent,
        border: selected ? null : Border.all(color: p.hairline, width: 1.5),
      ),
      child: selected
          ? Center(
              child: FaIcon(FontAwesomeIcons.check,
                  size: 10,
                  color: p.isDark ? const Color(0xFF0B1020) : Colors.white),
            )
          : null,
    );
  }
}

class _MenuRow extends StatelessWidget {
  final GlassPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuRow({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Pressable(
      onTap: onTap,
      pressedScale: 0.97,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: FaIcon(icon, size: 14, color: p.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: GlassText.body(p, 14.5, weight: FontWeight.w500)),
            ),
            FaIcon(FontAwesomeIcons.chevronRight,
                size: 11, color: p.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _DownloadDialog extends StatefulWidget {
  final ModelConfig model;
  final GlassPalette palette;
  final VoidCallback onCompleted;

  const _DownloadDialog({
    required this.model,
    required this.palette,
    required this.onCompleted,
  });

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  final ModelDownloader _downloader = ModelDownloader();
  double _progress = 0.0;
  bool _isDownloading = false;
  String _status = "Ready to download";

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;

    return AlertDialog(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text("Download model",
          style: GlassText.display(p, 18, weight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Model: ${widget.model.name}",
              style: GlassText.body(p, 14)),
          const SizedBox(height: 4),
          Text("Size: ~${widget.model.sizeMB.toInt()} MB",
              style: GlassText.body(p, 14, color: p.textSecondary)),
          const SizedBox(height: 20),
          if (_isDownloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 6,
                backgroundColor: p.hairline,
                valueColor: AlwaysStoppedAnimation<Color>(p.accent),
              ),
            ),
            const SizedBox(height: 10),
            Text("${(_progress * 100).toStringAsFixed(1)}%",
                style: GlassText.body(p, 12,
                    color: p.textSecondary, weight: FontWeight.w600)),
          ] else
            Text(_status,
                style: GlassText.body(p, 13, color: p.textSecondary)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (_isDownloading) {
              _downloader.cancelDownload();
            }
            Navigator.pop(context);
          },
          child: Text("Cancel",
              style: GlassText.body(p, 14,
                  weight: FontWeight.w600, color: p.textSecondary)),
        ),
        if (!_isDownloading)
          ElevatedButton(
            onPressed: _startDownload,
            style: ElevatedButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor:
                  p.isDark ? const Color(0xFF0B1020) : Colors.white,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: Text(_progress > 0 ? "Resume" : "Download",
                style: GlassText.body(p, 14, weight: FontWeight.w600,
                    color: p.isDark
                        ? const Color(0xFF0B1020)
                        : Colors.white)),
          ),
      ],
    );
  }

  void _startDownload() async {
    setState(() {
      _isDownloading = true;
      _status = "Downloading...";
    });

    try {
      await _downloader.downloadModel(
        widget.model.url,
        widget.model.filename,
        (progress) {
          setState(() {
            _progress = progress;
          });
        },
      );

      if (mounted) {
        Navigator.pop(context); // Close dialog
        widget.onCompleted(); // Select model
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          // Friendly error message
          _status = "Download paused. Tap to continue.";
        });
      }
    }
  }
}
