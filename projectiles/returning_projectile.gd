class_name ReturningProjectile
extends Projectile
## A projectile that travels outward, pauses briefly, then returns to
## the entity that threw it. Used by the Apprentice's hammer throw
## and any future boomerang-style attacks.
##
## Lifecycle: OUTGOING -> PAUSE -> RETURN -> queue_free
##
## The return path re-enables the hitbox so the projectile can damage
## on the way back. Pierce resets for the return leg so the same
## enemy can be hit twice (once each way) -- this is intentional:
## positioning between the boss and the hammer's arc is a skill test.

enum Phase { OUTGOING, PAUSE, RETURN }

@export var pause_duration: float = 0.18
@export var return_speed_mult: float = 1.3

var _phase: Phase = Phase.OUTGOING
var _pause_timer: float = 0.0
var _owner_ref: WeakRef = WeakRef.new()
var _outgoing_distance: float = 0.0
var _max_distance: float = 0.0

## Called by the weapon after instantiation to set who threw it.
func set_owner(owner: Node2D) -> void:
	_owner_ref = weakref(owner)


func _ready() -> void:
	super()
	_max_distance = speed * lifetime
	_phase = Phase.OUTGOING


func _physics_process(delta: float) -> void:
	match _phase:
		Phase.OUTGOING:
			position += direction * speed * delta
			_outgoing_distance += speed * delta
			lifetime -= delta
			if lifetime <= 0.0:
				_begin_pause()

		Phase.PAUSE:
			_pause_timer -= delta
			if _pause_timer <= 0.0:
				_begin_return()

		Phase.RETURN:
			var owner: Node2D = _owner_ref.get_ref() as Node2D
			if owner == null or not is_instance_valid(owner):
				queue_free()
				return
			var to_owner: Vector2 = (owner.global_position - global_position)
			var dist: float = to_owner.length()
			if dist < 20.0:
				queue_free()
				return
			direction = to_owner.normalized()
			rotation = direction.angle()
			var ret_speed: float = speed * return_speed_mult
			position += direction * ret_speed * delta


func _begin_pause() -> void:
	_phase = Phase.PAUSE
	_pause_timer = pause_duration
	# Disable hitbox during pause
	if hitbox:
		hitbox.collision_layer = 0


func _begin_return() -> void:
	_phase = Phase.RETURN
	# Re-enable hitbox for return leg, reset pierce
	_hits = 0
	if hitbox:
		match owning_team:
			"player": hitbox.collision_layer = 16
			"enemy":  hitbox.collision_layer = 64
			_:        hitbox.collision_layer = 16 | 64


## Override wall collision: returning projectiles pass through walls
## on the way back (they're magically returning to the thrower).
func _on_body_entered(_body: Node) -> void:
	if _phase == Phase.OUTGOING:
		_begin_pause()
	# During RETURN, ignore walls


## Override area collision for return leg hit tracking.
func _on_area_entered(area: Area2D) -> void:
	if area is HurtboxComponent:
		var hb: HurtboxComponent = area
		if hb.team == owning_team and owning_team != "neutral":
			return
		_hits += 1
		if _hits > pierce and _phase == Phase.OUTGOING:
			_begin_pause()
