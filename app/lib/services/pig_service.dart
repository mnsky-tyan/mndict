import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_settings.dart';
import '../ui/widgets/pig_design.dart';

/// One variety in the Pig Market's gacha pool. Herd, not collection: the
/// same variety can live in the pen many times. [price] is the breed's
/// base value — the coin figure the sell price multiplies from, not a
/// shelf tag (adoption runs through the gacha pull). Everything visual
/// lives in [design] (see pig_design.dart); the painter renders that spec.
class PigBreed {
  final String id;
  final String name;
  final int stars; // 1..5 rarity tier, shown as ★
  final int price; // base sell value in coins
  final PigDesign design;
  final double speed; // wander pace multiplier
  final double napChance; // how often it flops over for a nap

  const PigBreed({
    required this.id,
    required this.name,
    required this.stars,
    required this.price,
    required this.design,
    this.speed = 1.0,
    this.napChance = 0.22,
  });
}

/// How raised a pig is. Stages advance by real time since adoption and
/// are the whole economy: value = base value × stage multiplier.
/// A pig that runs out of food stops growing until it eats again.
enum PigStage { piglet, grown, chunky }

/// Boars and sows — the gate on the breeding pen.
enum PigGender { female, male }

/// A pig living on the farm.
class Pig {
  final int id;
  final String breedId;
  String name;
  final DateTime adoptedAt; // growth (and thus value) grows from here
  int pets;
  final PigGender gender;

  /// Care clocks: hunger drains from 100 to 0 over [PigService.hungerHours]
  /// since [fedAt]; dirt builds to 100 over [PigService.dirtHours] since
  /// [bathedAt]. Time spent at hunger 0 doesn't count toward growth —
  /// [starvedSeconds] banks the finished spells, the running one is
  /// derived from [fedAt] (see [PigService.effectiveAgeOf]).
  DateTime fedAt;
  DateTime bathedAt;
  int starvedSeconds;

  /// Breeding: while [dueAt] is set the sow is expecting [matedTo]'s litter.
  int? matedTo;
  DateTime? dueAt;

  Pig({
    required this.id,
    required this.breedId,
    required this.name,
    DateTime? adoptedAt,
    this.pets = 0,
    PigGender? gender,
    DateTime? fedAt,
    DateTime? bathedAt,
    this.starvedSeconds = 0,
    this.matedTo,
    this.dueAt,
  })  : adoptedAt = adoptedAt ?? DateTime.now(),
        gender = gender ?? PigGender.values[DateTime.now().millisecond % 2],
        fedAt = fedAt ?? DateTime.now(),
        bathedAt = bathedAt ?? DateTime.now();

  /// 100 = just fed, 0 = starving. Drains linearly.
  double hunger([DateTime? now]) {
    final n = now ?? DateTime.now();
    final hours = n.difference(fedAt).inMicroseconds / 3.6e9;
    return (100 - hours * 100 / PigService.hungerHours).clamp(0.0, 100.0);
  }

  /// 0 = sparkling, 100 = needs a shower asap. Builds linearly.
  double dirt([DateTime? now]) {
    final n = now ?? DateTime.now();
    final hours = n.difference(bathedAt).inMicroseconds / 3.6e9;
    return (hours * 100 / PigService.dirtHours).clamp(0.0, 100.0);
  }

  bool get isPregnant => dueAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'breed': breedId,
        'name': name,
        'pets': pets,
        'adoptedAt': adoptedAt.millisecondsSinceEpoch,
        'gender': gender.index,
        'fedAt': fedAt.millisecondsSinceEpoch,
        'bathedAt': bathedAt.millisecondsSinceEpoch,
        'starvedSeconds': starvedSeconds,
        'matedTo': matedTo,
        'dueAt': dueAt?.millisecondsSinceEpoch,
      };

  factory Pig.fromJson(Map<String, dynamic> json) => Pig(
        id: json['id'] as int,
        breedId: json['breed'] as String,
        name: json['name'] as String,
        // Pigs saved before growth existed start their clock today.
        adoptedAt: json['adoptedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['adoptedAt'] as int)
            : null,
        pets: json['pets'] as int? ?? 0,
        gender: json['gender'] != null
            ? PigGender.values[json['gender'] as int]
            : null,
        fedAt: json['fedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['fedAt'] as int)
            : null,
        bathedAt: json['bathedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['bathedAt'] as int)
            : null,
        starvedSeconds: json['starvedSeconds'] as int? ?? 0,
        matedTo: json['matedTo'] as int?,
        dueAt: json['dueAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['dueAt'] as int)
            : null,
      );
}

/// Something the herd did that the farm journal cares about — the wiring
/// between the pen and the XP/quest ledger in FarmProfile.
enum PigEventKind { pull, sell, pet, feed, bathe, birth }

class PigEvent {
  final PigEventKind kind;
  final String breedId;
  final int stars;
  final int value; // sale price for [sell], pull rarity stars otherwise

  const PigEvent(this.kind, this.breedId, {this.stars = 0, this.value = 0});
}

/// The outcome of one market pull, for the reveal moment.
class PullResult {
  final Pig pig;
  final PigBreed breed;
  final bool isNewBreed;
  final int dupCount; // how many of this breed were pulled before

  const PullResult(this.pig, this.breed,
      {required this.isNewBreed, required this.dupCount});
}

/// The farm's ledger: which pigs live in the pen, the gacha that brings
/// them in, and the sell flow that lets them go. Coins live in
/// [AppSettings]; this service spends and earns them, and broadcasts
/// [PigEvent]s for the journal.
class PigService extends ChangeNotifier {
  static const int capacity = 12;
  static const int pullCost = 15;

  /// Gacha odds per rarity tier, in percent — printed on the machine.
  /// EV ≈ 14 coins of base value against the 15-coin pull: a Piglet dumps
  /// at the 0.7 broker fee (EV ≈ 10), so pull-and-flip loses coins and
  /// only patient raising (1.6×/2.4× by stage) turns a profit.
  static const Map<int, int> pullOdds = {1: 58, 2: 25, 3: 12, 4: 4, 5: 1};

  /// Growth stage thresholds by real time held. Starving pauses the clock.
  static const Duration grownAfter = Duration(hours: 24);
  static const Duration chunkyAfter = Duration(hours: 72);

  // -- care ----------------------------------------------------------------
  /// A feeding lasts this long before the pig is starving again.
  static const int hungerHours = 8;

  /// A bath keeps the pig clean this long.
  static const int dirtHours = 16;

  /// How long a sow carries a litter.
  static const Duration pregnancy = Duration(hours: 6);

  /// Market price of one ear of corn.
  static const int cornPrice = 3;

  /// The trough pile tops out visually at this many ears in the basket.
  static const int cornTroughCapacity = 8;

  /// Minimum hunger (0–100) both pigs need before they'll breed.
  static const double breedMinHunger = 25;

  /// Stage multiplier on the breed's base value. Piglets sell under a
  /// broker fee so the market can't be farmed by instant flips.
  static double stageMultiplier(PigStage stage) => switch (stage) {
        PigStage.piglet => 0.7,
        PigStage.grown => 1.6,
        PigStage.chunky => 2.4,
      };

  static const String _key = 'pig_farm_v1';

  /// The Market's pool: 50 themed breeds across five tiers, cheapest
  /// first within a tier. Prices are the base a pig's sell value grows
  /// from; the 5★s stay the jackpot. breed i wears pigDesigns[i] — the
  /// catalog test locks the pairing (1:1, all 50, no doubles).
  static final List<PigBreed> breeds = [
    // -- ★1 commons: charming starters --
    PigBreed(id: 'truffle', name: 'Truffle', stars: 1, price: 5,
        design: pigDesigns[0], speed: 1.0, napChance: 0.22),
    PigBreed(id: 'pebble', name: 'Pebble', stars: 1, price: 4,
        design: pigDesigns[2], speed: 0.7, napChance: 0.30),
    PigBreed(id: 'sunny', name: 'Sunny', stars: 1, price: 5,
        design: pigDesigns[4], speed: 1.1, napChance: 0.18),
    PigBreed(id: 'butterscotch', name: 'Butterscotch', stars: 1, price: 5,
        design: pigDesigns[1], speed: 0.85, napChance: 0.40),
    PigBreed(id: 'clover', name: 'Clover', stars: 1, price: 5,
        design: pigDesigns[3], speed: 0.9, napChance: 0.30),
    PigBreed(id: 'berry', name: 'Berry', stars: 1, price: 6,
        design: pigDesigns[5], speed: 0.95, napChance: 0.25),
    PigBreed(id: 'cocoa', name: 'Cocoa', stars: 1, price: 6,
        design: pigDesigns[6], speed: 0.8, napChance: 0.45),
    PigBreed(id: 'snowdrop', name: 'Snowdrop', stars: 1, price: 6,
        design: pigDesigns[7], speed: 0.75, napChance: 0.50),
    PigBreed(id: 'puddle', name: 'Puddle', stars: 1, price: 6,
        design: pigDesigns[9], speed: 1.0, napChance: 0.35),
    PigBreed(id: 'blueberry', name: 'Blueberry', stars: 1, price: 7,
        design: pigDesigns[8], speed: 1.1, napChance: 0.18),
    // -- ★2 uncommons: full food skins --
    PigBreed(id: 'pineapple', name: 'Pineapple', stars: 2, price: 8,
        design: pigDesigns[10], speed: 0.9, napChance: 0.28),
    PigBreed(id: 'strawberry', name: 'Strawberry', stars: 2, price: 8,
        design: pigDesigns[11], speed: 1.05, napChance: 0.20),
    PigBreed(id: 'watermelon', name: 'Watermelon', stars: 2, price: 9,
        design: pigDesigns[12], speed: 0.95, napChance: 0.26),
    PigBreed(id: 'mochi', name: 'Mochi', stars: 2, price: 9,
        design: pigDesigns[13], speed: 0.8, napChance: 0.42),
    PigBreed(id: 'biscuit', name: 'Biscuit', stars: 2, price: 10,
        design: pigDesigns[22], speed: 0.85, napChance: 0.34),
    PigBreed(id: 'matcha', name: 'Matcha', stars: 2, price: 10,
        design: pigDesigns[16], speed: 0.9, napChance: 0.30),
    PigBreed(id: 'honey', name: 'Honey', stars: 2, price: 11,
        design: pigDesigns[14], speed: 0.85, napChance: 0.30),
    PigBreed(id: 'corn', name: 'Corn', stars: 2, price: 11,
        design: pigDesigns[18], speed: 1.0, napChance: 0.22),
    PigBreed(id: 'jam', name: 'Jam', stars: 2, price: 12,
        design: pigDesigns[19], speed: 1.0, napChance: 0.24),
    PigBreed(id: 'bubbles', name: 'Bubbles', stars: 2, price: 12,
        design: pigDesigns[17], speed: 1.15, napChance: 0.16),
    PigBreed(id: 'mocha', name: 'Mocha', stars: 2, price: 13,
        design: pigDesigns[15], speed: 0.8, napChance: 0.38),
    PigBreed(id: 'macaron', name: 'Macaron', stars: 2, price: 13,
        design: pigDesigns[21], speed: 0.9, napChance: 0.28),
    PigBreed(id: 'cottoncandy', name: 'Cotton Candy', stars: 2, price: 14,
        design: pigDesigns[20], speed: 1.1, napChance: 0.20),
    // -- ★3 rares: jobs & characters --
    PigBreed(id: 'chef', name: 'Chef', stars: 3, price: 16,
        design: pigDesigns[27], speed: 1.0, napChance: 0.22),
    PigBreed(id: 'gardener', name: 'Gardener', stars: 3, price: 18,
        design: pigDesigns[28], speed: 0.9, napChance: 0.28),
    PigBreed(id: 'bee', name: 'Bee', stars: 3, price: 20,
        design: pigDesigns[32], speed: 1.3, napChance: 0.10),
    PigBreed(id: 'ninja', name: 'Ninja', stars: 3, price: 22,
        design: pigDesigns[26], speed: 1.35, napChance: 0.08),
    PigBreed(id: 'sailor', name: 'Sailor', stars: 3, price: 24,
        design: pigDesigns[23], speed: 1.0, napChance: 0.22),
    PigBreed(id: 'kabuki', name: 'Kabuki', stars: 3, price: 26,
        design: pigDesigns[29], speed: 0.9, napChance: 0.20),
    PigBreed(id: 'firecracker', name: 'Firecracker', stars: 3, price: 28,
        design: pigDesigns[30], speed: 1.2, napChance: 0.10),
    PigBreed(id: 'buccaneer', name: 'Buccaneer', stars: 3, price: 30,
        design: pigDesigns[24], speed: 1.1, napChance: 0.15),
    PigBreed(id: 'wizard', name: 'Wizard', stars: 3, price: 32,
        design: pigDesigns[25], speed: 0.85, napChance: 0.30),
    PigBreed(id: 'glacier', name: 'Glacier', stars: 3, price: 36,
        design: pigDesigns[31], speed: 0.7, napChance: 0.40),
    PigBreed(id: 'peacock', name: 'Peacock', stars: 3, price: 40,
        design: pigDesigns[33], speed: 0.9, napChance: 0.18),
    PigBreed(id: 'ember', name: 'Ember', stars: 3, price: 50,
        design: pigDesigns[34], speed: 1.25, napChance: 0.10),
    // -- ★4 epics: fantasy + glow auras --
    PigBreed(id: 'kitsune', name: 'Kitsune', stars: 4, price: 55,
        design: pigDesigns[40], speed: 1.1, napChance: 0.14),
    PigBreed(id: 'phantom', name: 'Phantom', stars: 4, price: 60,
        design: pigDesigns[42], speed: 1.15, napChance: 0.12),
    PigBreed(id: 'mecha', name: 'Mecha', stars: 4, price: 65,
        design: pigDesigns[41], speed: 0.8, napChance: 0.20),
    PigBreed(id: 'royal', name: 'Royal', stars: 4, price: 70,
        design: pigDesigns[38], speed: 0.75, napChance: 0.25),
    PigBreed(id: 'dragonfruit', name: 'Dragonfruit', stars: 4, price: 75,
        design: pigDesigns[39], speed: 1.0, napChance: 0.18),
    PigBreed(id: 'frosty', name: 'Frosty', stars: 4, price: 80,
        design: pigDesigns[36], speed: 0.7, napChance: 0.38),
    PigBreed(id: 'firebird', name: 'Firebird', stars: 4, price: 85,
        design: pigDesigns[35], speed: 1.2, napChance: 0.10),
    PigBreed(id: 'starweaver', name: 'Starweaver', stars: 4, price: 90,
        design: pigDesigns[43], speed: 1.0, napChance: 0.22),
    PigBreed(id: 'halo', name: 'Halo', stars: 4, price: 100,
        design: pigDesigns[37], speed: 1.0, napChance: 0.20),
    // -- ★5 legendaries: full spectacle --
    PigBreed(id: 'sol', name: 'Sol', stars: 5, price: 150,
        design: pigDesigns[44], speed: 1.1, napChance: 0.15),
    PigBreed(id: 'luna', name: 'Luna', stars: 5, price: 165,
        design: pigDesigns[45], speed: 0.9, napChance: 0.25),
    PigBreed(id: 'leviathan', name: 'Leviathan', stars: 5, price: 180,
        design: pigDesigns[46], speed: 0.85, napChance: 0.20),
    PigBreed(id: 'goldheart', name: 'Goldheart', stars: 5, price: 200,
        design: pigDesigns[47], speed: 0.9, napChance: 0.22),
    PigBreed(id: 'prism', name: 'Prism', stars: 5, price: 220,
        design: pigDesigns[48], speed: 1.15, napChance: 0.12),
    PigBreed(id: 'midnight', name: 'Voidling', stars: 5, price: 240,
        design: pigDesigns[49], speed: 1.0, napChance: 0.18),
  ];

  /// Cute names handed out at adoption. Food-themed, like every good pig.
  static const List<String> _namePool = [
    'Mochi', 'Baozi', 'Pudding', 'Dumpling', 'Waffle', 'Nugget', 'Pepper',
    'Cocoa', 'Butter', 'Tofu', 'Marshmallow', 'Biscuit', 'Pickle', 'Taro',
    'Miso', 'Churro', 'Bagel', 'Pretzel', 'Mango', 'Sesame',
  ];

  final AppSettings _settings;
  final List<Pig> _pigs = [];
  final Random _random = Random();
  int _nextId = 1;

  /// Codex: how many times each breed has been pulled, ever.
  final Map<String, int> _pulledByBreed = {};

  /// Every breed the farm has ever met — pulls and births alike.
  final Set<String> _everSeen = {};

  final _events = StreamController<PigEvent>.broadcast();

  /// Herd happenings for the journal (XP, quests, achievements).
  Stream<PigEvent> get events => _events.stream;

  PigService(this._settings);

  List<Pig> get pigs => List.unmodifiable(_pigs);
  bool get isFull => _pigs.length >= capacity;
  Map<String, int> get pulledByBreed => Map.unmodifiable(_pulledByBreed);
  int get discoveredCount => _everSeen.length;
  List<Pig> get pregnant =>
      _pigs.where((p) => p.isPregnant).toList(growable: false);

  static PigBreed breedById(String id) =>
      breeds.firstWhere((b) => b.id == id, orElse: () => breeds.first);

  // -- growth & value ------------------------------------------------------

  /// Time the pig has actually spent growing: wall-clock age minus every
  /// spell spent starving. Finished spells are banked in
  /// [Pig.starvedSeconds]; the running one is derived from [Pig.fedAt],
  /// so pauses survive restarts without any timers.
  static Duration effectiveAgeOf(Pig pig, [DateTime? now]) {
    final n = now ?? DateTime.now();
    var age = n.difference(pig.adoptedAt);
    age -= Duration(seconds: pig.starvedSeconds);
    final grace = pig.fedAt.add(const Duration(hours: hungerHours));
    if (n.isAfter(grace)) age -= n.difference(grace);
    return age < Duration.zero ? Duration.zero : age;
  }

  static PigStage stageOf(Pig pig, [DateTime? now]) {
    final age = effectiveAgeOf(pig, now);
    if (age >= chunkyAfter) return PigStage.chunky;
    if (age >= grownAfter) return PigStage.grown;
    return PigStage.piglet;
  }

  /// Time until the pig's next growth stage; null when fully grown.
  static Duration? timeToNextStage(Pig pig, [DateTime? now]) {
    final age = effectiveAgeOf(pig, now);
    if (age < grownAfter) return grownAfter - age;
    if (age < chunkyAfter) return chunkyAfter - age;
    return null;
  }

  /// What selling the pig pays right now.
  static int sellValueOf(Pig pig, [DateTime? now]) =>
      (breedById(pig.breedId).price * stageMultiplier(stageOf(pig, now)))
          .round();

  // -- persistence ---------------------------------------------------------

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _pigs.clear();
        for (final item in (decoded['pigs'] as List? ?? [])) {
          final pig = Pig.fromJson(item as Map<String, dynamic>);
          // Drop pigs whose breed vanished from the catalog.
          if (breeds.any((b) => b.id == pig.breedId)) _pigs.add(pig);
        }
        _nextId = decoded['nextId'] as int? ?? _pigs.length + 1;
        final pulls = decoded['pulled'] as Map<String, dynamic>? ?? {};
        _pulledByBreed
          ..clear()
          ..addEntries(
              pulls.entries.map((e) => MapEntry(e.key, e.value as int)));
        _everSeen
          ..clear()
          ..addAll(_pulledByBreed.keys);
      } catch (_) {
        _pigs.clear();
        _pulledByBreed.clear();
        _everSeen.clear();
      }
    } else {
      // First run: the Truffle gift, so the pen is never empty on day one.
      await adoptDirect('truffle');
    }
    // Pigs due while the app was closed are born on load.
    checkBirths();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'pigs': _pigs.map((p) => p.toJson()).toList(),
        'nextId': _nextId,
        'pulled': _pulledByBreed,
      }),
    );
  }

  void _emit(PigEvent event) => _events.add(event);

  // -- actions -------------------------------------------------------------

  PigGender _rollGender() => PigGender.values[_random.nextInt(2)];

  /// Bring a specific breed home for free — the day-one Truffle gift and
  /// the test/preview seeding path.
  Future<Pig> adoptDirect(String breedId, {String? name}) async {
    final pig = Pig(
      id: _nextId++,
      breedId: breedId,
      name: name ?? _nextName(),
      gender: _rollGender(),
    );
    _pigs.add(pig);
    _everSeen.add(breedId);
    await _save();
    notifyListeners();
    return pig;
  }

  /// Test/preview path: insert a pre-built pig directly.
  void debugAdd(Pig pig) {
    _pigs.add(pig);
    _everSeen.add(pig.breedId);
    notifyListeners();
  }

  /// Roll the gacha: pay [pullCost], receive a random breed weighted by
  /// [pullOdds]. The pig joins the pen immediately; the sheet animates
  /// the reveal afterwards.
  Future<PullResult?> pull() async {
    if (isFull) return null;
    if (!await _settings.spendCoins(pullCost)) return null;

    final breed = _rollBreed();
    final dupCount = _pulledByBreed[breed.id] ?? 0;
    final pig = Pig(
        id: _nextId++, breedId: breed.id, name: _nextName(), gender: _rollGender());
    _pigs.add(pig);
    _everSeen.add(breed.id);
    _pulledByBreed[breed.id] = dupCount + 1;
    await _save();
    notifyListeners();
    _emit(PigEvent(PigEventKind.pull, breed.id, stars: breed.stars));
    return PullResult(pig, breed, isNewBreed: dupCount == 0, dupCount: dupCount);
  }

  PigBreed _rollBreed() {
    final roll = _random.nextInt(100);
    var cum = 0;
    var stars = 1;
    for (final entry in pullOdds.entries) {
      cum += entry.value;
      if (roll < cum) {
        stars = entry.key;
        break;
      }
    }
    final tier = breeds.where((b) => b.stars == stars).toList();
    return tier[_random.nextInt(tier.length)];
  }

  /// Send a pig to market: it trots off and its current value lands in
  /// the purse. Returns the coins paid, or null if the pig was already
  /// gone.
  Future<int?> sell(Pig pig) async {
    if (pig.isPregnant) return null; // the litter stays with its mother
    final value = sellValueOf(pig);
    final removed = _pigs.remove(pig);
    if (!removed) return null;
    await _settings.addCoins(value);
    await _save();
    notifyListeners();
    _emit(PigEvent(PigEventKind.sell, pig.breedId, value: value));
    return value;
  }

  Future<void> rename(Pig pig, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || !_pigs.contains(pig)) return;
    pig.name = trimmed;
    await _save();
    notifyListeners();
  }

  /// Record one petting. Silent on purpose — the scene handles the
  /// feedback; the counter persists and the journal listens.
  Future<void> pet(Pig pig) async {
    pig.pets++;
    _emit(PigEvent(PigEventKind.pet, pig.breedId));
    await _save();
  }

  // -- care ----------------------------------------------------------------

  /// One ear of corn from the basket. If the pig was starving, the
  /// starved spell is banked first so growth resumes where it left off.
  Future<void> feed(Pig pig, [DateTime? now]) async {
    if (!_pigs.contains(pig)) return;
    final n = now ?? DateTime.now();
    final grace = pig.fedAt.add(const Duration(hours: hungerHours));
    if (n.isAfter(grace)) {
      pig.starvedSeconds += n.difference(grace).inSeconds;
    }
    pig.fedAt = n;
    await _save();
    notifyListeners();
    _emit(PigEvent(PigEventKind.feed, pig.breedId));
  }

  /// Scrub the pig sparkling clean.
  Future<void> bathe(Pig pig, [DateTime? now]) async {
    if (!_pigs.contains(pig)) return;
    pig.bathedAt = now ?? DateTime.now();
    await _save();
    notifyListeners();
    _emit(PigEvent(PigEventKind.bathe, pig.breedId));
  }

  /// Can these two start a family? Opposite genders, both raised past the
  /// piglet stage, neither starving, and the sow not already expecting.
  static bool canBreed(Pig a, Pig b, [DateTime? now]) {
    if (identical(a, b) || a.gender == b.gender) return false;
    final n = now ?? DateTime.now();
    if (a.isPregnant || b.isPregnant) return false;
    if (stageOf(a, n) == PigStage.piglet || stageOf(b, n) == PigStage.piglet) {
      return false;
    }
    if (a.hunger(n) < breedMinHunger || b.hunger(n) < breedMinHunger) {
      return false;
    }
    return true;
  }

  /// Every pen-mate the sow could start a family with right now.
  List<Pig> matchesFor(Pig sow, [DateTime? now]) => _pigs
      .where((p) => p.id != sow.id && canBreed(sow, p, now))
      .toList(growable: false);

  /// Match-make a pair. The sow carries the litter: [Pig.dueAt] counts
  /// down (real time) to a piglet of either parent's breed.
  bool breed(Pig sow, Pig boar, [DateTime? now]) {
    final n = now ?? DateTime.now();
    if (!canBreed(sow, boar, n)) return false;
    sow
      ..matedTo = boar.id
      ..dueAt = n.add(pregnancy);
    _save();
    notifyListeners();
    return true;
  }

  /// Deliver any litters that are due. Called lazily — from the scene
  /// tick and on load — so piglets arrive even without a timer. Births
  /// wait for pen room; returns how many piglets were born.
  int checkBirths([DateTime? now]) {
    final n = now ?? DateTime.now();
    var born = 0;
    final ready = _pigs
        .where((p) => p.dueAt != null && !n.isBefore(p.dueAt!))
        .toList();
    for (final sow in ready) {
      if (_pigs.length >= capacity) break;
      final sire = _pigs.where((p) => p.id == sow.matedTo).toList();
      final breedPool = [
        sow.breedId,
        if (sire.isNotEmpty) sire.first.breedId,
      ];
      final breedId = breedPool[_random.nextInt(breedPool.length)];
      final piglet = Pig(
        id: _nextId++,
        breedId: breedId,
        name: _nextName(),
        gender: _rollGender(),
      );
      _pigs.add(piglet);
      _everSeen.add(breedId);
      sow
        ..matedTo = null
        ..dueAt = null;
      born++;
      _emit(PigEvent(PigEventKind.birth, breedId));
    }
    if (born > 0) {
      _save();
      notifyListeners();
    }
    return born;
  }

  String _nextName() {
    final used = _pigs.map((p) => p.name).toSet();
    final free = _namePool.where((n) => !used.contains(n)).toList();
    if (free.isNotEmpty) return free[_random.nextInt(free.length)];
    return 'Pig $_nextId';
  }

  @override
  void dispose() {
    _events.close();
    super.dispose();
  }
}
