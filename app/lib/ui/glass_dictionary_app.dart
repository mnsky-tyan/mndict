import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../services/app_settings.dart';
import '../../services/dictionary_service.dart';
import '../../services/vocabulary_service.dart';
import 'theme/glass_theme.dart';
import 'widgets/aurora_background.dart';
import 'widgets/aurora_orb.dart';
import 'widgets/bottom_nav_bar.dart';
import 'widgets/definition_card.dart';
import 'widgets/glass_container.dart';
import 'widgets/glass_page.dart';
import 'widgets/pressable.dart';
import 'widgets/search_bar.dart';
import 'widgets/side_menu.dart';
import 'widgets/vocabulary_detail_popup.dart';
import 'screens/home_view.dart';
import 'screens/test_screen.dart';

class GlassDictionaryApp extends StatefulWidget {
  const GlassDictionaryApp({super.key});

  @override
  State<GlassDictionaryApp> createState() => _GlassDictionaryAppState();
}

class _GlassDictionaryAppState extends State<GlassDictionaryApp>
    with TickerProviderStateMixin {
  final AppSettings _settings = AppSettings();
  DictionaryService? _dictionaryService;
  late VocabularyService _vocabularyService;

  final TextEditingController _searchController = TextEditingController();

  // Scale-reveal drawer: the whole app steps back while the menu is
  // revealed underneath — no ordinary side slide.
  late final AnimationController _drawerC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 0,
  );
  late final CurvedAnimation _drawerCurve = CurvedAnimation(
    parent: _drawerC,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  // Fractional page position (0..3). Drives the page slide, the nav lens
  // and the top-bar title crossfade from one clock, so a drag scrubs all
  // three together — nothing animates "after" the finger.
  // Bounds extend past the page range on purpose: a drag rubber-bands up
  // to 0.24 pages past the ends, and the default [0, 1] bounds would
  // silently clamp every animateTo back to 1.0.
  late final AnimationController _pagesC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 0,
    lowerBound: -0.5,
    upperBound: 3.5,
  );

  // Streaming tokens go through this notifier so only the definition card
  // rebuilds per token, not the whole scaffold.
  final ValueNotifier<String> _definition = ValueNotifier('');
  String get _definitionContent => _definition.value;

  int _currentIndex = 0;
  String _currentWord = "";
  bool _isLoading = false;
  bool _isSaved = false;
  String? _statusMessage;

  // Token gate: clearing the search retires the in-flight lookup so late
  // tokens from the discarded generation can't resurrect the card.
  bool _acceptTokens = false;

  @override
  void initState() {
    super.initState();
    _vocabularyService = VocabularyService();
    // Rebuild when the drawer fully opens/closes so PopScope's canPop and
    // the menu button stay in sync.
    _drawerC.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        if (mounted) setState(() {});
      }
    });
    _init();
  }

  Future<void> _init() async {
    await _settings.init();
    await _vocabularyService.init();

    _dictionaryService = DictionaryService(_settings);

    // Subscribe BEFORE init(): the status stream is broadcast, so statuses
    // emitted during init (model checks, loading, ready) would be dropped.
    _dictionaryService!.tokenStream.listen(
      (token) {
        if (!_acceptTokens) return;
        _definition.value += token;
        if (_isLoading) {
          setState(() => _isLoading = false);
        }
      },
      onError: (e) {
        setState(() {
          _definition.value = "Error: $e";
          _isLoading = false;
        });
      },
    );

    _dictionaryService!.statusStream.listen((status) {
      print("Status: $status");
      setState(() => _statusMessage = status);
      if (status.toLowerCase() == "done" ||
          status.startsWith("Error") ||
          status.startsWith("Failed")) {
        if (_isLoading) {
          setState(() => _isLoading = false);
        }
      }
    });

    await _dictionaryService!.init();

    setState(() {});
  }

  @override
  void dispose() {
    _drawerC.dispose();
    _pagesC.dispose();
    _dictionaryService?.dispose();
    _searchController.dispose();
    _definition.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    if (query.isEmpty) return;
    // Ignore re-submits while a lookup is streaming — a second submit would
    // clear the content buffer and swallow the first tokens.
    if (_isLoading) return;

    HapticFeedback.lightImpact();
    setState(() {
      _currentWord = query;
      _definition.value = "";
      _isLoading = true;
      _isSaved = _vocabularyService.isWordSaved(query);
    });

    _acceptTokens = true;
    _dictionaryService?.searchWord(query);
  }

  /// The (x) on the search bar: back to the idle orb, and any definition
  /// still streaming is retired mid-flight.
  void _handleClearSearch() {
    setState(() {
      _currentWord = "";
      _definition.value = "";
      _isLoading = false;
      _isSaved = false;
      _acceptTokens = false;
    });
  }

  void _toggleSave() async {
    if (_currentWord.isEmpty) return;

    if (_isSaved) {
      await _vocabularyService.removeWord(_currentWord);
    } else {
      await _vocabularyService.saveWord(_currentWord, _definitionContent);
      await _settings.addCoins(1);
      HapticFeedback.heavyImpact();
    }

    setState(() {
      _isSaved = !_isSaved;
    });
  }

  void _onNavTapped(int index) {
    // Leaving the field — by tab switch or by tapping the active tab —
    // always drops the keyboard.
    _dismissKeyboard();
    if (index != _currentIndex) {
      HapticFeedback.selectionClick();
      setState(() {
        _currentIndex = index;
        _closeVocabularyPopup();
      });
    }
    // Also runs when the index is unchanged: a page drag that snaps back
    // (or rubber-bands past an edge) still has to settle the controller.
    _pagesC.animateTo(
      index.toDouble(),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  /// The page drag began — the pager handles the scrub itself; the app only
  /// lets go of the keyboard so swiping never fights with the IME.
  void _onPageDragStart() {
    _dismissKeyboard();
  }

  /// Heading content for tab [i]: the live search bar on tab 0, a plain
  /// title elsewhere.
  Widget _topBarLayer(int i, GlassPalette p) {
    if (i == 0) {
      return GlassSearchBar(
        key: const ValueKey('search'),
        controller: _searchController,
        onSubmitted: _onSearch,
        onClear: _handleClearSearch,
      );
    }
    return Container(
      key: ValueKey('title-$i'),
      height: 48,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        const ['', 'Vocabulary', 'Test', 'Home'][i],
        style: GlassText.display(p, 20, weight: FontWeight.w600),
      ),
    );
  }

  void _openDrawer() {
    // The menu takes over the screen; a keyboard fighting with it feels
    // broken, so the search field lets go first.
    _dismissKeyboard();
    HapticFeedback.lightImpact();
    _drawerC.forward();
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = _settings.isDarkMode ? GlassPalette.dark : GlassPalette.light;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final screenWidth = MediaQuery.of(context).size.width;

    return GlassScope(
      palette: p,
      fontSize: _settings.fontSize,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: p.isDark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: p.isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: p.isDark
              ? Brightness.light
              : Brightness.dark,
        ),
        child: PopScope(
          canPop: _drawerC.isDismissed,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !_drawerC.isDismissed) {
              _drawerC.reverse();
            }
          },
          child: AnimatedBuilder(
            animation: _drawerCurve,
            builder: (context, scaffold) {
              final t = _drawerCurve.value;
              return Stack(
                children: [
                  Positioned.fill(child: scaffold!),
                  // Scrim
                  if (t > 0)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => _drawerC.reverse(),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.42 * t),
                        ),
                      ),
                    ),
                  // The menu: a rounded glass panel floating over the
                  // receding app, not a full-bleed sheet with sharp edges.
                  if (t > 0)
                    Positioned(
                      top: 12,
                      bottom: 12,
                      left: 12,
                      width: math.min(screenWidth * 0.80, 330.0),
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(-1.16, 0),
                          end: Offset.zero,
                        ).animate(_drawerCurve),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(34),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    Colors.black.withValues(alpha: 0.42 * t),
                                blurRadius: 46,
                                offset: const Offset(8, 12),
                                spreadRadius: -6,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(34),
                            child: SideMenu(
                              settings: _settings,
                              onThemeChanged: (val) => setState(() {}),
                              onFontSizeChanged: (val) => setState(() {}),
                              onModelChanged: (url, filename) {
                                _dictionaryService?.checkAndLoadModel();
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
            // The app itself: scales back and rounds off as the menu opens.
            child: Scaffold(
              backgroundColor: Colors.transparent,
              // The keyboard overlays instead of squeezing the layout — no jump
              // when focus enters the search field.
              resizeToAvoidBottomInset: false,
              body: AnimatedBuilder(
                animation: _drawerCurve,
                builder: (context, child) {
                  final t = _drawerCurve.value;
                  return Transform.translate(
                    offset: Offset(52 * t, 0),
                    child: Transform.scale(
                      scale: 1 - 0.06 * t,
                      alignment: Alignment.centerLeft,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(34 * t),
                        child: child,
                      ),
                    ),
                  );
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AuroraBackground(
                        child: SafeArea(
                          bottom: false,
                          child: Column(
                            children: [
                              // Top bar: menu + (search field on the Search
                              // tab, tab title elsewhere).
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  10,
                                  20,
                                  4,
                                ),
                                child: Row(
                                  children: [
                                    GlassIconButton(
                                      icon: FontAwesomeIcons.bars,
                                      onTap: _openDrawer,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      // The heading rides the same clock as
                                      // the pages: it slides and fades with
                                      // the drag instead of cross-fading on
                                      // its own after release. Layers slide
                                      // in opposite directions, so titles
                                      // never overlap mid-transition.
                                      child: AnimatedBuilder(
                                        animation: _pagesC,
                                        builder: (context, _) {
                                          final v = _pagesC.value.clamp(
                                            0.0,
                                            3.0,
                                          );
                                          return Stack(
                                            alignment: Alignment.centerLeft,
                                            children: [
                                              for (var i = 0; i < 4; i++)
                                                if ((v - i).abs() < 0.5)
                                                  IgnorePointer(
                                                    ignoring:
                                                        i != _currentIndex,
                                                    child: Opacity(
                                                      opacity:
                                                          (1 - (v - i).abs() * 2)
                                                              .clamp(0.0, 1.0),
                                                      child: Transform
                                                          .translate(
                                                        offset: Offset(
                                                          (i - v) *
                                                              screenWidth *
                                                              0.32,
                                                          0,
                                                        ),
                                                        child: _topBarLayer(
                                                            i, p),
                                                      ),
                                                    ),
                                                  ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Model status, surfaced from the service's status stream
                              AnimatedSize(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: _buildStatusStrip(p),
                              ),
                              Expanded(
                                // Taps on empty page space (not on buttons,
                                // which win the gesture arena) let go of the
                                // search field's focus.
                                child: GestureDetector(
                                  onTap: _dismissKeyboard,
                                  behavior: HitTestBehavior.translucent,
                                  child: _PageSwiper(
                                    position: _pagesC,
                                    onSettled: _onNavTapped,
                                    onDragStart: _onPageDragStart,
                                    children: [
                                      // Tab 0: Search (Dictionary)
                                      SizedBox.expand(
                                        child: Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            20,
                                            10,
                                            20,
                                            bottomInset + 96,
                                          ),
                                          child: ValueListenableBuilder<String>(
                                            valueListenable: _definition,
                                            builder: (context, content, _) {
                                              // The orb stays center-stage while
                                              // the model thinks; the card slides
                                              // in only once words start
                                              // arriving.
                                              return AnimatedSwitcher(
                                                duration: const Duration(
                                                  milliseconds: 320,
                                                ),
                                                switchInCurve:
                                                    Curves.easeOutCubic,
                                                switchOutCurve: Curves.easeIn,
                                                transitionBuilder:
                                                    (
                                                      child,
                                                      anim,
                                                    ) => FadeTransition(
                                                      opacity: anim,
                                                      child: SlideTransition(
                                                        position: Tween<Offset>(
                                                          begin: const Offset(
                                                            0,
                                                            0.06,
                                                          ),
                                                          end: Offset.zero,
                                                        ).animate(anim),
                                                        child: child,
                                                      ),
                                                    ),
                                                child: content.isEmpty
                                                    ? Center(
                                                        child: _SearchHint(
                                                          key: const ValueKey(
                                                            'hint',
                                                          ),
                                                          isLoading: _isLoading,
                                                          word: _currentWord,
                                                        ),
                                                      )
                                                    : DefinitionCard(
                                                        key: const ValueKey(
                                                          'card',
                                                        ),
                                                        content: content,
                                                        isLoading: _isLoading,
                                                        isSaved: _isSaved,
                                                        onSave: _toggleSave,
                                                        title:
                                                            _currentWord
                                                                .isNotEmpty
                                                            ? _currentWord
                                                            : null,
                                                      ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),

                                      // Tab 1: Vocabulary
                                      SizedBox.expand(
                                        child: Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            20,
                                            8,
                                            20,
                                            bottomInset + 96,
                                          ),
                                          child: _buildVocabularyList(p),
                                        ),
                                      ),

                                      // Tab 2: Test
                                      SizedBox.expand(
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            bottom: bottomInset + 88,
                                          ),
                                          child: TestScreen(
                                            vocabularyService:
                                                _vocabularyService,
                                            dictionaryService:
                                                _dictionaryService,
                                            settings: _settings,
                                          ),
                                        ),
                                      ),

                                      // Tab 3: Home
                                      SizedBox.expand(
                                        child: Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            20,
                                            8,
                                            20,
                                            bottomInset + 96,
                                          ),
                                          child: _buildHome(p),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Floating glass navigation
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: bottomInset + 12,
                      child: GlassBottomNavBar(
                        position: _pagesC,
                        onTap: _onNavTapped,
                      ),
                    ),
                    // Vocabulary detail bottom sheet
                    if (_selectedVocabularyItem != null)
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: bottomInset + 100,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(context).size.height * 0.60,
                          ),
                          child: VocabularyDetailPopup(
                            word: _selectedVocabularyItem!.word,
                            definition: _selectedVocabularyItem!.definition,
                            onClose: _closeVocabularyPopup,
                            onDelete: _deleteVocabularyItem,
                            onRefresh: _refreshVocabularyItem,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildStatusStrip(GlassPalette p) {
    final status = _statusMessage;
    if (status == null) return const SizedBox.shrink();
    final terminal = status == 'Ready' || status.toLowerCase() == 'done';
    if (terminal) return const SizedBox.shrink();

    final isBusy =
        status.contains('Loading') ||
        status.contains('Warming') ||
        status.contains('Checking');
    final isError = status.startsWith('Failed') || status.startsWith('Error');
    final isMissing = status.contains('not found');

    final dotColor = isError
        ? p.danger
        : (isBusy || isMissing)
        ? p.warn
        : p.success;

    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 20, right: 20),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GlassContainer(
          blur: 0,
          chrome: true,
          sheen: false,
          borderRadius: 999,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GlassText.body(
                    p,
                    11.5,
                    weight: FontWeight.w500,
                    color: p.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHome(GlassPalette p) {
    final model = _settings.currentModelConfig;
    final status = _statusMessage ?? 'Checking model…';
    final modelReady = status == 'Ready' || status == 'Model Loaded';
    final modelBusy =
        status.contains('Loading') ||
        status.contains('Warming') ||
        status.contains('Checking');

    return HomeView(
      wordCount: _vocabularyService
          .getSortedWords(SortType.latest, true)
          .length,
      coins: _settings.coins,
      modelName: model.name,
      modelFilename: model.filename,
      modelSizeMB: model.sizeMB,
      modelReady: modelReady,
      modelBusy: modelBusy,
      recentWords: _vocabularyService.getSortedWords(SortType.latest, true),
      onNav: _onNavTapped,
    );
  }

  Widget _buildVocabularyList(GlassPalette p) {
    final words = _vocabularyService.getSortedWords(_sortType, _isAscending);

    return Column(
      children: [
        // Sorting controls
        Row(
          children: [
            Expanded(
              child: GlassSegmented<SortType>(
                palette: p,
                value: _sortType,
                options: const [
                  ('Latest', SortType.latest),
                  ('A–Z', SortType.alphabetical),
                  ('Familiar', SortType.familiarity),
                ],
                onChanged: (val) => setState(() => _sortType = val),
              ),
            ),
            const SizedBox(width: 10),
            GlassIconButton(
              icon: _isAscending
                  ? FontAwesomeIcons.arrowUp
                  : FontAwesomeIcons.arrowDown,
              iconSize: 13,
              size: 42,
              iconColor: p.textSecondary,
              onTap: () => setState(() => _isAscending = !_isAscending),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // List
        Expanded(
          child: words.isEmpty
              ? _EmptyVocabulary(palette: p)
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: words.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = words[index];
                    return Pressable(
                      onTap: () => _showVocabularyPopup(item),
                      pressedScale: 0.98,
                      child: GlassContainer(
                        blur: 0,
                        borderRadius: 18,
                        padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.word,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GlassText.body(
                                      p,
                                      15,
                                      weight: FontWeight.w600,
                                      tracking: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.definition,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GlassText.body(
                                      p,
                                      12,
                                      color: p.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FaIcon(
                                FontAwesomeIcons.chevronRight,
                                size: 11,
                                color:
                                    p.textSecondary.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // Vocabulary State
  SortType _sortType = SortType.latest;
  bool _isAscending = false;
  VocabularyItem? _selectedVocabularyItem;

  // ... existing methods ...

  void _showVocabularyPopup(VocabularyItem item) {
    setState(() {
      _selectedVocabularyItem = item;
    });
  }

  void _closeVocabularyPopup() {
    setState(() {
      _selectedVocabularyItem = null;
    });
  }

  void _deleteVocabularyItem() async {
    if (_selectedVocabularyItem != null) {
      await _vocabularyService.removeWord(_selectedVocabularyItem!.word);
      _closeVocabularyPopup();
      setState(() {
        _isSaved = _vocabularyService.isWordSaved(_currentWord);
      });
    }
  }

  void _refreshVocabularyItem() {
    if (_selectedVocabularyItem != null) {
      // Regenerate by routing through the normal search path: it retires
      // stale tokens, resets the buffer and streams the new definition.
      final word = _selectedVocabularyItem!.word;
      _onNavTapped(0);
      _closeVocabularyPopup();
      _searchController.text = word;
      _onSearch(word);
    }
  }
}

class _SearchHint extends StatefulWidget {
  final bool isLoading;
  final String word;

  const _SearchHint({super.key, required this.isLoading, required this.word});

  @override
  State<_SearchHint> createState() => _SearchHintState();
}

class _SearchHintState extends State<_SearchHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = GlassScope.of(context).palette;
    final animate = !MediaQuery.disableAnimationsOf(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Gentle idle bob; the orb never stops being alive.
        final t = animate ? _controller.value * 2 * 3.14159 : 0.0;
        final bob = animate ? 5.5 * math.sin(t) : 0.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: Offset(0, bob),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: AuroraOrb(
                  key: ValueKey(widget.isLoading),
                  size: widget.isLoading ? 86 : 76,
                  glowBoost: widget.isLoading ? 1.6 : 1.0,
                ),
              ),
            ),
            const SizedBox(height: 22),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: Column(
                key: ValueKey(widget.isLoading),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.isLoading && widget.word.isNotEmpty
                        ? 'Looking up \u201C${widget.word}\u201D'
                        : 'Look up any word',
                    style: GlassText.display(p, 20),
                  ),
                  if (!widget.isLoading) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Words, phrases, idioms — definitions\nstream in, generated on this device.',
                      textAlign: TextAlign.center,
                      style: GlassText.body(
                        p,
                        13,
                        height: 1.5,
                        color: p.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyVocabulary extends StatelessWidget {
  final GlassPalette palette;

  const _EmptyVocabulary({required this.palette});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassContainer(
            width: 60,
            height: 60,
            borderRadius: 30,
            blur: 0,
            padding: EdgeInsets.zero,
            child: Center(
              child: FaIcon(
                FontAwesomeIcons.bookOpen,
                size: 18,
                color: p.accent,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Text('No saved words yet', style: GlassText.display(p, 17)),
          const SizedBox(height: 6),
          Text(
            'Look up a word and tap the heart\nto keep it here.',
            textAlign: TextAlign.center,
            style: GlassText.body(p, 12.5, height: 1.5, color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// iOS-style segmented control on a glass base.
class GlassSegmented<T> extends StatelessWidget {
  final GlassPalette palette;
  final T value;
  final List<(String, T)> options;
  final ValueChanged<T> onChanged;

  const GlassSegmented({
    super.key,
    required this.palette,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return GlassContainer(
      blur: 0,
      chrome: true,
      sheen: false,
      borderRadius: 20,
      padding: const EdgeInsets.all(3.5),
      child: Row(
        children: [
          for (final (label, item) in options)
            Expanded(
              child: Pressable(
                onTap: () => onChanged(item),
                pressedScale: 0.95,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: value == item
                        ? (p.isDark ? const Color(0xFF324066) : Colors.white)
                        : Colors.transparent,
                    boxShadow: value == item
                        ? [
                            BoxShadow(
                              color: p.shadow,
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : const [],
                  ),
                  child: Center(
                    child: Text(
                      label,
                      maxLines: 1,
                      style: GlassText.body(
                        p,
                        12,
                        weight: value == item
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: value == item ? p.textPrimary : p.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The four tab pages live in one Stack, all mounted (state preserved like
/// the old IndexedStack). A single fractional position [position] slides
/// them — and a horizontal drag scrubs it directly, so the pages, the nav
/// lens and the top-bar heading all track the finger exactly. Release
/// settles with the app's standard ease, fling velocity included.
class _PageSwiper extends StatefulWidget {
  final Animation<double> position;
  final List<Widget> children;

  /// Called with the target page when a drag ends or is cancelled. The
  /// app routes this through its normal nav handler, which settles the
  /// controller onto the target.
  final ValueChanged<int> onSettled;
  final VoidCallback? onDragStart;

  const _PageSwiper({
    required this.position,
    required this.children,
    required this.onSettled,
    this.onDragStart,
  });

  @override
  State<_PageSwiper> createState() => _PageSwiperState();
}

class _PageSwiperState extends State<_PageSwiper> {
  /// Cumulative unresisted drag target (position at drag start minus total
  /// delta), so
  /// the rubber band maps overshoot without ever losing motion.
  double _target = 0;
  int _notch = 0;

  void _onDragStart(DragStartDetails d) {
    widget.onDragStart?.call();
    final c = widget.position as AnimationController;
    c.stop();
    _target = c.value;
    _notch = c.value.round().clamp(0, widget.children.length - 1);
  }

  void _onDragUpdate(DragUpdateDetails d, double w) {
    final delta = d.primaryDelta;
    if (delta == null || w <= 0) return;

    final c = widget.position as AnimationController;
    final max = (widget.children.length - 1).toDouble();
    _target -= delta / w;
    // Rubber-band past the ends, like PageView's edge resistance: only
    // the overshoot part of the target is scaled down.
    double resolved;
    if (_target < 0) {
      resolved = _target * 0.28;
    } else if (_target > max) {
      resolved = max + (_target - max) * 0.28;
    } else {
      resolved = _target;
    }
    c.value = resolved.clamp(-0.24, max + 0.24);

    // A soft tick every time the finger crosses a page boundary.
    final notch = c.value.round().clamp(0, widget.children.length - 1);
    if (notch != _notch) {
      _notch = notch;
      HapticFeedback.selectionClick();
    }
  }

  void _settle(double velocityX) {
    final c = widget.position as AnimationController;
    final max = widget.children.length - 1;
    // Fling projection: velocity carries the settle up to ~a quarter page.
    final projected = (c.value - velocityX / 1400).clamp(0.0, max.toDouble());
    widget.onSettled(projected.round().clamp(0, max));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return GestureDetector(
          // Translucent: empty page space (padding, gaps, the area around
          // the hint) still starts a swipe even though no child claims the
          // hit — deferToChild would dead-zone exactly those areas.
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: (d) => _onDragUpdate(d, w),
          onHorizontalDragEnd: (d) =>
              _settle(d.velocity.pixelsPerSecond.dx),
          onHorizontalDragCancel: () => _settle(0),
          child: AnimatedBuilder(
            animation: widget.position,
            builder: (context, _) {
              final v = widget.position.value;
              return Stack(
                children: [
                  for (var i = 0; i < widget.children.length; i++)
                    _PageLayer(
                      position: widget.position,
                      index: i,
                      width: constraints.maxWidth,
                      visible: (v - i).abs() < 0.55,
                      child: widget.children[i],
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// One page in the swiper. Offstage (and its tickers stopped) whenever it
/// is farther than half a page from the position — the element stays in the
/// tree, so page state survives, but nothing paints or ticks.
class _PageLayer extends StatelessWidget {
  final Animation<double> position;
  final int index;
  final double width;
  final bool visible;
  final Widget child;

  const _PageLayer({
    required this.position,
    required this.index,
    required this.width,
    required this.visible,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final d = index - position.value;
    return IgnorePointer(
      ignoring: !visible,
      child: Offstage(
        offstage: !visible,
        child: TickerMode(
          enabled: visible,
          child: Transform.translate(
            offset: Offset(d * width, 0),
            // RepaintBoundary: the slide is a layer move, the page content
            // itself never repaints during the drag.
            child: RepaintBoundary(child: child),
          ),
        ),
      ),
    );
  }
}
