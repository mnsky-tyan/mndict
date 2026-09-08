/// The farm's worlds — where the herd lives. Each is a full backdrop
/// theme (painters in ui/widgets/world_themes.dart); this file is the
/// game data so the profile and the UI agree without art dependencies.
enum WorldId { meadow, beach, ship, skyisland }

class WorldTheme {
  final WorldId id;
  final String name;
  final int unlockLevel;
  final String blurb;
  final String emoji;

  const WorldTheme(this.id, this.name, this.unlockLevel, this.blurb, this.emoji);
}

/// Buy order = unlock order. Levels ride the existing FarmProfile unlock
/// ladder (2–6 are meadow yard features; 7+ open new worlds).
const List<WorldTheme> worldCatalog = [
  WorldTheme(WorldId.meadow, 'Home Meadow', 1,
      'Where it all begins: barn, windmill, orchard.', '🚜'),
  WorldTheme(WorldId.beach, 'Sunset Beach', 7,
      'Warm sand, gentle surf, palm shade.', '🏝️'),
  WorldTheme(WorldId.ship, 'Pig Pirate Ship', 10,
      'A proper deck, a tall sail, open sea.', '🚢'),
  WorldTheme(WorldId.skyisland, 'Sky Island', 13,
      'A floating islet above the clouds.', '☁️'),
];

WorldTheme worldById(WorldId id) =>
    worldCatalog.firstWhere((w) => w.id == id);
