class_name HurtboxComponent
extends Area2D
## Detects incoming HitboxComponents and emits a signal with the damage info.
## Hook this signal up to your HealthComponent in the parent entity.
##
## Why a signal instead of calling HealthComponent directly?
## So the entity in between can intercept: apply armor, dodge chance,
## damage-type resistances, on-hit effects, etc. before HP is touched.

signal hit_received(amount: float, info: Dictionary, source: HitboxComponent)

@export var team: String = "neutral" # "player", "enemy", "neutral"


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	if not area is HitboxComponent:
		return
	var hitbox: HitboxComponent = area
	# Don't friendly-fire. Neutral hits everything.
	if hitbox.owning_team != "neutral" and hitbox.owning_team == team:
		return
	hit_received.emit(hitbox.damage, hitbox.damage_info, hitbox)
