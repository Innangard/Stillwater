class_name Telegraph
extends Area2D
## A floor-warning attack node. Spawned by TelegraphedAreaWeapon.
##
## Lifecycle: shows a colored ring on the ground for `warning_duration`
## seconds (drawn via _draw, so no texture authoring needed), THEN
## delivers damage to whatever's inside `damage_radius` in a single
## pulse. After the pulse, the node persists for `linger_duration`
## seconds — set to 0 for a one-shot explosion, or a positive value
## for floor hazards like fire patches that keep hurting things
## that walk into them (Cinder-Wraith use case).
##
## Why an Area2D + custom draw rather than a Sprite + AnimationPlayer?
##   - The visual is purely procedural (color/radius/fill ratio), which
##     is exactly what _draw is for. No art assets to author.
##   - The damage delivery is via HitboxComponent so it routes through
##     the existing hitbox/hurtbox layer system every other attack uses.
##   - Total state is small enough (timer + radius + color) that the
##     overhead of a full AnimationPlayer would dwarf the benefit.
##
## Damage routing matches Projectile: HitboxComponent sits on this node,
## owning_team determines collision_layer (16 = player-source,
## 64 = enemy-source). Hit detection happens during the BRIEF pulse
## frame; after that, if linger_duration > 0, the hitbox stays active
## and any hurtbox that enters during linger gets re-hit (same
## "step on the fire patch and burn again" behavior as a real hazard).

@export var damage: float = 10.0
@export var damage_info: Dictionary = {}
@export var owning_team: String = "neutral"

## Time spent showing the warning before damage fires. The danger ring
## fills toward solid as this counts down, giving the player a clear
## "I have N seconds to get out of this circle" signal.
@export var warning_duration: float = 0.8

## Radius in pixels of both the warning visual AND the damage zone —
## what you see is what hurts you, with no offset.
@export var damage_radius: float = 64.0

## Color the warning is tinted. Set by the spawning weapon based on
## element. Defaults to a neutral orange that reads as "danger" without
## committing to an element.
@export var warning_color: Color = Color(0.95, 0.45, 0.18, 1.0)

## How long the AOE persists AFTER the initial pulse. 0 = vanish on
## pulse (the common case — single explosion). Positive = leave a
## damaging floor patch for this many seconds (fire patches, slick
## puddles, etc.). During linger the hitbox stays active so anything
## entering it gets hit again at its own apply-cooldown.
@export var linger_duration: float = 0.0

## Visual scale during linger. Patches that persist should look
## different from the warning — typically a more solid, slightly
## dimmer rendering — so the player can read "the warning is over,
## but the floor is still hot." 1.0 = same color as warning,
## < 1.0 = dimmed for the linger phase.
@export var linger_brightness: float = 0.75


# ============================================================================

@onready var hitbox: HitboxComponent = $HitboxComponent
@onready var collision: CollisionShape2D = $HitboxComponent/CollisionShape2D

# State machine: WARNING → PULSE → LINGER → done. We use an enum-of-states
# because the visual draw and the hitbox-active-flag both depend on which
# phase we're in.
enum Phase { WARNING, LINGER }
var _phase: Phase = Phase.WARNING
var _time_in_phase: float = 0.0


func _ready() -> void:
	# Difficulty: same convention as Projectile. Enemy telegraphs get
	# their warning shortened on Hard (less reaction time) and lengthened
	# on Easy. Player-spawned telegraphs (if they ever exist — future
	# kenning or spell idea) aren't scaled. The multiplier is reused
	# from projectile_speed because the underlying intent — "enemy
	# attacks come at you faster on Hard" — is the same.
	if owning_team == "enemy":
		# Inverse: a higher "speed multiplier" should mean SHORTER warning.
		# Clamp to avoid divide-by-zero on a misconfigured difficulty.
		var speed_mult: float = max(0.1,
			DifficultySettings.get_projectile_speed_multiplier())
		warning_duration /= speed_mult

	# Set the hitbox's parameters. damage_info already carries element /
	# on_hit_effects from the spawning weapon — no need to recompute.
	hitbox.damage = damage
	hitbox.damage_info = damage_info
	hitbox.owning_team = owning_team
	match owning_team:
		"player": hitbox.collision_layer = 16
		"enemy":  hitbox.collision_layer = 64
		_:        hitbox.collision_layer = 16 | 64

	# Apply the radius to the CollisionShape2D. We deferred this so
	# weapons that scale radius (none yet, but possible) can do so
	# before _ready by setting damage_radius after instantiating.
	var shape := CircleShape2D.new()
	shape.radius = damage_radius
	collision.shape = shape

	# Hitbox is INACTIVE during warning — disable the collision shape
	# so it doesn't exist in the physics space yet. We keep monitorable
	# true so that when the shape is re-enabled in _enter_linger(), the
	# physics server treats it as a NEW shape entering the space and
	# fires area_entered on any overlapping hurtbox. The old approach
	# (toggling monitoring/monitorable) silently failed: Godot 4 does
	# not fire area_entered when monitorable flips from false→true for
	# already-overlapping areas, so players standing on the warning
	# took zero damage.
	collision.disabled = true


func _process(delta: float) -> void:
	_time_in_phase += delta
	match _phase:
		Phase.WARNING:
			# Trigger the redraw every frame so the warning ring's fill
			# ratio animates smoothly. queue_redraw is cheap.
			queue_redraw()
			if _time_in_phase >= warning_duration:
				_enter_linger()
		Phase.LINGER:
			# The hitbox is on during linger; nothing to do in the
			# update loop except wait for the linger to elapse.
			if _time_in_phase >= linger_duration:
				queue_free()


func _enter_linger() -> void:
	_phase = Phase.LINGER
	_time_in_phase = 0.0
	# Re-enable the collision shape. The physics server treats this as
	# a shape entering the space for the first time, so any hurtbox
	# already overlapping receives an area_entered signal on the next
	# physics step — exactly what we want for "you were standing in the
	# circle when it detonated."
	collision.disabled = false
	# If linger_duration is zero, free immediately after one frame of
	# active hitbox. We can't queue_free this same frame or the hitbox
	# never gets a chance to fire its area_entered signal — Godot needs
	# one physics step with the shape active. Schedule via a one-shot
	# timer at the end of the current frame.
	if linger_duration <= 0.0:
		_die_after_one_frame.call_deferred()
	queue_redraw()


func _die_after_one_frame() -> void:
	# Wait one physics frame, then free. Implements the "single pulse,
	# done" mode without needing a Timer child node.
	await get_tree().physics_frame
	queue_free()


func _draw() -> void:
	match _phase:
		Phase.WARNING:
			# Fill ratio = time elapsed / warning duration. Renders as
			# an outer ring that fills inward toward a solid danger
			# circle — the standard "incoming AOE" affordance from
			# every action game with floor warnings.
			var fill_ratio: float = clamp(_time_in_phase / warning_duration, 0.0, 1.0)
			var outline := warning_color
			var fill := warning_color
			fill.a *= 0.25 + 0.45 * fill_ratio   # ramp opacity up
			# Inner filled circle that grows.
			draw_circle(Vector2.ZERO, damage_radius * fill_ratio, fill)
			# Outline ring — always full radius, gives the player the
			# unambiguous danger boundary even when fill is small.
			draw_arc(Vector2.ZERO, damage_radius, 0.0, TAU, 48,
				outline, 2.5, true)
		Phase.LINGER:
			# Solid hazard patch. Dimmer than the warning peak — the
			# brightness contrast tells the player "this is the
			# settled aftermath, not the incoming threat."
			var patch_color := warning_color
			patch_color.a = linger_brightness * 0.55
			draw_circle(Vector2.ZERO, damage_radius, patch_color)
			draw_arc(Vector2.ZERO, damage_radius, 0.0, TAU, 48,
				warning_color, 1.5, true)
