class_name TelegraphedAreaWeapon
extends Weapon
## Spawns a Telegraph node when fired. The telegraph shows a warning
## ring on the ground for `warning_duration`, then deals AOE damage
## in `damage_radius`. Optional `linger_duration` keeps the AOE alive
## as a floor hazard after the initial pulse — for fire patches,
## acid pools, etc.
##
## Target picker decides WHERE the telegraph lands:
##   - AT_PLAYER: snap to player's current position at fire time.
##     Classic "where you ARE" attack — easy to dodge by simply
##     moving on the wind-up tell.
##   - AT_PREDICTED: take the player's current velocity, project
##     forward by `prediction_seconds` to guess where they'll be.
##     Punishes the player for moving in a straight line — they
##     have to break stride to dodge. Bullet-hell mainstay.
##   - AT_CASTER_OFFSET: spawn at a fixed offset from the firing
##     enemy. Used for "ground-slam in front of me" attacks.
##
## Lean by design (the user explicitly asked for this) — fields above
## are the minimum set required to author the six new Act 2 ranged
## enemies. Specific extensions to consider only when a new enemy
## actually needs them: multi-tick damage during linger, damage that
## scales with distance from center, multi-shot bursts of telegraphs.

enum TargetPicker {
	AT_PLAYER,
	AT_PREDICTED,
	AT_CASTER_OFFSET,
}

@export_group("Telegraph")
## Scene to spawn. Default points at our shipped telegraph.tscn —
## override only if you need a custom-shaped warning visual.
@export var telegraph_scene: PackedScene = preload("res://weapons/telegraph.tscn")

## Seconds the warning displays before damage fires. Tuning guidance:
##   0.4 = nearly unreactable — only for low-radius pings
##   0.7-0.9 = standard "you can dodge if you're paying attention"
##   1.2+   = generous, suitable for very large AOEs
@export var warning_duration: float = 0.8

## Radius of both the visual warning AND the damage zone.
@export var damage_radius: float = 64.0

## How long the damaging AOE persists after the initial pulse, as a
## walk-into floor hazard. 0 = single pulse, vanishes. Positive =
## leaves a hazard for that many seconds. Fire patches use this.
@export var linger_duration: float = 0.0

@export var target_picker: TargetPicker = TargetPicker.AT_PLAYER

## Used only when target_picker == AT_PREDICTED. The player's current
## velocity is projected forward by this many seconds to pick the
## landing site. Higher = more aggressive lead, easier to fake out
## by suddenly stopping; lower = more conservative, closer to
## AT_PLAYER.
@export var prediction_seconds: float = 0.45

## Used only when target_picker == AT_CASTER_OFFSET. Telegraph lands
## at caster.position + this offset, rotated by caster's facing.
## Defaults to a forward-of-caster spot suitable for "ground slam
## in front of me" attacks. The AIM vector passed to attack() rotates
## this offset, so the enemy hitting from any angle lands the AOE
## in the player's general direction.
@export var caster_offset: Vector2 = Vector2(60, 0)

## Maximum distance from the firing enemy at which it should attempt
## this attack. Used by enemy AI to know "I'm close enough to stomp"
## or "I'm close enough to lob a rock." Per-instance because the
## right value depends entirely on the weapon's role — a heavy ground
## slam should fire only at melee distance (60), a long-range rock
## lob fires from much further (260). Default (200) is a middle
## ground that suits Cinder-Wraith-style floating attackers.
@export var max_engage_range: float = 200.0


# ============================================================================

func _init() -> void:
	# Mirror RangedWeapon's _init category-tag. Used by armor damage
	# multipliers — for now, telegraphed AOE doesn't count as either
	# melee or ranged for armor bonus purposes (the player isn't
	# expected to use these), so we leave it as "spell" which armor
	# damage modifiers already don't buff. If a future player kenning
	# spawns telegraphed AOEs, this is the field to revisit.
	category = "spell"


func attack(user: Node2D, aim: Vector2) -> void:
	if telegraph_scene == null:
		push_error("TelegraphedAreaWeapon '%s' has no telegraph_scene." % weapon_name)
		return

	# Resolve the landing position based on target_picker. We do this
	# at fire time so the player's position right when the wind-up
	# completes is what gets sampled — not what they were doing when
	# wind-up started. This is the standard expectation for telegraph
	# attacks; players read the wind-up frame, then have warning_duration
	# to evacuate.
	var landing: Vector2 = _resolve_landing(user, aim)

	# Build the damage info dict via the base class. Includes element,
	# on_hit_effects, weapon_name — everything HitboxComponent needs.
	var info: Dictionary = build_damage_info()
	var effective_damage: float = compute_outgoing_damage(user)
	info["amount"] = effective_damage

	# Instance and configure the telegraph node.
	var tel: Telegraph = telegraph_scene.instantiate() as Telegraph
	tel.damage = effective_damage
	tel.damage_info = info
	tel.owning_team = user.team if "team" in user else "neutral"
	tel.warning_duration = warning_duration
	tel.damage_radius = damage_radius
	tel.linger_duration = linger_duration
	tel.warning_color = Weapon.element_color(element)
	tel.global_position = landing

	# Add to the world root, not the firing enemy — telegraphs should
	# stay put if the enemy moves or dies during the wind-up. Following
	# the projectile precedent: get the current scene as the parent.
	# get_tree().current_scene is the region root for all gameplay
	# scenes, which is where projectiles spawn too.
	user.get_tree().current_scene.add_child(tel)


func _resolve_landing(user: Node2D, aim: Vector2) -> Vector2:
	# Find the player. user IS the player for player-spawned telegraphs;
	# for enemy-spawned ones, we look up by group. We need the player
	# reference even for AT_CASTER_OFFSET if the future wants
	# offset-relative-to-player attacks, but for now offset is purely
	# relative to caster.
	match target_picker:
		TargetPicker.AT_PLAYER:
			var p: Node = user.get_tree().get_first_node_in_group("player")
			if p is Node2D:
				return (p as Node2D).global_position
			# Fallback: enemy's own position. Shouldn't happen — no
			# player in scene is a degenerate case — but better to
			# spawn the telegraph on the caster than crash.
			return user.global_position
		TargetPicker.AT_PREDICTED:
			var p: Node = user.get_tree().get_first_node_in_group("player")
			if not (p is Node2D):
				return user.global_position
			var p2 := p as Node2D
			# Predict by velocity. CharacterBody2D exposes .velocity;
			# fall back to zero if the player's body type doesn't.
			var v: Vector2 = Vector2.ZERO
			if "velocity" in p2:
				v = p2.velocity
			return p2.global_position + v * prediction_seconds
		TargetPicker.AT_CASTER_OFFSET:
			# Rotate the static offset by the aim direction so the
			# attack lands "in front of where I'm pointing." Using
			# aim.angle() for the rotation keeps the offset's local
			# X-axis facing the player.
			var rot: float = aim.angle()
			var rotated_offset: Vector2 = caster_offset.rotated(rot)
			return user.global_position + rotated_offset
	# Unreachable; satisfy GDScript's strict return analysis.
	return user.global_position


func effective_range() -> float:
	# AI consults this to know when it's close enough to fire. We just
	# return the authoring-time value; each weapon instance picks the
	# range that fits its role (60 for a ground stomp, 260 for a rock
	# lob, etc.).
	return max_engage_range
