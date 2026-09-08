import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/services/app_settings.dart';
import 'package:app/services/farm_profile.dart';
import 'package:app/services/pig_service.dart';
import 'package:app/services/worlds.dart';
import 'package:app/ui/widgets/pig_design.dart';

/// The care layer: hunger and dirt run on real time, starvation pauses
/// growth, breeding needs a fed adult pair, and litters arrive late.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSettings settings;
  late PigService pigs;
  late FarmProfile profile;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings();
    await settings.init();
    await settings.addCoins(500);
    pigs = PigService(settings);
    await pigs.init();
    profile = FarmProfile(settings, pigs);
    await profile.init();
  });

  group('hunger & dirt clocks', () {
    test('drain linearly from a fresh feeding', () {
      final now = DateTime.now();
      final pig = pigs.pigs.single;
      expect(pig.hunger(now), closeTo(100, 0.001));
      final halfFed = pig.hunger(now.add(const Duration(hours: 4)));
      expect(halfFed, closeTo(50, 0.01));
      expect(pig.hunger(now.add(const Duration(hours: 8))), 0);
      // Hunger never goes negative.
      expect(pig.hunger(now.add(const Duration(days: 30))), 0);
    });

    test('dirt builds until a bath resets it', () async {
      final now = DateTime.now();
      final pig = pigs.pigs.single;
      expect(pig.dirt(now), closeTo(0, 0.001));
      expect(pig.dirt(now.add(const Duration(hours: 8))), closeTo(50, 0.01));
      expect(pig.dirt(now.add(const Duration(days: 2))), 100);
      await pigs.bathe(pig, now.add(const Duration(hours: 8)));
      expect(pig.dirt(now.add(const Duration(hours: 8))), 0);
    });
  });

  group('starvation pauses growth', () {
    /// 30h old, fed 10h ago: starving for the last 2h.
    Pig starvedPig(DateTime now) {
      final pig = Pig(
        id: 500,
        breedId: 'truffle',
        name: 'Peckish',
        adoptedAt: now.subtract(const Duration(hours: 30)),
        fedAt: now.subtract(const Duration(hours: 10)),
      );
      pigs.debugAdd(pig);
      return pig;
    }

    test('wall-clock age minus starved spells is the effective age', () {
      final now = DateTime.now();
      final pig = starvedPig(now);
      expect(pig.hunger(now), 0);
      final age = PigService.effectiveAgeOf(pig, now);
      expect(age.inHours, 28);
      expect(PigService.stageOf(pig, now), PigStage.grown);
      // The pause also pushes the next stage back.
      expect(
        PigService.timeToNextStage(pig, now)!.inHours,
        PigService.chunkyAfter.inHours - 28,
      );
    });

    test('feeding banks the spell so growth resumes cleanly', () async {
      final now = DateTime.now();
      final pig = starvedPig(now);
      await pigs.feed(pig, now);
      expect(pig.starvedSeconds, 2 * 3600);
      expect(pig.hunger(now), 100);
      // Effective age is stable across the meal: 30h - 2h banked.
      expect(PigService.effectiveAgeOf(pig, now).inHours, 28);
      // ...and again an hour later, growing normally.
      final later = now.add(const Duration(hours: 1));
      expect(PigService.effectiveAgeOf(pig, later).inHours, 29);
    });
  });

  group('breeding', () {
    test('old saves migrate without new fields', () {
      final legacy = Pig.fromJson({
        'id': 7,
        'breed': 'truffle',
        'name': 'Legacy',
        'pets': 3,
        'adoptedAt': DateTime.now().millisecondsSinceEpoch,
      });
      expect(legacy.gender, isNotNull);
      expect(legacy.starvedSeconds, 0);
      expect(legacy.isPregnant, isFalse);
      expect(legacy.hunger(), closeTo(100, 0.001));
      expect(legacy.dirt(), closeTo(0, 0.001));
    });

    Pig adult(PigGender gender, {String breed = 'truffle'}) {
      final pig = Pig(
        id: pigs.pigs.length + 100,
        breedId: breed,
        name: 'Adult $gender',
        gender: gender,
        adoptedAt: DateTime.now().subtract(const Duration(hours: 48)),
      );
      pigs.debugAdd(pig);
      return pig;
    }

    test('eligibility: genders, stage, hunger, pregnancy', () {
      final now = DateTime.now();
      final sow = adult(PigGender.female);
      final boar = adult(PigGender.male);

      expect(PigService.canBreed(sow, boar, now), isTrue);

      // Same gender is out.
      final sow2 = adult(PigGender.female);
      expect(PigService.canBreed(sow, sow2, now), isFalse);

      // Piglets are out.
      final young = Pig(
        id: 777,
        breedId: 'truffle',
        name: 'Young',
        gender: PigGender.male,
        adoptedAt: now, // brand new = piglet
      );
      pigs.debugAdd(young);
      expect(PigService.canBreed(sow, young, now), isFalse);

      // A starving pig is out.
      boar.fedAt = now.subtract(const Duration(hours: 9));
      expect(PigService.canBreed(sow, boar, now), isFalse);
      boar.fedAt = now;

      // An already-expecting sow is out.
      expect(pigs.breed(sow, boar, now), isTrue);
      expect(PigService.canBreed(sow, boar, now), isFalse);
    });

    test('a litter arrives when due, of a parent breed', () async {
      final now = DateTime.now();
      final sow = adult(PigGender.female, breed: 'blueberry');
      final boar = adult(PigGender.male, breed: 'ember');
      final before = pigs.pigs.length;

      expect(pigs.breed(sow, boar, now), isTrue);
      expect(sow.isPregnant, isTrue);
      expect(sow.dueAt!.difference(now), PigService.pregnancy);

      // Too early: nothing yet.
      pigs.checkBirths(now.add(const Duration(hours: 5)));
      expect(pigs.pigs.length, before);

      // Due: one piglet, of one of the parents' breeds, sow cleared.
      pigs.checkBirths(now.add(const Duration(hours: 7)));
      expect(pigs.pigs.length, before + 1);
      expect(sow.isPregnant, isFalse);
      final piglet = pigs.pigs.last;
      expect(
        piglet.breedId,
        anyOf('blueberry', 'ember'),
      );
      expect(PigService.stageOf(piglet, now.add(const Duration(hours: 7))),
          PigStage.piglet);
    });

    test('births wait for pen room', () {
      final now = DateTime.now();
      final sow = adult(PigGender.female);
      final boar = adult(PigGender.male);
      pigs.breed(sow, boar, now);
      while (!pigs.isFull) {
        final filler = Pig(
            id: 1000 + pigs.pigs.length,
            breedId: 'truffle',
            name: 'F',
            adoptedAt: now);
        pigs.debugAdd(filler);
      }
      pigs.checkBirths(now.add(const Duration(hours: 7)));
      expect(pigs.pigs.length, PigService.capacity);
      expect(sow.isPregnant, isTrue); // still waiting
    });

    test('a pregnant sow cannot be sold', () async {
      final now = DateTime.now();
      final sow = Pig(
        id: 950,
        breedId: 'truffle',
        name: 'Sow',
        gender: PigGender.female,
        adoptedAt: now.subtract(const Duration(hours: 48)),
      );
      pigs.debugAdd(sow);
      final boar = adult(PigGender.male);
      pigs.breed(sow, boar, now);
      final coins = settings.coins;
      expect(await pigs.sell(sow), isNull);
      expect(settings.coins, coins);
      expect(pigs.pigs.contains(sow), isTrue);
    });
  });

  group('corn & decor', () {
    test('corn spends atomically', () async {
      await profile.addCorn(5);
      expect(await profile.spendCorn(3), isTrue);
      expect(profile.corn, 2);
      expect(await profile.spendCorn(3), isFalse);
      expect(profile.corn, 2);
    });

    test('decor takes the first free slot and frees it on removal', () async {
      final a = profile.placeDecor('ball');
      final b = profile.placeDecor('hay');
      expect(a, 0);
      expect(b, 1);
      expect(profile.removeDecor('ball'), isTrue);
      expect(profile.placeDecor('pumpkin'), 0); // reuses the freed slot
      // Filling every slot.
      for (final id in ['mushroom', 'flowers', 'lantern', 'scarecrow', 'cart', 'fence']) {
        profile.placeDecor(id);
      }
      expect(profile.decor.length, FarmProfile.decorSlots);
      expect(profile.placeDecor('oneMore'), isNull);
    });
  });

  group('gacha catalog integrity', () {
    // _rollBreed picks uniformly inside a star tier, so an empty tier would
    // make Random.nextInt(0) throw mid-pull, and a breed outside pullOdds
    // could never be pulled at all.
    test('every pullOdds tier has at least one breed', () {
      for (final stars in PigService.pullOdds.keys) {
        expect(PigService.breeds.any((b) => b.stars == stars), isTrue,
            reason: 'no breed lives in tier $stars');
      }
    });

    test('pull odds sum to 100 and cover every breed tier', () {
      expect(PigService.pullOdds.values.reduce((a, b) => a + b), 100);
      for (final breed in PigService.breeds) {
        expect(PigService.pullOdds.containsKey(breed.stars), isTrue,
            reason: '${breed.id} (${breed.name}) is unreachable');
      }
    });

    test('breed ids are unique', () {
      final ids = PigService.breeds.map((b) => b.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('50 breeds, each wearing a distinct design, all designs worn',
        () {
      expect(PigService.breeds.length, 50);
      expect(pigDesigns.length, 50);
      final worn = PigService.breeds.map((b) => b.design).toList();
      expect(worn.toSet().length, 50, reason: 'two breeds share a design');
      expect(worn.toSet(), pigDesigns.toSet(), reason: 'an unused design');
      // Aura rings are the 4★+ flex: every epic/legendary wears one, no
      // common/uncommon/rare does.
      for (final b in PigService.breeds) {
        expect(b.design.aura == AuraStyle.none, b.stars < 4,
            reason: '${b.name} (${b.stars}★) aura mismatch');
      }
    });
  });

  group('worlds', () {
    test('levels cross cumulative thresholds', () async {
      // Regression: _grantXp once compared "total XP >= total XP + cost",
      // so the farm never rose past Lv.1 and no unlock ever fired.
      // XP math here is deterministic: saves always pay 4 XP and the save
      // quest (goal 3, always on the board) pays 15 once. Achievements
      // only re-evaluate on pig events, so they pay nothing in this test.
      expect(profile.level, 1);
      for (var i = 0; i < 6; i++) {
        await profile.recordWordSaved();
      }
      // 24 XP + 15 quest = 39: one short of the Lv.2 threshold.
      expect(profile.level, 1, reason: '39 xp is one short of 40');
      await profile.recordWordSaved(); // → 43
      expect(profile.level, 2, reason: '43 xp must reach level 2');
      expect(profile.xpIntoLevel, 3);
      for (var i = 7; i < 23; i++) {
        await profile.recordWordSaved(); // → 107
      }
      expect(profile.level, 2, reason: '107 xp is three short of 110');
      await profile.recordWordSaved(); // → 111
      expect(profile.level, 3);
      expect(profile.xpIntoLevel, 1);
    });

    test('locked worlds refuse to open and persist the choice', () async {
      // Fresh profile: level 1, only the meadow is open.
      expect(profile.world, WorldId.meadow);
      expect(await profile.setWorld(WorldId.ship), isFalse);
      expect(profile.world, WorldId.meadow);

      // Level up past every unlock, then move and restore.
      while (profile.level < 13) {
        await profile.recordMastered();
        await profile.recordMastered();
        await profile.recordMastered();
        await profile.recordMastered();
      }
      expect(await profile.setWorld(WorldId.skyisland), isTrue);
      expect(profile.world, WorldId.skyisland);

      // A world above the unlock level falls back to the meadow.
      SharedPreferences.setMockInitialValues({
        'farm_profile_v1': '{"xp":2460,"level":1,"world":"skyisland"}',
      });
      final demoted = FarmProfile(settings, pigs);
      await demoted.init();
      expect(demoted.world, WorldId.meadow,
          reason: 'a save edited down a level can not keep a locked world');
    });
  });
}
