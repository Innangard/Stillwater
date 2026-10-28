class_name Weapon
extends Item
## Base class for all weapons (melee, ranged, magic).
## Extends Item so weapons live in the inventory like anything else.
## Subclasses override attack() to define what happens when fired.
##
## Two convenience setters keep things in sync automatically:
##   - Setting `weapon_name` mirrors into `item_name` so the inventory
##     displays the same name without each .tres needing to set both.
##   - Setting `element` updates `placeholder_color` to a thematic
##     color so inventory tiles auto-tint without authoring per item.
## In both cases, you can still set `item_name` or `placeholder_color`
## explicitly in a .tres if you want to override — just put them AFTER
## weapon_name / element in the file (Godot applies properties in order).

enum Element {
	PHYSICAL,
	FIRE,
	ICE,
	LIGHTNING,
	POISON,
	HOLY,
	DARK,
}

@export_group("Weapon")
@export var weapon_name: String = "Unnamed Weapon" :
	set(value):
		weapon_name = value
		# Keep the inventory display name in sync. If you set item_name
		# explicitly to override, set it after weapon_name in your .tres.
		item_name = value

@export_group("Combat")
@export var base_damage: float = 10.0
@export var element: Element = Element.PHYSICAL :
	set(value):
		element = value
		# Auto-tint inventory tile from element. Set placeholder_color
		# explicitly in your .tres if you want a non-elemental color.
		placeholder_color = element_color(value)
## Seconds between attacks. Lower = faster.
@export var cooldown: float = 0.4
## Optional status effects to attempt to apply on hit.
@export var on_hit_effects: Array[StatusApplication] = []

## Multiplier applied to the wielder's movement speed while this weapon
## is equipped in EITHER hand (primary or secondary). 1.0 = no effect.
##
## Composes multiplicatively with armor's move_speed_multiplier, kenning
## speed bonuses, status effects, and the sneak modifier. The aggregator
## in RunState.get_weapon_move_speed_multiplier() iterates over BOTH
## weapon slots so the bonus applies whenever the dagger is at your hip,
## not only while you're actively swinging it. This matches the contract
## that armor stats follow — you get the buff from carrying the piece,
## not from actively using it — and avoids speed rubber-banding when the
## player swaps between primary and secondary mid-fight.
##
## Conventional values: 1.05 (light), 1.10 (notable), 1.15 (the
## Galewalker's-Sandals tier — rare). Stacks multiplicatively, so two
## 1.10 sources give 1.21x. Values below 1.0 are valid for "heavy"
## weapons that slow you, but no shipped weapon uses that today.
@export var wielder_speed_multiplier: float = 1.0

## True if this weapon takes BOTH hands. A two-handed weapon may be
## equipped in EITHER the primary or secondary slot, but as long as it
## is in either slot, the OTHER slot must be empty. The equip code in
## RunState enforces this — attempting to equip into a slot while a
## two-handed weapon occupies the other slot will return false (the
## inventory click fails silently); attempting to equip a two-handed
## weapon while the other slot is non-empty will likewise fail.
##
## All ranged weapons are two-handed by convention (bows and crossbows
## need both hands to draw or crank). Heavy melee — greataxes, mauls,
## greatswords, long spears — is also two-handed; one-handed melee
## (daggers, falchions, swords, sabers) is not.
@export var two_handed: bool = false


func _init() -> void:
	# Weapons don't stack by default — each one gets its own inventory slot.
	if max_stack > 1:
		max_stack = 1
	# Default category — subclasses override in their own _init().
	if category == "misc":
		category = "weapon"


## Build the damage_info dict that travels through the damage pipeline.
## `weapon_category` lets downstream consumers (kill-count trackers,
## kennings, achievements) tell what KIND of weapon dealt the hit
## without needing to plumb the Weapon resource itself through hitbox/
## hurtbox boundaries. Inherits from the `category` field that all
## Weapon subclasses set in their _init() ("melee"/"ranged"/"spell").
func build_damage_info() -> Dictionary:
	return {
		"amount": base_damage,
		"element": element,
		"weapon_name": weapon_name,
		"weapon_category": category,
		"on_hit_effects": on_hit_effects,
	}


## Compute the actual damage this weapon should deal for a given user,
## composing the weapon's base with the user's outgoing-damage modifiers.
## Used by all attack() subclasses so the multiplier path is identical
## across melee, ranged, and magic. Enemies have no kenning bonuses (the
## KenningManager call gates on user being the Player), so this collapses
## to base_damage × status_buffs × difficulty for them.
##
## Order: base × status (from buffs like Berserker) × kenning (from
## equipped titles, weapon-type and element gated) × difficulty.
## Multiplicative so stacking two +25% sources gives +56.25%, not +50%
## — same convention StatusEffectComponent uses for its own composition.
##
## Difficulty applies ASYMMETRICALLY:
##   - Enemy users: damage scales with DifficultySettings.enemy_damage_mult.
##     (Easy = 0.7, Hard = 1.3) — this is the core "hard hits harder" lever.
##   - Player user: no difficulty scaling on outgoing damage. Player power
##     should feel identical across difficulties; the variable side is
##     ENEMY behavior. Scaling player damage too would compound with the
##     enemy-health change and make Easy trivial / Hard a damage race.
func compute_outgoing_damage(user: Node) -> float:
	var d: float = base_damage
	# Status-effect outgoing buffs (e.g. Berserker rune). The component
	# already exists on the player and several enemies; missing component
	# is a perfectly valid case (bare-bones entities).
	var status: Node = user.get_node_or_null("StatusEffectComponent")
	if status != null and status.has_method("get_damage_dealt_multiplier"):
		d *= status.get_damage_dealt_multiplier()
	# Kenning bonuses only ever apply to the player. The KenningManager
	# autoload is guaranteed to exist by the time any weapon fires.
	if user is Player:
		d *= KenningManager.get_damage_dealt_multiplier(self)
		# Rune damage bonuses: ALL_DAMAGE always applies, plus
		# MELEE_DAMAGE or PROJECTILE_DAMAGE gated on category.
		d *= RunState.get_rune_multiplier(RunestoneItem.RuneStat.ALL_DAMAGE)
		if category == "melee":
			d *= RunState.get_rune_multiplier(RunestoneItem.RuneStat.MELEE_DAMAGE)
			d *= RunState.get_armor_melee_damage_multiplier()
		elif category == "ranged":
			d *= RunState.get_rune_multiplier(RunestoneItem.RuneStat.PROJECTILE_DAMAGE)
			d *= RunState.get_armor_ranged_damage_multiplier()
	else:
		# Non-Player users are enemies (mooks + bosses + future critters);
		# the asymmetric difficulty lever rides on this branch.
		d *= DifficultySettings.get_enemy_damage_multiplier()
	return d


## Override in subclasses. Spawns whatever the weapon does into the world.
func attack(_user: Node2D, _aim: Vector2) -> void:
	push_warning("Weapon.attack() called on the base class — subclass should override.")


## Effective max distance at which this weapon can hit something. Enemy AI
## uses this to decide when it's in attack range. Subclasses should override
## with a more accurate calculation; the base returns a small default so
## abstract weapons don't make AI try to attack from across the map.
func effective_range() -> float:
	return 32.0


## Color associated with an element. Used by projectile visuals, hit fx, etc.
static func element_color(elem: int) -> Color:
	match elem:
		Element.PHYSICAL:  return Color(0.92, 0.92, 0.92)
		Element.FIRE:      return Color(1.00, 0.52, 0.12)
		Element.ICE:       return Color(0.55, 0.85, 1.00)
		Element.LIGHTNING: return Color(1.00, 0.95, 0.40)
		Element.POISON:    return Color(0.40, 0.90, 0.30)
		Element.HOLY:      return Color(1.00, 0.95, 0.70)
		Element.DARK:      return Color(0.45, 0.20, 0.65)
	return Color.WHITE
