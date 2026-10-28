class_name ExpandingRingWeapon
extends Weapon
## Weapon wrapper that spawns an ExpandingRing on attack — a radial
## wave-front expanding from the user, hitting each target once as it
## passes. See expanding_ring.gd for the front mechanics. Built for the
## Drowned Crone's wave pulse; reusable for any shockwave attack.
##
## The ring is parented to the ARENA (user's parent), not the user —
## a wave detaches from its source: if the caster moves after stomping,
## the ripple keeps expanding from where the stomp landed. This is the
## opposite choice from PersistentHitboxWeapon (whose cone follows the
## caster like a flamethrower) and it's deliberate.

const RING_SCENE: PackedScene = preload("res://weapons/expanding_ring.tscn")

@export_group("Ring")
## Radius the wave-front starts at. Set just outside the caster's body
## so the ring visibly emerges from them rather than materializing.
@export var start_radius: float = 30.0
## Radius the front dissipates at — the wave's total reach.
@export var end_radius: float = 240.0
## Seconds from start_radius to end_radius. Lower = faster front =
## harder to outrun. At (240-30)/1.1 ≈ 190 px/s the front is a little
## faster than a slowed player and slower than a dash — which is the
## point: the dash is the answer.
@export var expand_duration: float = 1.1
## Half-width of the hit band around the front line.
@export var band_half_width: float = 14.0
## Knockback applied radially OUTWARD from ring center on hit.
@export var knockback: float = 150.0
## Visual color of the ring.
@export var ring_color: Color = Color(0.45, 0.70, 0.85, 0.65)


func _init() -> void:
	super()
	if category == "weapon":
		category = "persistent"


## AI range hint: the ring reaches end_radius eventually, but treating
## the full reach as "attack range" would have casters stomping from
## across the arena where the ring takes a full second to arrive and
## everyone just walks away from it. Two-thirds reach keeps the cast
## inside the band where the front arrives fast enough to threaten.
func effective_range() -> float:
	return end_radius * 0.66


func attack(user: Node2D, _aim: Vector2) -> void:
	var ring: ExpandingRing = RING_SCENE.instantiate()
	ring.start_radius = start_radius
	ring.end_radius = end_radius
	ring.expand_duration = expand_duration
	ring.band_half_width = band_half_width
	ring.damage = compute_outgoing_damage(user)
	ring.element = int(element)
	ring.knockback = knockback
	ring.on_hit_effects = on_hit_effects
	ring.ring_color = ring_color
	ring.weapon_name = weapon_name
	ring.weapon_category = category
	ring.owning_team = user.team if "team" in user else "neutral"
	# Parent to the arena and pin to the cast point — the wave detaches
	# from the caster (see class docstring).
	var parent: Node = user.get_parent()
	parent.add_child(ring)
	ring.global_position = user.global_position
