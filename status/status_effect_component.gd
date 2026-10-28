class_name StatusEffectComponent
extends Node
## Drop one of these on any entity that can receive status effects.
## Tracks active effects, ticks them, exposes aggregate stat modifiers.
##
## Decoupling note: this component does NOT touch HealthComponent directly.
## When an effect ticks damage, we emit `tick_damage` and the parent entity
## routes that through its own intercept layer (resistances, etc.) before
## calling HealthComponent.take_damage. Keeps the component generic.

signal effect_applied(effect: StatusEffect, stacks: int)
signal effect_removed(effect: StatusEffect)
signal effect_ticked(effect: StatusEffect, stacks: int)
## Emitted when an effect's tick wants to deal damage. Connect to your
## entity's damage intercept (usually the same path as _on_hit_received).
signal tick_damage(amount: float, info: Dictionary)
signal tick_heal(amount: float, info: Dictionary)

# effect_id (StringName) -> ActiveEffect
var _active: Dictionary = {}


# ---------------- Apply / remove ----------------

func apply(effect: StatusEffect, source: Node = null) -> void:
	if effect == null or effect.effect_id == &"":
		return

	# Binding immunity (Net-Cutter kenning). Binding effects — nets,
	# grabs, roots, drags — never take hold of an immune player. Gated
	# on the owner being in the "player" group so enemy StatusEffect
	# Components never pay the KenningManager lookup (kennings are a
	# player-only system). The check runs per-application, so the
	# immunity is live the moment the kenning is equipped and gone the
	# moment it's unequipped — no cached state to invalidate.
	if effect.binding \
			and get_parent().is_in_group("player") \
			and KenningManager.is_binding_immune():
		return

	if _active.has(effect.effect_id):
		_handle_reapply(effect, source)
	else:
		var ae := ActiveEffect.new(effect, source)
		_active[effect.effect_id] = ae
		effect.on_apply(get_parent(), 1)
		effect_applied.emit(effect, 1)


## Try to apply an array of StatusApplications, rolling chance for each.
## Used by entities to process info["on_hit_effects"] from damage_info.
func try_apply_each(applications: Array, source: Node = null) -> void:
	for app in applications:
		if app is StatusApplication and app.effect != null:
			if randf() < app.chance:
				apply(app.effect, source)


func remove(effect_id: StringName) -> void:
	if not _active.has(effect_id):
		return
	var ae: ActiveEffect = _active[effect_id]
	_active.erase(effect_id)
	if ae.effect:
		ae.effect.on_remove(get_parent())
		effect_removed.emit(ae.effect)


func clear_all() -> void:
	for id in _active.keys():
		remove(id)


func _handle_reapply(effect: StatusEffect, _source: Node) -> void:
	var ae: ActiveEffect = _active[effect.effect_id]
	match effect.stack_behavior:
		StatusEffect.StackBehavior.REFRESH:
			ae.time_remaining = effect.duration
		StatusEffect.StackBehavior.ADD_STACK:
			ae.stacks = mini(ae.stacks + 1, effect.max_stacks)
			ae.time_remaining = effect.duration
			effect_applied.emit(effect, ae.stacks)
		StatusEffect.StackBehavior.IGNORE:
			pass


# ---------------- Queries ----------------

func has_effect(effect_id: StringName) -> bool:
	return _active.has(effect_id)

func get_active(effect_id: StringName) -> ActiveEffect:
	return _active.get(effect_id)


# ---------------- Aggregate modifiers ----------------

func get_speed_multiplier() -> float:
	var m := 1.0
	for ae in _active.values():
		m *= ae.effect.speed_multiplier
	return m

func get_damage_taken_multiplier() -> float:
	var m := 1.0
	for ae in _active.values():
		m *= ae.effect.damage_taken_multiplier
	return m

func get_damage_dealt_multiplier() -> float:
	var m := 1.0
	for ae in _active.values():
		m *= ae.effect.damage_dealt_multiplier
	return m

func is_action_prevented() -> bool:
	for ae in _active.values():
		if ae.effect.prevents_action:
			return true
	return false


## Get the dominant tint color (highest intensity wins). Returns Color(0,0,0,0)
## if no tinting effect is active. Use for visual feedback in _draw or shaders.
func get_tint() -> Color:
	var best := Color(0, 0, 0, 0)
	var best_intensity := 0.0
	for ae in _active.values():
		var fx: StatusEffect = ae.effect
		if fx.tint_color.a > 0.0 and fx.tint_intensity > best_intensity:
			best_intensity = fx.tint_intensity
			best = Color(fx.tint_color.r, fx.tint_color.g, fx.tint_color.b, fx.tint_intensity)
	return best


# ---------------- Tick loop ----------------

func _process(delta: float) -> void:
	if _active.is_empty():
		return

	var to_remove: Array[StringName] = []

	for id in _active:
		var ae: ActiveEffect = _active[id]

		# Tick
		if ae.effect.tick_interval > 0.0:
			ae.time_to_next_tick -= delta
			if ae.time_to_next_tick <= 0.0:
				_do_tick(ae)
				ae.time_to_next_tick += ae.effect.tick_interval

		# Expiration (negative duration = permanent)
		if ae.effect.duration >= 0.0:
			ae.time_remaining -= delta
			if ae.time_remaining <= 0.0:
				to_remove.append(id)

	for id in to_remove:
		remove(id)


func _do_tick(ae: ActiveEffect) -> void:
	# Give subclasses first crack — if they handle it, skip default damage.
	var handled: bool = ae.effect.on_tick(get_parent(), ae.stacks)
	if not handled and ae.effect.damage_per_tick > 0.0:
		var info := {
			"amount": ae.effect.damage_per_tick * ae.stacks,
			"element": ae.effect.damage_element,
			"from_status": true,
			"status_id": ae.effect.effect_id,
		}
		tick_damage.emit(info["amount"], info)
	if not handled and ae.effect.heal_per_tick > 0.0:
		var heal_info := {
			"amount": ae.effect.heal_per_tick * ae.stacks,
			"from_status": true,
			"status_id": ae.effect.effect_id,
		}
		tick_heal.emit(heal_info["amount"], heal_info)
	effect_ticked.emit(ae.effect, ae.stacks)
