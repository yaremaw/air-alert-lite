/// Every tunable number of the lite game, in one place. Both sides, the AI
/// and the interface read them from here, so rebalancing is editing this file.
public static class LiteRules
{
	// ---------------------------------------------------------------- economy

	public const float StartMoney = 400f;
	/// Money a side earns a second with no factory, and what each working factory adds.
	public const float BaseIncome = 3f, FactoryIncome = 4f;
	/// Production points (PP) a second with no factory, and what each working factory adds.
	public const float BasePP = 1f, FactoryPP = 1.2f;
	/// A factory whose region is under air alert works at this share of its pace (money and PP).
	public const float AlertWork = 0.5f;
	/// The first factory's price; every further one costs this many times the one before.
	public const float FactoryCost = 130f, FactoryGrowth = 1.35f;
	/// The first air defence system's price, and how much dearer each further one is.
	public const int AdCost = 220, AdStep = 40;
	/// Air defence systems a region can hold.
	public const int AdPerRegion = 3;
	/// Repairs (while switched on): a damaged building gets back this share of
	/// its full health a second, at this price for every 1% of its health.
	public const float RepairRate = 0.01f, RepairPrice = 1.5f;
	/// A destroyed factory leaves ruins that take its place in the region this long.
	public const float RuinTime = 180f;
	/// How often industry shifts between regions on each side.
	public const float IndustryShift = 120f;
	/// How often each side's intelligence locates one hidden site of the other's.
	public const float IntelEvery = 75f;
	public const float AllClearAfter = 3f;

	// ---------------------------------------------------------------- difficulty (Easy, Normal, Hard)

	/// The enemy's money and production, as a share of ours. Its bigger
	/// country is harder to defend, so from Normal up it gets a little more.
	public static readonly float[] EnemyIncome = { 0.8f, 1.1f, 1.3f };
	/// Time between the enemy's raids, as a share of the usual.
	public static readonly float[] EnemyTempo = { 1.3f, 1f, 0.85f };

	// ---------------------------------------------------------------- production

	/// Production points each weapon takes to build.
	public static float PP(LiteArm a) => a switch { LiteArm.Drone => 5f, LiteArm.Cruise => 30f, _ => 80f };
	/// Weapons each side has in stock when the war starts.
	public static int StartStock(LiteArm a) => a switch { LiteArm.Drone => 12, LiteArm.Cruise => 2, _ => 0 };
	/// The longest the production queue can be.
	public const int QueueMax = 20;

	// ---------------------------------------------------------------- buildings

	public static float BuildTime(LiteKind k) => k switch { LiteKind.Factory => 8f, LiteKind.Ad => 7f, _ => 0f };
	public static float Range(LiteKind k) => k == LiteKind.Ad ? AdRange : 0f;

	// ---------------------------------------------------------------- targets, armor, damage

	/// Each capital has four key targets round it; destroying this many of
	/// the other side's wins the war.
	public const int KeysToWin = 3;
	/// How far from the capital's middle the key targets stand.
	public const float KeyRing = 24f;
	public static float MaxHp(LiteKind k) => k switch
	{
		LiteKind.Factory => 60f, LiteKind.Ad => 40f,
		LiteKind.Hq => 360f, LiteKind.Bunker => 450f, LiteKind.Energy => 260f, _ => 310f,
	};
	public static float Armor(LiteKind k) => k switch
	{
		LiteKind.Factory => 2f, LiteKind.Ad => 3f,
		LiteKind.Hq => 6f, LiteKind.Bunker => 12f, LiteKind.Energy => 4f, _ => 8f,
	};
	/// A hit deals max(MinDamage, Power − Armor).
	public const float MinDamage = 1f;
	public static float Power(LiteArm a) => a switch { LiteArm.Drone => 10f, LiteArm.Cruise => 60f, _ => 200f };

	// ---------------------------------------------------------------- air defence

	/// Reach of a system, and the width of its radar sector in degrees; it
	/// engages only what is inside the sector.
	public const float AdRange = 125f, AdArc = 120f;
	/// How fast a system turns to a new facing, degrees a second.
	public const float AdTurnRate = 45f;
	/// Weapons a system can track and fire at at once, and the seconds
	/// between the interceptors each of them fires.
	public const int AdChannels = 2;
	public const float AdShotInterval = 1.6f, InterceptorSpeed = 330f;
	/// Chance one interceptor brings down each kind of weapon.
	public static float AdHit(LiteArm a) => a switch { LiteArm.Drone => 0.35f, LiteArm.Cruise => 0.22f, _ => 0.08f };
	/// Radars see this many times their firing range, all round.
	public const float RadarReach = 1.5f;

	// ---------------------------------------------------------------- weapons

	public static float Speed(LiteArm a) => a switch { LiteArm.Drone => 26f, LiteArm.Cruise => 72f, _ => 220f };
	/// What a hit reaches round itself, and how far from the aim point it lands.
	public static float Blast(LiteArm a) => a switch { LiteArm.Drone => 9f, LiteArm.Cruise => 11f, _ => 14f };
	public static float Scatter(LiteArm a) => a switch { LiteArm.Drone => 4f, LiteArm.Cruise => 3f, _ => 7f };
	/// How far round itself a weapon in flight reveals the other side's sites.
	public static float SpotRadius(LiteArm a) => a switch { LiteArm.Drone => 46f, LiteArm.Cruise => 26f, _ => 0f };
	/// Regions within this distance of a drone or cruise missile go under alert...
	public static float AlertRadius(LiteArm a) => a switch { LiteArm.Drone => 30f, LiteArm.Cruise => 34f, _ => 0f };
	/// ...and so do those it would reach in this many seconds on its present
	/// heading. Nobody on the ground knows its route.
	public static float Heading(LiteArm a) => a switch { LiteArm.Drone => 4f, LiteArm.Cruise => 3f, _ => 0f };
}
