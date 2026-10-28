class_name ActiveEffect
extends RefCounted
## Runtime instance of a status effect on a specific entity. Created
## and managed by StatusEffectComponent — you usually don't make these
## yourself, you call status_component.apply(some_effect).

var effect: StatusEffect
var time_remaining: float
var stacks: int = 1
var time_to_next_tick: float
## Who applied this effect. Optional, for things like "deal extra damage
## to targets you've burned" or for kill attribution.
var source: Node = null


func _init(_effect: StatusEffect = null, _source: Node = null) -> void:
	effect = _effect
	source = _source
	if effect:
		time_remaining = effect.duration
		time_to_next_tick = effect.tick_interval
