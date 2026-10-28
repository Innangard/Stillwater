class_name ShieldWeapon
extends Weapon
## A defensive weapon. Unlike MeleeWeapon / RangedWeapon / MagicSpell —
## which all use the "press → fire → cooldown" model — the shield is
## hold-to-raise: while the player holds the bound action (LMB if in
## the primary slot, RMB if in the secondary slot), a block zone
## exists in front of them. While the zone is active:
##
##   - the player's movement speed is multiplied by movement_speed_multiplier
##   - the other hand's weapon cannot be used
##   - enemy melee hitboxes overlapping the zone take melee_damage_reduction
##     applied to damage that reaches the player
##   - enemy projectiles entering the zone are destroyed outright
##
## The shield itself deals no damage (base_damage = 0). It's a
## defensive option, not an attack option.
##
## Because the shield doesn't fit the attack(user, aim) hook the way
## other Weapon subclasses do, the player special-cases ShieldWeapon
## in its input handler (_update_shield_state) rather than calling
## attack() on it. attack() is implemented here as a safe no-op
## (with a warning if it does get called, which shouldn't happen).
##
## Per-instance tuning happens via the four exports below: rectangle
## size, distance from the player's body, slowdown factor, damage
## reduction multiplier. Heavier shields would use a larger rect, a
## stronger slowdown, and stronger reduction.

@export_group("Shield")
## Dimensions of the block rectangle.
##   x = thickness in the aim direction (small — the shield is shallow)
##   y = breadth perpendicular to aim (larger — the shield is wide)
## A 40×80 rectangle means a 40px-deep, 80px-tall shield held in front
## of the player.
@export var block_arc_size: Vector2 = Vector2(40, 80)

## Distance from the player's center to the shield rectangle's center,
## along the aim direction. With a 30px distance and a 40px-thick
## shield, the near edge of the shield is at 10px and the far edge is
## at 50px from the player.
@export var block_distance: float = 30.0

## Movement-speed multiplier applied while blocking. Composes
## multiplicatively with status / kenning / armor speed multipliers
## in the player's speed pipeline. 0.5 = half speed, the user's stated
## design target.
@export var movement_speed_multiplier: float = 0.5

## Multiplier applied to incoming melee damage when the source hitbox
## was overlapping the shield zone at the moment of the hit. 0.25
## means "you take 25% of the damage you would have" — a 75% damage
## reduction, the user's stated target. Set to 0.0 for a full-block
## shield, 0.5 for a lighter shield, etc.
##
## Only applies to non-projectile damage sources — projectiles in
## the zone are destroyed outright (not reduced), per the spec.
@export var melee_damage_reduction: float = 0.25

## The scene spawned as a child of the player when the shield raises.
## Default points at the stock shield_zone.tscn — override only if a
## specific shield needs a different visual (a glowing magic ward,
## a flaming barrier, etc.).
@export var shield_zone_scene: PackedScene = preload("res://weapons/shield_zone.tscn")

@export_group("Special Effects")
## Per-element multipliers applied to incoming damage when the source
## hitbox is in the shield zone — same convention as Armor's
## element_multipliers field. Keyed by Weapon.Element (int). Composes
## multiplicatively with melee_damage_reduction:
##
##     effective_reduction = melee_damage_reduction
##                         * element_multipliers.get(info.element, 1.0)
##
## A "Frost-Banded Round" with melee_damage_reduction = 0.20 and
## element_multipliers = {1: 0.5} (Element.FIRE) takes 10% of fire
## damage but 20% of everything else — the cold rings turn back flame
## but only flame.
##
## The 0.10 reduction floor (enforced in the player's _on_hit_received)
## still applies — effective reduction never goes below 0.10 no matter
## what the element multiplier says. This means very low base reductions
## can't be "boosted past the cap" by element multipliers; the multiplier
## is most useful on mid-tier shields whose base reduction has headroom
## above the floor.
@export var element_multipliers: Dictionary = {}

## Max-HP bonus granted while this shield is equipped, even when not
## raised. Same convention as Armor's max_health_bonus — a passive
## carrying benefit. The mail-backed late-game shields (Moor-Mail
## Bulwark, Hoarfrost Aegis) use this; lighter shields leave it at 0.
##
## Plumbed through RunState.get_shield_max_health_bonus, summed into
## the same max-HP composition KenningManager uses for armor and
## kenning bonuses. Recomputed on weapon_equipped (KenningManager
## listens for the signal).
@export var max_health_bonus: float = 0.0


# ============================================================================

func _init() -> void:
	# Mirror the convention used by other weapon subclasses for the
	# category tag. Armor damage-mults filter by category — shields
	# shouldn't pick up melee or ranged damage bonuses since they
	# deal no damage and aren't an attack type.
	category = "shield"


## Override of the base Weapon.attack hook. Shields don't fire on
## press — the player's input handler intercepts and routes to the
## shield-state update path instead. If this is ever called, something
## upstream went wrong: warn loudly so the bug surfaces in development.
func attack(_user: Node2D, _aim: Vector2) -> void:
	push_warning("ShieldWeapon.attack() was called — the player should " +
		"special-case shields and route through _update_shield_state " +
		"instead. Check input dispatch in player.gd.")


## AI never tries to use a shield (no enemy currently equips one), but
## return 0 so any code path that consults effective_range as a
## "can I attack from here" check gets a clear "no, not from any
## range" answer.
func effective_range() -> float:
	return 0.0
