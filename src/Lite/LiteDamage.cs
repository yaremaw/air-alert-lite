using System;

/// Damage and armor. A hit deals the warhead's power less the target's
/// armor, never less than MinDamage: drones do little to anything armored,
/// a ballistic missile hurts everything.
public static class LiteDamage
{
	public static float Dealt(LiteArm a, LiteKind k) => MathF.Max(LiteRules.MinDamage, LiteRules.Power(a) - LiteRules.Armor(k));

	/// Health a weapon of kind `a` can take off a `k` with `hp` left: no more than it has.
	public static float Useful(LiteArm a, LiteKind k, float hp) => MathF.Min(Dealt(a, k), hp);
}
