class_name HealthComponent
extends Node
## Reusable HP container. Drop one on any entity that can take damage.
## Doesn't know about hitboxes/hurtboxes - those signal in via take_damage().

@export var max_health: float = 100.0
@export var invulnerable: bool = false

var current_health: float

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, info: Dictionary)
signal healed(amount: float)
signal died


func _ready() -> void:
	current_health = max_health


func take_damage(amount: float, info: Dictionary = {}) -> void:
	if invulnerable or is_dead() or amount <= 0.0:
		return
	current_health = max(0.0, current_health - amount)
	damaged.emit(amount, info)
	health_changed.emit(current_health, max_health)
	if current_health == 0.0:
		died.emit()


func heal(amount: float) -> void:
	if is_dead() or amount <= 0.0:
		return
	current_health = min(max_health, current_health + amount)
	healed.emit(amount)
	health_changed.emit(current_health, max_health)


func set_max_health(new_max: float, heal_to_full: bool = false) -> void:
	max_health = max(1.0, new_max)
	if heal_to_full:
		current_health = max_health
	else:
		current_health = min(current_health, max_health)
	health_changed.emit(current_health, max_health)


func is_dead() -> bool:
	return current_health <= 0.0


func health_percent() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0
