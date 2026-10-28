class_name DummyEnemy
extends CharacterBody2D
## Test enemy with sense-based aggression.
##
## States:
##   IDLE   — drifts. Doesn't chase. Periodically polls "should I notice?"
##            using the player's effective signature (noise + smell + distance).
##   ALERT  — has noticed something. Chases the player. Doesn't return to idle
##            (the dead are persistent once roused). Future enemies could have
##            an alert-decay if you want forgetting behavior.
##
## Detection model:
##   effective_range = base_range * (1 + noise_factor * noise_sensitivity
##                                       + smell_factor * smell_sensitivity)
## If distance to player <= effective_range, the enemy engages.

enum AIState { IDLE, ALERT }

@export var max_speed: float = 110.0
@export var acceleration: float = 800.0

@export_group("Senses")
## Range at which a perfectly silent, scentless player is detected.
## Most enemies should keep this small — you want signature to matter.
@export var base_detection: float = 80.0
## How much player noise expands detection. 1.0 = doubles range at full noise.
@export var noise_sensitivity: float = 5.0
## How much player smell expands detection.
@export var smell_sensitivity: float = 4.0
## Once alerted, chases at this much further before disengaging — currently
## unused (enemies don't disengage). Reserved for future "memory" tuning.
@export var alert_pursue_range: float = 800.0

@export_group("Drops")
@export var currency_drop_min: int = 3
@export var currency_drop_max: int = 8
@export var item_drops: Array[Item] = []
@export_range(0.0, 1.0) var item_drop_chance: float = 0.35

const _PICKUP_SCENE: PackedScene = preload("res://pickups/pickup.tscn")
const _DEFAULT_DROP_PATHS: Array = [
	"res://items/instances/pale_ash.tres",
	"res://items/instances/bog_bile.tres",
	"res://items/instances/frost_filament.tres",
	"res://items/instances/wraithseed.tres",
	"res://items/instances/soul_phial.tres",
]

var team: String = "enemy"

@onready var health_component: HealthComponent = $HealthComponent
@onready var hurtbox: HurtboxComponent = $HurtboxComponent
@onready var status_component: StatusEffectComponent = $StatusEffectComponent

var _player: Node2D = null
var _ai_state: AIState = AIState.IDLE
## Detection check interval — poll instead of every frame.
const _DETECT_INTERVAL: float = 0.25
var _detect_timer: float = 0.0
## Cached info from the most recent incoming hit, for enemy_killed
## kill-attribution. Mirrors Enemy._last_hit_info.
var _last_hit_info: Dictionary = {}


func _ready() -> void:
	add_to_group("enemies")
	# Stagger initial detection ticks so a swarm doesn't all fire the same frame.
	_detect_timer = randf() * _DETECT_INTERVAL

	health_component.died.connect(_on_died)
	hurtbox.hit_received.connect(_on_hit_received)
	status_component.tick_damage.connect(_on_status_tick_damage)

	EventBus.player_spawned.connect(_on_player_spawned)
	call_deferred("_find_player")


func _find_player() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")


func _on_player_spawned(player: Node) -> void:
	_player = player


func _physics_process(delta: float) -> void:
	if status_component.is_action_prevented():
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		move_and_slide()
		queue_redraw()
		return

	if not is_instance_valid(_player):
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		move_and_slide()
		queue_redraw()
		return

	# Detection poll — every _DETECT_INTERVAL, ask whether the player's
	# current signature plus distance should put us into ALERT.
	if _ai_state == AIState.IDLE:
		_detect_timer -= delta
		if _detect_timer <= 0.0:
			_detect_timer = _DETECT_INTERVAL
			_check_detection()

	match _ai_state:
		AIState.IDLE:
			# Idle drift toward zero velocity. Future: wander pattern.
			velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		AIState.ALERT:
			_chase(delta)

	move_and_slide()
	queue_redraw()


func _check_detection() -> void:
	var p: Player = _player as Player
	if p == null:
		return

	var dist: float = global_position.distance_to(p.global_position)
	var noise_f: float = p.noise_factor()
	var smell_f: float = p.smell_factor()
	var range: float = base_detection * (1.0 \
		+ noise_f * noise_sensitivity \
		+ smell_f * smell_sensitivity)

	if dist <= range:
		_ai_state = AIState.ALERT


func _chase(delta: float) -> void:
	var to_player: Vector2 = _player.global_position - global_position
	var dist := to_player.length()

	var effective_speed := max_speed * status_component.get_speed_multiplier()

	if dist > 1.0:
		var dir := to_player / dist
		velocity = velocity.move_toward(dir * effective_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)


func _on_hit_received(amount: float, info: Dictionary, source: HitboxComponent) -> void:
	amount *= status_component.get_damage_taken_multiplier()
	health_component.take_damage(amount, info)
	EventBus.damage_dealt_visual.emit(self, amount, info)
	# Stash for enemy_killed in _on_died — see Enemy._on_hit_received
	# for the design rationale. Dummies count toward kill-tracker
	# kennings (Spear-Dane / Arrow-Crow) too: they're enemies, they
	# die, the player practiced their weapon on them.
	_last_hit_info = info

	# Being hit is the most decisive detection signal — wake up if asleep.
	_ai_state = AIState.ALERT

	if info.has("on_hit_effects"):
		status_component.try_apply_each(info["on_hit_effects"], source)

	if info.has("knockback") and is_instance_valid(source):
		var dir := (global_position - source.global_position).normalized()
		velocity = dir * float(info["knockback"])


func _on_status_tick_damage(amount: float, info: Dictionary) -> void:
	health_component.take_damage(amount, info)
	EventBus.damage_dealt_visual.emit(self, amount, info)


func _on_died() -> void:
	EventBus.entity_died.emit(self)
	EventBus.enemy_killed.emit(self, _last_hit_info)
	_spawn_drops()
	queue_free()


func _spawn_drops() -> void:
	var currency := randi_range(currency_drop_min, currency_drop_max)
	if currency > 0:
		var p: Pickup = _PICKUP_SCENE.instantiate()
		p.currency_amount = currency
		get_parent().add_child(p)
		p.global_position = global_position

	if randf() < item_drop_chance:
		var pool: Array = item_drops if not item_drops.is_empty() else _load_default_drops()
		if not pool.is_empty():
			var p: Pickup = _PICKUP_SCENE.instantiate()
			p.item = pool.pick_random()
			get_parent().add_child(p)
			p.global_position = global_position + Vector2(randf_range(-16, 16), randf_range(-16, 16))


func _load_default_drops() -> Array:
	var pool: Array = []
	for path in _DEFAULT_DROP_PATHS:
		var it: Resource = load(path)
		if it:
			pool.append(it)
	return pool


# --- Placeholder visual: red circle, status-tinted, with HP bar ---
func _draw() -> void:
	var body: Color = Color(0.8, 0.2, 0.2)
	# Idle enemies render dimmer to signal "not yet aggressive."
	if _ai_state == AIState.IDLE:
		body = body.lerp(Color(0.3, 0.3, 0.3), 0.55)
	var tint: Color = status_component.get_tint()
	if tint.a > 0.0:
		body = body.lerp(Color(tint.r, tint.g, tint.b, 1.0), tint.a)
	draw_circle(Vector2.ZERO, 14.0, body)

	# HP bar
	var hp_pct: float = health_component.health_percent() if health_component else 1.0
	var bar_w := 24.0
	draw_rect(Rect2(Vector2(-bar_w * 0.5, -22), Vector2(bar_w, 3)), Color(0.2, 0.0, 0.0))
	draw_rect(Rect2(Vector2(-bar_w * 0.5, -22), Vector2(bar_w * hp_pct, 3)), Color(1.0, 0.3, 0.3))

	# Tiny eye-glint when alert, to read at a glance
	if _ai_state == AIState.ALERT:
		draw_circle(Vector2(0, -3), 2.0, Color(1, 0.95, 0.5))
