class_name LiteKind

## DEPOT, LAUNCHER, POWER and JAMMER are campaign sites, set out by an
## operation, never built.
## POWER: a power station; destroyed, its side's SAMs go silent for a day.
## JAMMER: electronic warfare; the other side's drones that fly into its
## circle are often lost (missiles are not fooled).
## RADAR: a long-range radar (built, since phase 4): it sees far, and air
## defence near it fights by its picture (see LiteSense).
## MOBILE: a mobile anti-drone unit, cheap and short-ranged, set down where
## it is needed and staying there. MRADAR: a mobile radar, smaller and
## cheaper than RADAR, to fill gaps.
## OILRIG, REFINERY, SUBSTATION, PUMP, SILO: a country's working sites where
## its land suits them (see LiteBiome): income, and its people's morale when
## they are hit. A SUBSTATION also feeds the radars round it.
## UNIT: enemy forces on the move in an operation (see LiteUnit): never
## built, drawn as NATO symbols, not sprites.
enum { CAPITAL, FACTORY, GUN, SAM, DEPOT, RADAR, LAUNCHER, POWER, JAMMER,
	MOBILE, MRADAR, OILRIG, REFINERY, SUBSTATION, PUMP, SILO, UNIT }

## The sites a side can build, in the toolbar's order. A REFINERY makes the
## money (an oil field in the desert); a FACTORY makes the weapons.
const BUILT: Array[int] = [FACTORY, REFINERY, GUN, SAM, MOBILE, RADAR]

static func is_radar(k: int) -> bool:
	return k == RADAR or k == MRADAR

## Air defence that shoots (a capital's guns too).
static func shoots(k: int) -> bool:
	return k == GUN or k == SAM or k == MOBILE or k == CAPITAL

## A country's working sites (see LiteBiome).
static func is_works(k: int) -> bool:
	return k >= OILRIG and k <= SILO
