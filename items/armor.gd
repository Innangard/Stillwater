class_name Armor
extends Item
## Wearable equipment. Extends Item so it can sit in the inventory before
## being equipped (and after being unequipped) — same data flow as any
## other pickup.
##
## Three slots: HELMET, CHEST, BOOTS. The slot is a property of the armor
## itself, so the inventory UI knows which equipment slot a piece can go in.

enum ArmorSlot {
	HELMET,
	CHEST,
	BOOTS,
}

@export_group("Armor")
@export var armor_slot: ArmorSlot = ArmorSlot.CHEST
## Flat damage reduction subtracted before the multiplier.
@export var damage_reduction: float = 0.0
## Multiplier applied to incoming damage. 0.85 = 15% resist.
@export var damage_taken_multiplier: float = 1.0
## Per-element resistance multipliers. Optional. Same convention: 0.5 = halved.
## Keyed by Weapon.Element (int). Missing keys = no special resistance.
@export var element_multipliers: Dictionary = {}
## Per-second noise this piece adds while moving. Defaults to 0; set
## explicitly per piece. Roughly: leather ~3, mail ~8, plate ~15. Set to
## 0 for "silent" pieces (silken vestments, padded boots, etc.) regardless
## of damage_reduction.
@export var noise_weight: float = 0.0

@export_group("Build")
## Multiplier on outgoing damage from melee weapons. 1.10 = +10%.
## Applied at the Weapon.compute_outgoing_damage layer, gated on the
## weapon's category being "melee". 1.0 = no effect.
@export var melee_damage_multiplier: float = 1.0
## Multiplier on outgoing damage from ranged weapons. Same gating as
## melee_damage_multiplier but on category "ranged". 1.0 = no effect.
@export var ranged_damage_multiplier: float = 1.0
## Multiplier on player movement speed. Composes multiplicatively with
## status effects, kennings, and the sneak modifier. 1.0 = no effect.
@export var move_speed_multiplier: float = 1.0
## Flat bonus to max HP. Stacks additively with kenning HP bonuses. The
## KenningManager owns max-health recompute; it listens on armor_equipped
## and re-runs the math whenever a piece changes.
@export var max_health_bonus: float = 0.0


## Compute the post-armor damage given an incoming hit.
## Pure function — doesn't mutate anything. Apply multipliers, subtract flat,
## floor to 1 if the hit actually connected.
##
## Why floor at 1 and not 0:
##   Stacking armor used to let a heavy build reduce some hits all the way
##   to 0, which then early-returned out of HealthComponent.take_damage —
##   no flash, no audio, no smell increment. From the player's perspective
##   the hit never happened, even though it physically connected. That's
##   bad on two fronts: it broke the feedback contract (every connect
##   should register), and it let extreme armor stacks fully neutralize
##   chip damage from the toughest bosses, flattening the difficulty
##   curve we built the rest of the rebalance around.
##
## Why the amount <= 0.0 carve-out:
##   Earlier links in the damage pipeline can zero the hit BEFORE it
##   reaches armor — most importantly the Ash-Walker kenning's fire
##   immunity (which multiplies by 0.0) and any status multiplier that
##   could mathematically reach 0. Those are intentional immunities and
##   they shouldn't get silently undone by our 1-damage floor down here.
##   If amount is already 0 coming in, we pass it through untouched so
##   the immunity contract holds end-to-end.
func apply_to_damage(amount: float, info: Dictionary) -> float:
	if amount <= 0.0:
		return 0.0
	var elem: int = info.get("element", 0)
	var elem_mult: float = float(element_multipliers.get(elem, 1.0))
	var result: float = amount * damage_taken_multiplier * elem_mult - damage_reduction
	return maxf(result, 1.0)


static func format_stat_bullets(a: Armor) -> Array[String]:
	var bullets: Array[String] = []
	if a.damage_reduction > 0:
		bullets.append("%.0f flat damage reduction" % a.damage_reduction)
	if a.damage_taken_multiplier != 1.0:
		var pct: int = int((1.0 - a.damage_taken_multiplier) * 100)
		var prefix: String = "+" if pct > 0 else ""
		bullets.append("%s%d%% damage resistance" % [prefix, pct])
	if a.melee_damage_multiplier != 1.0:
		var pct: int = int((a.melee_damage_multiplier - 1.0) * 100)
		var prefix: String = "+" if pct > 0 else ""
		bullets.append("%s%d%% melee damage" % [prefix, pct])
	if a.ranged_damage_multiplier != 1.0:
		var pct: int = int((a.ranged_damage_multiplier - 1.0) * 100)
		var prefix: String = "+" if pct > 0 else ""
		bullets.append("%s%d%% ranged damage" % [prefix, pct])
	if a.move_speed_multiplier != 1.0:
		var pct: int = int((a.move_speed_multiplier - 1.0) * 100)
		var prefix: String = "+" if pct > 0 else ""
		bullets.append("%s%d%% move speed" % [prefix, pct])
	if a.max_health_bonus != 0:
		var prefix: String = "+" if a.max_health_bonus > 0 else ""
		bullets.append("%s%.0f max HP" % [prefix, a.max_health_bonus])
	if a.noise_weight > 0:
		bullets.append("%.0f noise while moving" % a.noise_weight)
	return bullets
