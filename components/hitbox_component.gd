class_name HitboxComponent
extends Area2D
## Deals damage to overlapping HurtboxComponents.
## The hurtbox is the one that detects overlap, so this is mostly a data carrier.
##
## damage_info is a free-form dictionary so weapons/spells can attach
## arbitrary metadata: element type, status effects, knockback, crit, etc.
## Examples:
##   {"element": "fire", "burn_chance": 0.3}
##   {"element": "physical", "knockback": 250.0, "crit": true}

@export var damage: float = 10.0
@export var damage_info: Dictionary = {}
@export var owning_team: String = "neutral" # "player", "enemy", "neutral"


func _ready() -> void:
	# Hitboxes don't need to monitor — they're monitored by hurtboxes.
	monitoring = false
