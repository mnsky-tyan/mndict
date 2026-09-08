import 'dart:ui';

/// The farm's art direction, decoded from the reference boards
/// (pigs/*.jpg — the 摩爾莊園-style pet scenes): chibi vinyl-toy pigs with
/// BOLD dark outlines, flat candy colours, two-tone cel shading, and — the
/// part that makes a breed feel rare — a full themed costume (pineapple
/// skin, sailor suit, flame mane) instead of a recolour.
///
/// This file is the vocabulary; pig_painter.dart is the renderer. Every
/// breed below is one const spec, so the market, the codex and the scene
/// all draw the exact same pig.

// -- part vocabularies --------------------------------------------------------

/// Coat markings painted inside the body silhouette.
enum CoatPattern {
  none,
  bigPatch, // one large contrasting patch (cow-like)
  spots, // scattered round spots
  freckles, // tiny cheek-dot scatter
  stripes, // horizontal bands (bee / watermelon rind)
  diamonds, // criss-cross grid (pineapple)
  seeds, // little dash seeds (strawberry / watermelon flesh)
  scales, // overlapping fish arcs
  wool, // fluffy cloud tufts along the silhouette
  splats, // paint/mud splats
  stars, // twinkling four-point stars
  hexes, // honeycomb
  bubbles, // transparent circles
  circuitry, // mecha panel lines + LED dots
  nebula, // deep-space gradient + star dust
  bands, // two-tone vertical split
  creamSwirl, // soft swirl blob top-down
  mintChips, // dark chips in a light field
  runes, // glyph ticks
  waves, // layered water curves
  flames, // rising flame licks
}

enum EarStyle { round, floppy, leaf, hornSmall, hornBig, antenna, fox, fin }

enum TailStyle { curl, curlTight, straight, tuft, flame, bolt, feather, fin }

enum EyeStyle { glossy, bead, happy, sly, visor }

enum SnoutStyle { standard, big, tiny, golden }

/// What the pig wears / carries / sprouts. Rendered by the painter in
/// back → body → face → hat → fore order.
enum HatKind {
  none,
  sprout, // single leaf stem
  flowerOne, // one bloom tucked on the head
  beanie, // knit beanie with pompom
  butter, // a square of butter (Butterscotch)
  berryBasket, // upturned basket of berries
  whippedCream, // swirl of cream + cherry
  raindrop, // droplet cap
  scarfOnly, // no hat, but a cosy scarf (colour via hatColor)
  leafCrown, // layered tropical leaves (pineapple / strawberry)
  huskCollar, // corn-leaf collar
  bambooSpike, // matcha whisk leaves
  candyWrap, // twisted wrapper bows
  sailorCap, // white disc cap + navy band
  tricorn, // pirate hat with skull
  bandana, // knotted headscarf
  wizardHat, // tall bent hat + star
  ninjaBand, // tied headband with tail
  chefToque, // tall pleated hat
  strawHat, // brimmed gardening hat + flower
  kabukiWig, // black side-puffs + red comb
  icicleCrown, // crystal spikes
  beeAntennae, // twin bobbed antennae
  featherCrest, // peacock fan of feathers
  vikingHelm, // riveted helm + horns
  crownGold, // three-point gem crown
  haloRing, // floating golden ring
  flameCrest, // mohawk of fire
  foxMask, // half fox mask on the forehead
  antennaLight, // mecha antenna + bulb
  moonCirclet, // crescent over the brow
  sunCorona, // radiant sun disc
  pearlDive, // diver cap + goggles
  crystalHalo, // floating ice crystals
  comet, // shooting-star clip
  treasurePile, // coins & gems heaped on the head
  prismCrown, // refracting crystal fan
  voidHalo, // dark eclipse ring
}

enum BackKind {
  none,
  angelWings, // white feather wings
  frostWings, // icy shard wings
  flameWings, // fire wings
  beetleWings, // translucent insect wings
  cape, // short cloth cape
  royalCape, // ermine-trimmed cape
  shellPack, // turtle-ish shell / backpack
  leafPack, // leafy knapsack
  jetpack, // tiny rocket pack
  fanTail, // peacock tail fan
  bubbleRing, // ring of floating bubbles
  fins, // dorsal fin + side fins
  voidRift, // cracked purple rift
}

enum ForeKind {
  none,
  sword, // cutlass across the front
  wand, // star-tipped wand
  spoon, // wooden mixing spoon
  fan, // folding fan
  trowel, // little garden spade
  shuriken, // held star blade
  goldCoin, // big coin against the chest
  gem, // heart-cut gem
  iceCream, // cone with a scoop
  corn, // an ear of corn
  pearl, // glowing orb
  drumstick, // honey drumstick
  umbrella, // leaf parasol held up
}

/// One breed's complete look. All colours are flat fills; the painter adds
/// cel shading, outlines and gloss. Stage (piglet/grown/chunky) changes
/// proportions and pattern density, not this spec.
class PigDesign {
  final Color body;
  final Color? belly; // lighter chest patch; null = none
  final Color snout;
  final Color blush;
  final Color outline; // stroke colour that outlines the pig

  final CoatPattern pattern;
  final Color? patternColor;
  final Color? patternColor2;

  final EarStyle ears;
  final Color? earInner;
  final TailStyle tail;

  final EyeStyle eyes;
  final Color? eyeColor;

  final SnoutStyle snoutStyle;

  final HatKind hat;
  final Color? hatColor;
  final Color? hatColor2;

  final BackKind back;
  final Color? backColor;
  final Color? backColor2;

  final ForeKind fore;
  final Color? foreColor;

  /// Rarity aura at the feet (4★+ designs only).
  final AuraStyle aura;

  const PigDesign({
    required this.body,
    required this.snout,
    required this.blush,
    this.belly,
    this.outline = const Color(0xFF43302E),
    this.pattern = CoatPattern.none,
    this.patternColor,
    this.patternColor2,
    this.ears = EarStyle.round,
    this.earInner,
    this.tail = TailStyle.curl,
    this.eyes = EyeStyle.glossy,
    this.eyeColor,
    this.snoutStyle = SnoutStyle.standard,
    this.hat = HatKind.none,
    this.hatColor,
    this.hatColor2,
    this.back = BackKind.none,
    this.backColor,
    this.backColor2,
    this.fore = ForeKind.none,
    this.foreColor,
    this.aura = AuraStyle.none,
  });
}

enum AuraStyle { none, gold, frost, fire, star, voidRift, rainbow }

// -- the palette (candy-flat, high saturation, warm dark outline) ------------

const _kPink = Color(0xFFFFA8BC);
const _kPinkDeep = Color(0xFFF27FA0);
const _kCream = Color(0xFFFDF3DC);
const _kButter = Color(0xFFFFD666);
const _kMango = Color(0xFFFFB84D);
const _kCoral = Color(0xFFFF8A66);
const _kRed = Color(0xFFEF5D6A);
const _kCherry = Color(0xFFE5484D);
const _kRosewood = Color(0xFFC05C4E);
const _kCocoa = Color(0xFF9C6242);
const _kCoffee = Color(0xFF8A5A3E);
const _kMocha = Color(0xFFB98A5E);
const _kMint = Color(0xFF9FE0B0);
const _kLeaf = Color(0xFF6FBF63);
const _kPine = Color(0xFF4E9E5F);
const _kTeal = Color(0xFF5FC9C0);
const _kAqua = Color(0xFF8FDFF0);
const _kSky = Color(0xFF7EC3EE);
const _kBlue = Color(0xFF7D9BE8);
const _kPeriwinkle = Color(0xFF9DB4F0);
const _kNavy = Color(0xFF44589C);
const _kViolet = Color(0xFF9A7BD8);
const _kPurple = Color(0xFF7C5FB8);
const _kPlum = Color(0xFFB37BA8);
const _kLilac = Color(0xFFC9AEE8);
const _kWhite = Color(0xFFFDF9F0);
const _kSilver = Color(0xFFD7DEE8);
const _kSteel = Color(0xFFAEB9C9);
const _kSlate = Color(0xFF8E9AAB);
const _kCharcoal = Color(0xFF5A6070);
const _kNight = Color(0xFF4A4677);
const _kGold = Color(0xFFF7C948);
const _kDeepGold = Color(0xFFDDA322);
const _kPeachSnout = Color(0xFFF2A9A0);
const _kRoseSnout = Color(0xFFEE8FA8);

// -- the 50 designs ------------------------------------------------------------
// Tier order: 10 commons (charming starters), 13 uncommons (food skins),
// 12 rares (jobs & characters), 9 epics (fantasy + aura), 6 legendaries.
// ids marked (*) existed in the first build — kept so saved pigs survive.

const List<PigDesign> pigDesigns = [
  // ===== ★1 commons =====
  PigDesign(
    body: _kPink, snout: _kRoseSnout, blush: _kPinkDeep, // *truffle
    pattern: CoatPattern.bigPatch, patternColor: Color(0xFFEFC98F),
    belly: _kCream, hat: HatKind.flowerOne, hatColor: _kCherry,
  ),
  PigDesign(
    body: _kMango, snout: Color(0xFFE89A5A), blush: _kCoral, // *butterscotch
    belly: _kCream, hat: HatKind.butter, hatColor: _kButter,
  ),
  PigDesign(
    body: _kSlate, snout: Color(0xFF77839B), blush: _kBlue, // pebble
    pattern: CoatPattern.spots, patternColor: Color(0xFF6D7890),
    belly: _kSilver, eyes: EyeStyle.bead,
  ),
  PigDesign(
    body: Color(0xFFC7EFCF), snout: Color(0xFF93C7A0), blush: _kLeaf, // clover
    hat: HatKind.sprout, hatColor: _kPine,
    pattern: CoatPattern.freckles, patternColor: Color(0xFF8FDCA0),
  ),
  PigDesign(
    body: _kButter, snout: Color(0xFFEAC25A), blush: _kMango, // sunny
    belly: _kCream,
    tail: TailStyle.curlTight,
  ),
  PigDesign(
    body: _kPlum, snout: Color(0xFF9B6E92), blush: Color(0xFFC868A8), // berry
    hat: HatKind.berryBasket, hatColor: _kCherry,
    pattern: CoatPattern.freckles, patternColor: Color(0xFFC893D8),
  ),
  PigDesign(
    body: _kCocoa, snout: Color(0xFF7E4E34), blush: _kRosewood, // cocoa
    hat: HatKind.whippedCream, hatColor: _kCream,
    belly: _kMocha, ears: EarStyle.floppy,
  ),
  PigDesign(
    body: Color(0xFFEAF6FB), snout: Color(0xFFCFE4EE), blush: _kAqua, // snowdrop
    hat: HatKind.scarfOnly, hatColor: _kSky,
    earInner: _kAqua, eyes: EyeStyle.bead,
  ),
  PigDesign(
    body: _kPeriwinkle, snout: Color(0xFF7E97DE), blush: _kBlue, // *blueberry
    belly: Color(0xFFEDF1FC),
    pattern: CoatPattern.freckles, patternColor: _kBlue,
    ears: EarStyle.round,
  ),
  PigDesign(
    body: _kAqua, snout: Color(0xFF6FB8D8), blush: _kSky, // puddle
    pattern: CoatPattern.splats, patternColor: Color(0xFFBDEBF7),
    hat: HatKind.raindrop, hatColor: _kSky,
  ),

  // ===== ★2 uncommons (food skins) =====
  PigDesign(
    body: _kButter, snout: Color(0xFFE8B23A), blush: _kMango, // pineapple
    pattern: CoatPattern.diamonds, patternColor: Color(0xFFE2A52E),
    hat: HatKind.leafCrown, hatColor: _kPine,
    tail: TailStyle.tuft,
  ),
  PigDesign(
    body: _kCherry, snout: Color(0xFFC9525A), blush: _kRosewood, // strawberry
    pattern: CoatPattern.seeds, patternColor: _kButter,
    hat: HatKind.leafCrown, hatColor: _kLeaf,
    belly: Color(0xFFF4757F),
  ),
  PigDesign(
    body: _kLeaf, snout: Color(0xFF579452), blush: _kPine, // watermelon
    pattern: CoatPattern.stripes, patternColor: _kPine,
    patternColor2: Color(0xFFEF6B78),
    hat: HatKind.leafCrown, hatColor: _kPine,
    tail: TailStyle.curlTight,
  ),
  PigDesign(
    body: Color(0xFFF6D9E2), snout: _kRoseSnout, blush: _kPinkDeep, // mochi
    pattern: CoatPattern.bands, patternColor: _kWhite,
    hat: HatKind.sprout, hatColor: Color(0xFF9FCB84),
    ears: EarStyle.round,
  ),
  PigDesign(
    body: Color(0xFFE8A63C), snout: Color(0xFFC9862E), blush: _kMango, // honey
    pattern: CoatPattern.creamSwirl, patternColor: Color(0xFFFFE9B0),
    hat: HatKind.whippedCream, hatColor: Color(0xFFFFE9B0),
    fore: ForeKind.goldCoin, foreColor: _kGold,
  ),
  PigDesign(
    body: _kCoffee, snout: Color(0xFF6F4630), blush: _kRosewood, // mocha
    pattern: CoatPattern.bands, patternColor: _kCream,
    hat: HatKind.whippedCream, hatColor: _kCream,
    eyes: EyeStyle.bead,
  ),
  PigDesign(
    body: _kMint, snout: Color(0xFF7BBF8C), blush: _kLeaf, // *matcha
    pattern: CoatPattern.creamSwirl, patternColor: Color(0xFFEFF8EF),
    hat: HatKind.bambooSpike, hatColor: _kPine,
    belly: Color(0xFFEFF8EF),
  ),
  PigDesign(
    body: Color(0xFFF3EFFF), snout: Color(0xFFD0C2EE), blush: _kPeriwinkle, // bubbles
    pattern: CoatPattern.bubbles, patternColor: _kAqua,
    hat: HatKind.candyWrap, hatColor: _kPeriwinkle,
    back: BackKind.bubbleRing, backColor: _kAqua,
  ),
  PigDesign(
    body: _kButter, snout: Color(0xFFE0A93A), blush: _kMango, // corn
    pattern: CoatPattern.diamonds, patternColor: Color(0xFFE8B84D),
    hat: HatKind.huskCollar, hatColor: _kLeaf,
    fore: ForeKind.corn, foreColor: _kButter,
  ),
  PigDesign(
    body: Color(0xFF9E5E86), snout: Color(0xFF84496E), blush: _kPlum, // jam
    pattern: CoatPattern.splats, patternColor: Color(0xFFC46FA6),
    hat: HatKind.berryBasket, hatColor: _kLilac,
  ),
  PigDesign(
    body: Color(0xFFF8C8DA), snout: _kRoseSnout, blush: _kPinkDeep, // cottoncandy
    pattern: CoatPattern.wool, patternColor: Color(0xFFBFDCF5),
    hat: HatKind.candyWrap, hatColor: _kPeriwinkle,
    tail: TailStyle.tuft,
  ),
  PigDesign(
    body: _kLilac, snout: Color(0xFFAC8BD4), blush: _kViolet, // macaron
    pattern: CoatPattern.bands, patternColor: _kCream,
    hat: HatKind.whippedCream, hatColor: _kCherry,
    belly: _kCream,
  ),
  PigDesign(
    body: _kMocha, snout: Color(0xFF9A6E44), blush: _kCoral, // biscuit
    pattern: CoatPattern.bigPatch, patternColor: _kCream,
    hat: HatKind.beanie, hatColor: _kCherry,
  ),

  // ===== ★3 rares (jobs & characters) =====
  PigDesign(
    body: _kWhite, snout: _kPeachSnout, blush: _kCoral, // sailor
    hat: HatKind.sailorCap, hatColor: _kNavy,
    back: BackKind.cape, backColor: _kNavy,
    fore: ForeKind.none,
  ),
  PigDesign(
    body: _kCream, snout: _kPeachSnout, blush: _kCherry, // buccaneer
    hat: HatKind.tricorn, hatColor: Color(0xFF3A3F52),
    fore: ForeKind.sword, foreColor: _kSilver,
    pattern: CoatPattern.stripes, patternColor: _kNavy,
    eyeColor: _kGold,
  ),
  PigDesign(
    body: _kViolet, snout: Color(0xFF8163BC), blush: _kPurple, // wizard
    hat: HatKind.wizardHat, hatColor: _kPurple,
    back: BackKind.cape, backColor: Color(0xFF684CA6),
    fore: ForeKind.wand, foreColor: _kGold,
    eyes: EyeStyle.sly,
  ),
  PigDesign(
    body: Color(0xFF3E4356), snout: Color(0xFF565C74), blush: _kCherry, // ninja
    hat: HatKind.ninjaBand, hatColor: _kCherry,
    fore: ForeKind.shuriken, foreColor: _kSilver,
    eyes: EyeStyle.sly, ears: EarStyle.round,
  ),
  PigDesign(
    body: _kCream, snout: _kPeachSnout, blush: _kCherry, // chef
    hat: HatKind.chefToque, hatColor: _kWhite,
    fore: ForeKind.spoon, foreColor: _kCoffee,
    belly: _kWhite, pattern: CoatPattern.bigPatch,
    patternColor: Color(0xFFF2DFC0),
  ),
  PigDesign(
    body: Color(0xFF8FD08F), snout: Color(0xFF77B577), blush: _kLeaf, // gardener
    hat: HatKind.strawHat, hatColor: _kButter,
    fore: ForeKind.trowel, foreColor: _kSlate,
    pattern: CoatPattern.bands, patternColor: Color(0xFF6C8FD4),
  ),
  PigDesign(
    body: _kWhite, snout: _kPeachSnout, blush: _kCherry, // kabuki
    hat: HatKind.kabukiWig, hatColor: Color(0xFF2E2438),
    fore: ForeKind.fan, foreColor: _kRed,
    pattern: CoatPattern.bands, patternColor: _kRed,
    eyes: EyeStyle.sly,
  ),
  PigDesign(
    body: Color(0xFFD93A3A), snout: Color(0xFFB92F42), blush: _kGold, // firecracker
    hat: HatKind.flameCrest, hatColor: _kGold,
    pattern: CoatPattern.splats, patternColor: _kGold,
    tail: TailStyle.flame,
  ),
  PigDesign(
    body: _kAqua, snout: Color(0xFF6FB8D8), blush: _kSky, // glacier
    hat: HatKind.icicleCrown, hatColor: _kAqua,
    pattern: CoatPattern.scales, patternColor: Color(0xFFBCE9F5),
    tail: TailStyle.fin,
  ),
  PigDesign(
    body: Color(0xFFF2C12E), snout: Color(0xFFD9A61E), blush: Color(0xFF4A3F2E), // bee
    pattern: CoatPattern.stripes, patternColor: Color(0xFF4A3F2E),
    hat: HatKind.beeAntennae, hatColor: Color(0xFF4A3F2E),
    back: BackKind.beetleWings, backColor: _kWhite,
    tail: TailStyle.bolt,
  ),
  PigDesign(
    body: _kTeal, snout: Color(0xFF4EAFA8), blush: _kNavy, // peacock
    pattern: CoatPattern.scales, patternColor: Color(0xFF7BD5CD),
    hat: HatKind.featherCrest, hatColor: _kNavy,
    back: BackKind.fanTail, backColor: _kTeal, backColor2: _kGold,
    tail: TailStyle.feather,
  ),
  PigDesign(
    body: _kCoral, snout: Color(0xFFE0765A), blush: _kCherry, // *ember
    hat: HatKind.flameCrest, hatColor: _kRed,
    pattern: CoatPattern.bands, patternColor: _kMango,
    tail: TailStyle.flame,
  ),

  // ===== ★4 epics (fantasy + aura) =====
  PigDesign(
    body: Color(0xFFE85D3D), snout: _kDeepGold, blush: _kCherry, // firebird
    hat: HatKind.flameCrest, hatColor: _kRed,
    back: BackKind.flameWings, backColor: _kRed, backColor2: _kGold,
    pattern: CoatPattern.flames, patternColor: _kGold,
    tail: TailStyle.flame, snoutStyle: SnoutStyle.golden,
    aura: AuraStyle.fire,
  ),
  PigDesign(
    body: _kSilver, snout: Color(0xFFB8C2D2), blush: _kSky, // *frosty
    hat: HatKind.crystalHalo, hatColor: _kAqua,
    back: BackKind.frostWings, backColor: _kAqua,
    pattern: CoatPattern.scales, patternColor: _kSteel,
    tail: TailStyle.feather, aura: AuraStyle.frost,
  ),
  PigDesign(
    body: _kWhite, snout: _kPeachSnout, blush: _kPink, // *halo (angel)
    hat: HatKind.haloRing, hatColor: _kGold,
    back: BackKind.angelWings, backColor: _kWhite,
    aura: AuraStyle.gold,
  ),
  PigDesign(
    body: _kPurple, snout: Color(0xFF684CA6), blush: _kCherry, // royal
    hat: HatKind.crownGold, hatColor: _kGold,
    back: BackKind.royalCape, backColor: Color(0xFFC0443E),
    pattern: CoatPattern.runes, patternColor: _kGold,
    fore: ForeKind.gem, foreColor: _kCherry,
    aura: AuraStyle.gold,
  ),
  PigDesign(
    body: Color(0xFFE4589A), snout: Color(0xFFC23E7E), blush: _kLeaf, // dragonfruit
    pattern: CoatPattern.splats, patternColor: Color(0xFF6FBF63),
    hat: HatKind.vikingHelm, hatColor: _kPine,
    ears: EarStyle.hornSmall, tail: TailStyle.flame,
    aura: AuraStyle.star,
  ),
  PigDesign(
    body: _kWhite, snout: _kPeachSnout, blush: _kMango, // kitsune
    pattern: CoatPattern.bands, patternColor: _kMango,
    hat: HatKind.foxMask, hatColor: _kRed,
    ears: EarStyle.fox, tail: TailStyle.feather,
    fore: ForeKind.fan, foreColor: _kGold,
    aura: AuraStyle.star,
  ),
  PigDesign(
    body: _kSteel, snout: Color(0xFF8A95A8), blush: _kSky, // mecha
    pattern: CoatPattern.circuitry, patternColor: Color(0xFF4ED8C6),
    hat: HatKind.antennaLight, hatColor: _kCharcoal,
    belly: Color(0xFF3A4050),
    eyes: EyeStyle.visor, tail: TailStyle.bolt,
    aura: AuraStyle.star,
  ),
  PigDesign(
    body: Color(0xFFBCCDF4), snout: Color(0xFF93A8DC), blush: _kPeriwinkle, // phantom
    pattern: CoatPattern.waves, patternColor: _kWhite,
    hat: HatKind.moonCirclet, hatColor: _kGold,
    back: BackKind.cape, backColor: Color(0xFF8FA4D8),
    eyeColor: Color(0xFF9CC7E2), tail: TailStyle.feather,
    aura: AuraStyle.frost,
  ),
  PigDesign(
    body: _kNight, snout: Color(0xFF6B66A0), blush: _kViolet, // starweaver
    pattern: CoatPattern.stars, patternColor: _kGold,
    hat: HatKind.comet, hatColor: _kGold,
    fore: ForeKind.wand, foreColor: _kLilac,
    aura: AuraStyle.star,
  ),

  // ===== ★5 legendaries =====
  PigDesign(
    body: _kGold, snout: _kDeepGold, blush: _kCherry, // *sol
    hat: HatKind.sunCorona, hatColor: _kMango,
    pattern: CoatPattern.bands, patternColor: _kMango,
    snoutStyle: SnoutStyle.golden, eyes: EyeStyle.happy,
    tail: TailStyle.flame, aura: AuraStyle.gold,
  ),
  PigDesign(
    body: _kNight, snout: Color(0xFF6B66A0), blush: _kLilac, // luna
    pattern: CoatPattern.nebula, patternColor: _kLilac,
    hat: HatKind.moonCirclet, hatColor: _kButter,
    fore: ForeKind.pearl, foreColor: _kAqua,
    tail: TailStyle.curlTight, aura: AuraStyle.star,
  ),
  PigDesign(
    body: Color(0xFF2E7F8A), snout: Color(0xFF20717C), blush: _kAqua, // leviathan
    pattern: CoatPattern.waves, patternColor: Color(0xFF9FE8E0),
    hat: HatKind.pearlDive, hatColor: _kGold,
    back: BackKind.fins, backColor: Color(0xFF20714F),
    ears: EarStyle.fin, tail: TailStyle.fin,
    snoutStyle: SnoutStyle.golden, aura: AuraStyle.frost,
  ),
  PigDesign(
    body: Color(0xFFF2B830), snout: Color(0xFFC08A18), blush: _kCherry, // goldheart
    pattern: CoatPattern.diamonds, patternColor: Color(0xFFFFDF7E),
    hat: HatKind.treasurePile, hatColor: _kGold,
    fore: ForeKind.gem, foreColor: _kCherry,
    snoutStyle: SnoutStyle.golden, aura: AuraStyle.gold,
  ),
  PigDesign(
    body: _kWhite, snout: _kPeachSnout, blush: _kPink, // prism
    pattern: CoatPattern.bands, patternColor: Color(0xFFB9F0D4),
    hat: HatKind.prismCrown, hatColor: _kAqua,
    back: BackKind.beetleWings, backColor: _kAqua,
    tail: TailStyle.feather, aura: AuraStyle.rainbow,
  ),
  PigDesign(
    body: Color(0xFF4A4266), snout: Color(0xFF6E64A0), blush: _kLilac, // *midnight → voidling
    pattern: CoatPattern.stars, patternColor: Color(0xFFD9CCF5),
    hat: HatKind.voidHalo, hatColor: _kLilac,
    back: BackKind.voidRift, backColor: Color(0xFFB89BE0),
    eyes: EyeStyle.sly, eyeColor: Color(0xFFE4DBFA),
    aura: AuraStyle.voidRift,
  ),
];
