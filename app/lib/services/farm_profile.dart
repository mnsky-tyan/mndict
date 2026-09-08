import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_settings.dart';
import 'pig_service.dart';
import 'worlds.dart';

/// A floating feedback crumb: "+1 🪙 · +4 XP", a quest payout, a badge.
/// The app overlays a chip queue wherever these land.
class RewardEvent {
  final String label; // already emoji-decorated
  final bool celebrate; // achievements & level-ups get the big toast

  const RewardEvent(this.label, {this.celebrate = false});
}

/// One daily task on the farm journal board.
class DailyQuest {
  final String id;
  final String title;
  final int goal;
  final int coinReward;
  final int xpReward;
  int progress;
  bool paid;

  DailyQuest(this.id, this.title, this.goal, this.coinReward, this.xpReward)
      : progress = 0,
        paid = false;

  bool get done => progress >= goal;

  Map<String, dynamic> toJson() => {'id': id, 'progress': progress};
}

/// A badge on the farm's achievement wall.
class Achievement {
  final String id;
  final String title;
  final String desc;
  final bool Function(AchievementProbe probe) test;

  const Achievement(this.id, this.title, this.desc, this.test);
}

/// Everything an achievement predicate may look at, gathered fresh each
/// evaluation.
class AchievementProbe {
  final FarmProfile profile;
  final PigService pigs;
  AchievementProbe(this.profile, this.pigs);

  int get saved => profile.stats['saved'] ?? 0;
  int get mastered => profile.stats['mastered'] ?? 0;
  int get pulls => profile.stats['pulls'] ?? 0;
  int get sales => profile.stats['sales'] ?? 0;
  int get profit => profile.stats['profit'] ?? 0;
  int get level => profile.level;
  int get streak => profile.streak;
  int get herd => pigs.pigs.length;
  int get discovered => pigs.discoveredCount;
  bool get hasChunky =>
      pigs.pigs.any((p) => PigService.stageOf(p) == PigStage.chunky);
  bool get hasFiveStar => PigService.breeds
      .any((b) => b.stars == 5 && (pigs.pulledByBreed[b.id] ?? 0) > 0);
}

/// The farm's long game: XP and levels with visible unlocks, a three-task
/// daily board, a streak, and an achievement wall. Learning is the only
/// real income — this ledger turns learning into visible accomplishment.
///
/// Order matters: construct after [AppSettings] and [PigService], and
/// `init()` before anyone reads it.
class FarmProfile extends ChangeNotifier {
  /// XP needed to advance FROM a level to the next. A level every couple
  /// of study sessions early, stretching as the farm matures.
  static int xpForLevel(int level) => 40 + (level - 1) * 30;

  /// What each farm level visibly adds to the scene — the farm-sim hook:
  /// a level must always buy something you can point at. Lv7+ open new
  /// worlds (services/worlds.dart).
  static const Map<int, String> unlocks = {
    2: 'Pond',
    3: 'Windmill',
    4: 'Flower garden',
    5: 'Golden fence',
    6: 'Orchard',
    7: 'Sunset Beach',
    10: 'Pig Pirate Ship',
    13: 'Sky Island',
  };

  static const List<String> titles = [
    'Sprout Farmer',
    'Field Hand',
    'Shepherd',
    'Rancher',
    'Hog Whisperer',
    'Farm Magnate',
    'Hog Baron',
  ];

  static const Map<int, int> _pullXpByStars = {1: 3, 2: 5, 3: 8, 4: 14, 5: 25};

  static const String _key = 'farm_profile_v1';
  static const int _petXpDailyCap = 10;

  final AppSettings _settings;
  final PigService _pigs;
  StreamSubscription<PigEvent>? _pigSub;

  int _xp = 0;
  int _level = 1;
  String _farmName = 'My Farm';
  int _streak = 0;
  String _lastQuestDay = '';
  String _questDay = '';
  late List<DailyQuest> _quests;
  final Set<String> _badges = {};
  final Map<String, int> _stats = {};
  int _petXpToday = 0;
  String _petXpDay = '';
  int _corn = 0;
  final Map<String, int> _decor = {}; // decor id -> yard slot index
  WorldId _world = WorldId.meadow; // where the herd lives

  final List<RewardEvent> _pendingRewards = [];

  FarmProfile(this._settings, this._pigs);

  // -- reads ---------------------------------------------------------------

  int get xp => _xp;
  int get level => _level;
  String get farmName => _farmName;
  String get title => titles[(_level - 1).clamp(0, titles.length - 1)];
  int get streak => _streak;
  List<DailyQuest> get quests => _quests;
  Set<String> get badges => Set.unmodifiable(_badges);
  Map<String, int> get stats => Map.unmodifiable(_stats);
  bool get allQuestsDone => _quests.every((q) => q.done);

  // -- corn & yard decor ----------------------------------------------------
  /// Ears of corn in the basket. Hungry pigs help themselves at the trough.
  int get corn => _corn;

  /// Decor placed in the yard: item id -> slot index.
  Map<String, int> get decor => Map.unmodifiable(_decor);

  /// The world the herd currently lives in. Never above the unlock level
  /// (a save edited or migrated from a higher level falls back home).
  WorldId get world {
    final theme = worldById(_world);
    return _level >= theme.unlockLevel ? _world : WorldId.meadow;
  }

  /// Move the herd to another world. False (and no change) if the world
  /// is still locked.
  Future<bool> setWorld(WorldId id) async {
    if (_level < worldById(id).unlockLevel) return false;
    if (_world == id) return true;
    _world = id;
    await _saveAndNotify();
    return true;
  }

  Future<void> addCorn(int amount) async {
    if (amount <= 0) return;
    _corn += amount;
    await _saveAndNotify();
  }

  /// Take corn from the basket; false (and no change) if short.
  Future<bool> spendCorn(int amount) async {
    if (amount > _corn) return false;
    _corn -= amount;
    await _saveAndNotify();
    return true;
  }

  /// Number of yard slots a decor can occupy.
  static const int decorSlots = 8;

  /// Place a newly bought decor in the first free yard slot; null when
  /// the yard is full (the buyer should refund).
  int? placeDecor(String id) {
    if (_decor.containsKey(id)) return _decor[id];
    final taken = _decor.values.toSet();
    for (var slot = 0; slot < decorSlots; slot++) {
      if (!taken.contains(slot)) {
        _decor[id] = slot;
        _save();
        notifyListeners();
        return slot;
      }
    }
    return null;
  }

  /// Put a decor away (sell-back is the UI's business).
  bool removeDecor(String id) {
    final gone = _decor.remove(id) != null;
    if (gone) {
      _save();
      notifyListeners();
    }
    return gone;
  }

  /// Total XP a level COSTS to leave behind (sum of every level's cost up
  /// to and including [level] is the XP needed to REACH level+1).
  static int _cumulativeXpToReach(int level) {
    var need = 0;
    for (var l = 1; l < level; l++) {
      need += xpForLevel(l);
    }
    return need;
  }

  /// XP already banked toward the next level, and this level's cost.
  int get xpIntoLevel =>
      (_xp - _cumulativeXpToReach(_level)).clamp(0, xpForLevel(_level));

  int get xpLevelCost => xpForLevel(_level);

  /// Crumbs waiting to be shown; the UI takes them all at once.
  List<RewardEvent> takeRewards() {
    final out = List<RewardEvent>.of(_pendingRewards);
    _pendingRewards.clear();
    return out;
  }

  // -- lifecycle -----------------------------------------------------------

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final d = jsonDecode(raw) as Map<String, dynamic>;
        _xp = d['xp'] as int? ?? 0;
        _level = d['level'] as int? ?? 1;
        _farmName = d['name'] as String? ?? _farmName;
        _streak = d['streak'] as int? ?? 0;
        _lastQuestDay = d['lastQuestDay'] as String? ?? '';
        _questDay = d['questDay'] as String? ?? '';
        _badges
          ..clear()
          ..addAll((d['badges'] as List? ?? []).cast<String>());
        _stats
          ..clear()
          ..addEntries((d['stats'] as Map<String, dynamic>? ?? {})
              .entries
              .map((e) => MapEntry(e.key, e.value as int)));
        _petXpToday = d['petXpToday'] as int? ?? 0;
        _petXpDay = d['petXpDay'] as String? ?? '';
        _corn = d['corn'] as int? ?? 0;
        _world = WorldId.values
            .asNameMap()[d['world'] as String?] ?? WorldId.meadow;
        _decor
          ..clear()
          ..addEntries((d['decor'] as Map<String, dynamic>? ?? {})
              .entries
              .map((e) => MapEntry(e.key, e.value as int)));
        // Today's board, mid-progress: restore what was done.
        final savedQuests = d['quests'] as List? ?? [];
        final restored = [
          for (final q in savedQuests)
            if (q is Map<String, dynamic> &&
                _questDefs.containsKey(q['id']) &&
                q['progress'] is int &&
                (q['progress'] as int) > 0)
              _restoreQuest(q['id'] as String, q['progress'] as int,
                  q['paid'] as bool? ?? false),
        ];
        if (restored.isNotEmpty && _questDay == _today()) {
          _quests = restored;
        }
      } catch (_) {
        // Corrupt ledger: start fresh, keep the farm.
      }
    }

    _pigSub = _pigs.events.listen(_onPigEvent);

    _rollTodaysQuests();
    reevaluate();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'xp': _xp,
        'level': _level,
        'name': _farmName,
        'streak': _streak,
        'lastQuestDay': _lastQuestDay,
        'questDay': _questDay,
        'badges': _badges.toList(),
        'stats': _stats,
        'quests': [for (final q in _quests) q.toJson()],
        'petXpToday': _petXpToday,
        'petXpDay': _petXpDay,
        'corn': _corn,
        'decor': _decor,
        'world': _world.name,
      }),
    );
  }

  // -- learning hooks (the coin + XP taps) ---------------------------------

  /// One word saved: the coin, plus XP and quest progress.
  Future<void> recordWordSaved() async {
    await _settings.addCoins(1);
    _stats['saved'] = (_stats['saved'] ?? 0) + 1;
    _grantXp(4);
    _bumpQuest('save');
    _addReward(const RewardEvent('+1 🪙  +4 XP'));
    await _finishQuests(const ['save']);
    await _saveAndNotify();
  }

  /// One first-time mastery in a test: the coin, bigger XP, quest progress.
  Future<void> recordMastered() async {
    await _settings.addCoins(1);
    _stats['mastered'] = (_stats['mastered'] ?? 0) + 1;
    _grantXp(8);
    _bumpQuest('master');
    _addReward(const RewardEvent('+1 🪙  +8 XP'));
    await _finishQuests(const ['master']);
    await _saveAndNotify();
  }

  /// Debug purse top-up (debug builds only): silent, no XP, no quest.
  Future<void> debugGrantCoins(int amount) async {
    await _settings.addCoins(amount);
    _addReward(RewardEvent('+$amount 🪙 (dev)'));
    notifyListeners();
  }

  void renameFarm(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _farmName = trimmed.length > 24 ? trimmed.substring(0, 24) : trimmed;
    _save();
    notifyListeners();
  }

  // -- pig events ----------------------------------------------------------

  Future<void> _onPigEvent(PigEvent e) async {
    switch (e.kind) {
      case PigEventKind.pull:
        _stats['pulls'] = (_stats['pulls'] ?? 0) + 1;
        _grantXp(_pullXpByStars[e.stars] ?? 3);
        _bumpQuest('pull');
        await _finishQuests(const ['pull']);
      case PigEventKind.sell:
        _stats['sales'] = (_stats['sales'] ?? 0) + 1;
        final gain = (e.value - PigService.pullCost).clamp(0, 1 << 30);
        _stats['profit'] = (_stats['profit'] ?? 0) + gain;
        _grantXp(2);
        _bumpQuest('sell');
        await _finishQuests(const ['sell']);
      case PigEventKind.pet:
        _stats['pets'] = (_stats['pets'] ?? 0) + 1;
        final today = _today();
        if (_petXpDay != today) {
          _petXpDay = today;
          _petXpToday = 0;
        }
        if (_petXpToday < _petXpDailyCap) {
          _petXpToday++;
          _grantXp(1);
        }
        _bumpQuest('pet');
        await _finishQuests(const ['pet']);
      case PigEventKind.feed:
        _stats['feeds'] = (_stats['feeds'] ?? 0) + 1;
        _grantXp(2);
        _bumpQuest('feed');
        await _finishQuests(const ['feed']);
      case PigEventKind.bathe:
        _stats['bathes'] = (_stats['bathes'] ?? 0) + 1;
        _grantXp(2);
        _bumpQuest('bathe');
        await _finishQuests(const ['bathe']);
      case PigEventKind.birth:
        _stats['births'] = (_stats['births'] ?? 0) + 1;
        _grantXp(12);
        _addReward(const RewardEvent('🐣 A piglet is born! +12 XP',
            celebrate: true));
    }
    reevaluate();
    await _saveAndNotify();
  }

  // -- quests & streak -----------------------------------------------------

  /// Master quest definitions — the board picks three of these a day.
  static const Map<String, List<int>> _questDefs = {
    // id: [goal, coinReward, xpReward]
    'save': [3, 6, 15],
    'master': [1, 8, 20],
    'pull': [1, 4, 10],
    'pet': [3, 2, 8],
    'sell': [1, 4, 10],
    'feed': [1, 5, 12],
    'bathe': [1, 5, 12],
  };

  static const Map<String, String> _questTitles = {
    'save': 'Save 3 new words',
    'master': 'Pass 1 mastery test',
    'pull': 'Adopt a pig at the Market',
    'pet': 'Pet your pigs 3 times',
    'sell': 'Send a pig to market',
    'feed': 'Serve corn at the trough',
    'bathe': 'Give a pig a shower',
  };

  /// Three tasks a day, always one learning quest: study is the spine,
  /// farm chores are the garnish. Deterministic per day.
  void _rollTodaysQuests() {
    final today = _today();
    if (_questDay == today && _quests.isNotEmpty) return;
    _questDay = today;
    final day = int.tryParse(today.substring(today.length - 2)) ?? 1;
    // Always one learning quest; the other two rotate study, pet and farm
    // chores on a fixed 6-day cycle so the whole pool comes around.
    final ids = switch (day % 6) {
      0 => ['save', 'pet', 'sell'],
      1 => ['save', 'master', 'pull'],
      2 => ['save', 'feed', 'sell'],
      3 => ['save', 'pet', 'pull'],
      4 => ['save', 'master', 'bathe'],
      _ => ['save', 'feed', 'pull'],
    };
    _quests = [for (final id in ids) _makeQuest(id)];
  }

  static DailyQuest _makeQuest(String id) {
    final def = _questDefs[id]!;
    return DailyQuest(
        id, _questTitles[id]!, def[0], def[1], def[2]);
  }

  static DailyQuest _restoreQuest(String id, int progress, bool paid) {
    final q = _makeQuest(id)
      ..progress = progress
      ..paid = paid;
    return q;
  }

  DailyQuest? _quest(String id) {
    for (final q in _quests) {
      if (q.id == id) return q;
    }
    return null;
  }

  void _bumpQuest(String id) {
    _quest(id)?.progress++;
  }

  /// Pay out any of the named quests that just completed (rewards read
  /// from the quest itself, so the board stays the single source), and
  /// roll the streak when the whole board is done.
  Future<void> _finishQuests(List<String> ids) async {
    for (final id in ids) {
      final q = _quest(id);
      if (q == null || !q.done || q.paid) continue;
      q.paid = true;
      if (q.coinReward > 0) await _settings.addCoins(q.coinReward);
      _grantXp(q.xpReward);
      final icon = switch (id) {
        'save' || 'master' => '📝',
        'feed' => '🌽',
        'bathe' => '🫧',
        _ => '🐷',
      };
      _addReward(RewardEvent(
          '$icon Quest done · +${q.coinReward} 🪙 +${q.xpReward} XP'));
    }
    if (allQuestsDone && _lastQuestDay != _questDay) {
      final yesterday =
          _today(DateTime.now().subtract(const Duration(days: 1)));
      _streak = _lastQuestDay == yesterday ? _streak + 1 : 1;
      _lastQuestDay = _questDay;
      if (_streak > 1) {
        _addReward(RewardEvent('🔥 $_streak-day streak!', celebrate: true));
      }
    }
  }

  // -- XP & levels ---------------------------------------------------------

  void _grantXp(int amount) {
    _xp += amount;
    // Level N+1 arrives at the cumulative threshold — never at "total XP
    // >= total XP + cost", which is what a broken early version compared
    // and why levels never rose past 1 (caught 2026-09-08 by the worlds
    // test spinning forever).
    while (_xp >= _cumulativeXpToReach(_level + 1)) {
      _level++;
      final unlock = unlocks[_level];
      _addReward(RewardEvent(
        '⭐ Farm Lv.$level — ${unlock ?? title}!',
        celebrate: true,
      ));
    }
  }

  // -- achievements --------------------------------------------------------

  static final List<Achievement> achievementDefs = [
    Achievement('firstPig', 'First Friend', 'Adopt your first pig',
        (p) => p.pulls >= 1),
    Achievement('herd5', 'Full House', 'Raise a herd of 5', (p) => p.herd >= 5),
    Achievement(
        'firstSale', 'Market Debut', 'Sell a pig at the Market',
        (p) => p.sales >= 1),
    Achievement('profit50', 'Shrewd Trader', 'Earn 50 coins of selling profit',
        (p) => p.profit >= 50),
    Achievement('chunky', 'Maximum Pig', 'Raise a pig to Chunky (72h)',
        (p) => p.hasChunky),
    Achievement('jackpot', 'Jackpot', 'Pull a 5★ breed', (p) => p.hasFiveStar),
    Achievement('collector', 'Breed Collector', 'Discover 5 different breeds',
        (p) => p.discovered >= 5),
    Achievement('words10', 'Bookworm', 'Save 10 words', (p) => p.saved >= 10),
    Achievement(
        'words100', 'Librarian', 'Save 100 words', (p) => p.saved >= 100),
    Achievement('master10', 'Scholar', 'Master 10 words', (p) => p.mastered >= 10),
    Achievement('streak3', 'Regular', 'Keep a 3-day streak', (p) => p.streak >= 3),
    Achievement('level5', 'Established', 'Reach Farm Lv.5', (p) => p.level >= 5),
    Achievement(
        'firstLitter',
        'Family Farm',
        'Welcome a piglet by breeding',
        (p) => (p.profile.stats['births'] ?? 0) >= 1),
    Achievement(
        'decor1',
        'Homemaker',
        'Place a decoration in the yard',
        (p) => p.profile.decor.isNotEmpty),
  ];

  /// Re-check the wall — called after every event and on init. Time-based
  /// facts (a pig crossing into Chunky) land on the next event.
  void reevaluate() {
    final probe = AchievementProbe(this, _pigs);
    for (final a in achievementDefs) {
      if (_badges.contains(a.id)) continue;
      if (a.test(probe)) {
        _badges.add(a.id);
        _grantXp(25);
        _addReward(RewardEvent('🏆 ${a.title} — ${a.desc}', celebrate: true));
      }
    }
  }

  // -- plumbing ------------------------------------------------------------

  void _addReward(RewardEvent e) => _pendingRewards.add(e);

  Future<void> _saveAndNotify() async {
    await _save();
    notifyListeners();
  }

  static String _today([DateTime? at]) {
    final d = at ?? DateTime.now();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}$mm$dd';
  }

  @override
  void dispose() {
    _pigSub?.cancel();
    super.dispose();
  }
}
