import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_settings.dart';
import '../../model_downloader.dart';
import '../screens/model_settings_screen.dart';
import '../screens/placeholder_screen.dart';

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
    return Drawer(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.5),
          border: Border(
            right: BorderSide(
              color: Colors.white.withOpacity(0.3),
              width: 1.0,
            ),
          ),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Header
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PlaceholderScreen(title: "User Account")),
                  );
                },
                child: DrawerHeader(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const CircleAvatar(
                        backgroundColor: Colors.white,
                        radius: 30,
                        child: FaIcon(FontAwesomeIcons.user, color: Color(0xFF4FACFE)),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'User Account',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'user@example.com',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Font Size
              ListTile(
                leading: const FaIcon(FontAwesomeIcons.textHeight, color: Colors.white),
                title: Text('Font Size', style: GoogleFonts.outfit(color: Colors.white)),
                subtitle: Slider(
                  value: widget.settings.fontSize,
                  min: 12.0,
                  max: 24.0,
                  divisions: 6,
                  label: widget.settings.fontSize.round().toString(),
                  onChanged: (value) {
                    setState(() {
                      widget.settings.setFontSize(value);
                    });
                    widget.onFontSizeChanged(value);
                  },
                ),
              ),

              // Dark Mode
              SwitchListTile(
                secondary: const FaIcon(FontAwesomeIcons.moon, color: Colors.white),
                title: Text('Dark Mode', style: GoogleFonts.outfit(color: Colors.white)),
                value: widget.settings.isDarkMode,
                onChanged: (value) {
                  setState(() {
                    widget.settings.setDarkMode(value);
                  });
                  widget.onThemeChanged(value);
                },
              ),

              const Divider(color: Colors.white24),

              // New Menu Items
              ListTile(
                leading: const FaIcon(FontAwesomeIcons.gear, color: Colors.white),
                title: Text('Configuration', style: GoogleFonts.outfit(color: Colors.white)),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PlaceholderScreen(title: "Configuration")),
                  );
                },
              ),
              ListTile(
                leading: const FaIcon(FontAwesomeIcons.language, color: Colors.white),
                title: Text('Language (English)', style: GoogleFonts.outfit(color: Colors.white)),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PlaceholderScreen(title: "Language")),
                  );
                },
              ),
              ListTile(
                leading: const FaIcon(FontAwesomeIcons.image, color: Colors.white),
                title: Text('Background', style: GoogleFonts.outfit(color: Colors.white)),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PlaceholderScreen(title: "Background")),
                  );
                },
              ),
              ListTile(
                leading: const FaIcon(FontAwesomeIcons.sliders, color: Colors.white),
                title: Text('Model Settings', style: GoogleFonts.outfit(color: Colors.white)),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => ModelSettingsScreen(settings: widget.settings)),
                  );
                },
              ),

              const Divider(color: Colors.white24),

              // Model Selection
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'AI Model',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              
              ...AppSettings.availableModels.map((model) {
                return RadioListTile<String>(
                  title: Text(model.name, style: GoogleFonts.outfit(color: Colors.white)),
                  subtitle: Text("${model.filename} (${model.sizeMB.toInt()} MB)", style: GoogleFonts.outfit(fontSize: 10, color: Colors.white70)),
                  value: model.filename,
                  groupValue: widget.settings.selectedModelFilename,
                  activeColor: Colors.white,
                  onChanged: (value) async {
                    if (value != null) {
                      final isDownloaded = await _downloader.isModelDownloaded(model.filename);
                      if (isDownloaded) {
                        _selectModel(model);
                      } else {
                        _showDownloadDialog(model);
                      }
                    }
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _selectModel(ModelConfig model) {
    setState(() {
      widget.settings.setSelectedModel(model.filename);
    });
    widget.onModelChanged(model.url, model.filename);
  }

  void _showDownloadDialog(ModelConfig model) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadDialog(model: model, onCompleted: () => _selectModel(model)),
    );
  }
}

class _DownloadDialog extends StatefulWidget {
  final ModelConfig model;
  final VoidCallback onCompleted;

  const _DownloadDialog({required this.model, required this.onCompleted});

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
    return AlertDialog(
      backgroundColor: Colors.white.withOpacity(0.95),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text("Download Model", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Model: ${widget.model.name}", style: GoogleFonts.outfit()),
          Text("Size: ~${widget.model.sizeMB.toInt()} MB", style: GoogleFonts.outfit()),
          const SizedBox(height: 20),
          if (_isDownloading) ...[
            LinearProgressIndicator(value: _progress, backgroundColor: Colors.grey[300], valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4FACFE))),
            const SizedBox(height: 10),
            Text("${(_progress * 100).toStringAsFixed(1)}%", style: GoogleFonts.outfit(fontSize: 12)),
          ] else
            Text(_status, style: GoogleFonts.outfit(color: Colors.grey)),
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
          child: Text("Cancel", style: GoogleFonts.outfit(color: Colors.red)),
        ),
        if (!_isDownloading)
          ElevatedButton(
            onPressed: _startDownload,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4FACFE)),
            child: Text(_progress > 0 ? "Resume" : "Download", style: GoogleFonts.outfit(color: Colors.white)),
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
