import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../services/api_key_store.dart';
import '../../services/app_settings.dart';
import '../../services/gemini_service.dart';
import '../theme/glass_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/glass_page.dart';
import '../widgets/pressable.dart';

enum _BadgeState { none, checking, valid, invalid, networkError }

/// Bring-your-own-key settings: masked display of the stored key, save with
/// a cheap credential check, and removal. Styled after ModelSettingsScreen.
class ApiKeyScreen extends StatefulWidget {
  final AppSettings? settings;
  final ApiKeyStore? keyStore;
  final Future<KeyValidation> Function(String key)? validate;

  const ApiKeyScreen({super.key, this.settings, this.keyStore, this.validate});

  @override
  State<ApiKeyScreen> createState() => _ApiKeyScreenState();
}

class _ApiKeyScreenState extends State<ApiKeyScreen> {
  late final ApiKeyStore _store =
      widget.keyStore ?? ApiKeyStore();
  final TextEditingController _input = TextEditingController();
  bool _obscured = true;
  bool _saving = false;
  String? _savedKey;
  _BadgeState _badge = _BadgeState.none;

  @override
  void initState() {
    super.initState();
    _reloadSavedKey();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _reloadSavedKey() async {
    final key = await _store.read();
    if (!mounted) return;
    setState(() => _savedKey = key);
  }

  Future<void> _saveAndVerify() async {
    final key = _input.text.trim();
    if (key.isEmpty || _saving) return;

    setState(() {
      _saving = true;
      _badge = _BadgeState.checking;
    });

    final check = widget.validate ?? GeminiService.validateApiKey;
    final result = await check(key);
    // The user's key is theirs to store: even when the check can't vouch
    // for it (rejected or network down) we save it — a lookup will say so
    // again, with the same actionable message.
    await _store.save(key);

    if (!mounted) return;
    setState(() {
      _saving = false;
      _badge = switch (result) {
        KeyValidation.valid => _BadgeState.valid,
        KeyValidation.invalid => _BadgeState.invalid,
        KeyValidation.networkError => _BadgeState.networkError,
      };
    });
    _reloadSavedKey();

    final p = _palette;
    final (message, background) = switch (result) {
      KeyValidation.valid => ('Key works', p.success),
      KeyValidation.invalid => ('Key rejected', p.danger),
      KeyValidation.networkError => ("Couldn't verify (network)", p.warn),
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(message, style: GlassText.body(p, 14, weight: FontWeight.w500)),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
    _input.clear();
  }

  Future<void> _removeKey() async {
    await _store.delete();
    if (!mounted) return;
    setState(() {
      _savedKey = null;
      _badge = _BadgeState.none;
    });
  }

  GlassPalette get _palette {
    final dark = widget.settings?.isDarkMode ?? false;
    return dark ? GlassPalette.dark : GlassPalette.light;
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette;

    return GlassPage(
      palette: p,
      title: 'API Key',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: GlassContainer(
          solid: true,
          borderRadius: 26,
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gemini API Key', style: GlassText.display(p, 20)),
              const SizedBox(height: 6),
              Text(
                'Lookups are answered by Google\u2019s Gemini API. Paste your '
                'key from Google AI Studio \u2014 it is stored only in this '
                'device\u2019s secure storage.',
                style:
                    GlassText.body(p, 12.5, height: 1.5, color: p.textSecondary),
              ),
              const SizedBox(height: 22),

              if (_savedKey != null) ...[
                _SavedKeyCard(
                  palette: p,
                  masked: ApiKeyStore.mask(_savedKey!),
                  badge: _badge,
                  onRemove: _removeKey,
                ),
                const SizedBox(height: 14),
              ],

              GlassContainer(
                blur: 0,
                borderRadius: 22,
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: TextField(
                  controller: _input,
                  obscureText: _obscured,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: GlassText.body(p, 15, height: 1.5),
                  cursorColor: p.accent,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Paste API key',
                    hintStyle: GlassText.body(p, 14, color: p.textSecondary),
                    suffixIcon: IconButton(
                      icon: FaIcon(
                        _obscured
                            ? FontAwesomeIcons.eye
                            : FontAwesomeIcons.eyeSlash,
                        size: 14,
                        color: p.textSecondary,
                      ),
                      onPressed: () => setState(() => _obscured = !_obscured),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: _saving ? '' : 'Save & Verify',
                  onTap: _saving ? null : _saveAndVerify,
                  leading: _saving
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: p.isDark
                                ? const Color(0xFF0B1020)
                                : Colors.white,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Saving runs a free key check \u2014 no tokens are spent.',
                style:
                    GlassText.body(p, 11.5, color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedKeyCard extends StatelessWidget {
  final GlassPalette palette;
  final String masked;
  final _BadgeState badge;
  final VoidCallback onRemove;

  const _SavedKeyCard({
    required this.palette,
    required this.masked,
    required this.badge,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return GlassContainer(
      blur: 0,
      sheen: false,
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: FaIcon(FontAwesomeIcons.key, size: 14, color: p.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saved key',
                    style: GlassText.body(p, 11, color: p.textSecondary)),
                const SizedBox(height: 2),
                Text(masked,
                    style: GlassText.body(p, 14.5,
                        weight: FontWeight.w600, tracking: 0.6)),
                const SizedBox(height: 6),
                _BadgeChip(palette: p, state: badge),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Pressable(
            onTap: onRemove,
            pressedScale: 0.94,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: FaIcon(FontAwesomeIcons.trashCan,
                  size: 14, color: p.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final GlassPalette palette;
  final _BadgeState state;

  const _BadgeChip({required this.palette, required this.state});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final (icon, color, label) = switch (state) {
      _BadgeState.valid => (
          FontAwesomeIcons.circleCheck,
          p.success,
          'Key works',
        ),
      _BadgeState.invalid => (
          FontAwesomeIcons.circleXmark,
          p.danger,
          'Key rejected',
        ),
      _BadgeState.networkError => (
          FontAwesomeIcons.wifi,
          p.warn,
          "Couldn't verify (network)",
        ),
      _BadgeState.checking => (
          FontAwesomeIcons.spinner,
          p.textSecondary,
          'Checking\u2026',
        ),
      _BadgeState.none => (
          FontAwesomeIcons.circleQuestion,
          p.textSecondary,
          'Not verified yet',
        ),
    };

    return GlassContainer(
      blur: 0,
      sheen: false,
      borderRadius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          state == _BadgeState.checking
              ? SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                )
              : FaIcon(icon, size: 10, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: GlassText.body(p, 11,
                  weight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
