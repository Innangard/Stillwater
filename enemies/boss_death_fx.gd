class_name BossDeathFx
extends RefCounted
## Boss death spectacle. Called by each boss's _on_died override to play
## the same dramatic sequence: hit-stop, screen shake, ash burst, world
## text, body fade-out. The boss is queue_free'd at the end of the fade
## so the player sees the death animate instead of a hard pop-off-screen.
##
## Pulled out into a standalone helper (rather than a method on a
## shared base class) because boss_enemy.gd and cinder_sovereign.gd
## both extend Enemy directly — refactoring them to share a parent
## just for the spectacle would touch many lines for little gain.
## This file is a static-style utility: call BossDeathFx.play(boss).
##
## What it does, in order:
##   1. Stops the boss from moving (velocity = 0) and from drawing its
##      WIND_UP telegraph (we won't have time to read a new attack).
##   2. Fires hit-stop and a big screen shake. The hit-stop is shorter
##      than the long-stun pulse so the player has agency back quickly.
##   3. Spawns a radial burst of "ash" particles drawn directly on the
##      boss's parent (so they survive past the boss being freed).
##   4. Spawns a "<NAME> falls." world text at the boss's head.
##   5. Tweens the boss's modulate alpha to 0 over ~1.4s, then queue_frees.
##   6. Spawns a guaranteed bonus pickup (currency burst).
##
## The base Enemy._on_died still runs through the boss override BEFORE
## queue_free, so the regular drop pipeline still fires — this helper
## only adds spectacle on top of normal loot. The boss's `_on_died`
## override is responsible for skipping the immediate queue_free in
## Enemy by NOT calling super().

const ASH_PARTICLE_COUNT: int = 24
const ASH_SCRIPT_PATH: String = "res://enemies/boss_death_particle.gd"
const FADE_DURATION: float = 1.4
const HIT_STOP_DURATION: float = 0.4
const HIT_STOP_SCALE: float = 0.10
const SHAKE_STRENGTH: float = 16.0
const SHAKE_DURATION: float = 0.6
const BONUS_CURRENCY_MIN: int = 60
const BONUS_CURRENCY_MAX: int = 120
const BONUS_CURRENCY_SPREAD_PX: float = 80.0


## Entry point. `boss` is the Enemy node that just died; `display_name`
## is the human-readable name shown in the falls-text; `accent_color`
## tints the ash burst and the text (use the boss's body_tint so the
## spectacle matches its visual identity). Returns nothing; the caller
## should NOT queue_free the boss — this helper schedules the free at
## the end of the fade-out.
static func play(boss: Node2D, display_name: String, accent_color: Color) -> void:
	if not is_instance_valid(boss):
		return
	var parent: Node = boss.get_parent()
	if not is_instance_valid(parent):
		boss.queue_free()
		return

	# 1. Stop motion and AI. The boss is dying — no more attacks. Setting
	# the AI state to STUNNED stops _process_chase / _process_recover
	# from re-driving velocity. The STAGGER_WINDOW timer is now moot
	# (HealthComponent already emitted died), but a moving body during
	# the death animation looks wrong, so we explicitly halt.
	if "velocity" in boss:
		boss.velocity = Vector2.ZERO
	if "_ai_state" in boss and "AIState" in boss:
		# Setting via property access to avoid coupling to specific enum value.
		# AIState.STUNNED has value 5 in enemy.gd (last position in the enum)
		# — referenced by number so this file doesn't need to import Enemy.
		boss._ai_state = 5

	# 2. Hit-stop + screen shake. Hit-stop uses Engine.time_scale via a
	# real-time timer like hud._apply_hit_stop, but inlined here so we
	# don't depend on the HUD existing as a singleton (it's an autoload
	# but lifecycle ordering could change).
	EventBus.request_screen_shake.emit(SHAKE_STRENGTH, SHAKE_DURATION)
	_run_hit_stop(boss)

	# 3. Spawn radial ash particles. Drawn by their own little Node2D
	# script (BossDeathParticle) so they outlive the boss and animate
	# independently. Loaded dynamically so importing this file doesn't
	# also force-load the particle script at scene-construction time.
	var particle_script: GDScript = load(ASH_SCRIPT_PATH)
	if particle_script != null:
		for i in ASH_PARTICLE_COUNT:
			var p := Node2D.new()
			p.set_script(particle_script)
			parent.add_child(p)
			p.global_position = boss.global_position
			# Outward direction + variable speed and lifetime so the
			# burst reads as organic. seeding via the index keeps the
			# look consistent across frames.
			var angle: float = TAU * float(i) / float(ASH_PARTICLE_COUNT) + randf_range(-0.1, 0.1)
			p.set("velocity", Vector2.RIGHT.rotated(angle) * randf_range(100.0, 220.0))
			p.set("lifetime", randf_range(0.9, 1.6))
			p.set("color", accent_color.lerp(Color(1.0, 0.85, 0.40), 0.35))
			p.set("size", randf_range(2.5, 5.0))

	# 4. World text — "<NAME> falls." floating above the body. Same
	# rough mechanism as hud._spawn_world_text but inlined here. We
	# don't call the HUD function because it's not exposed as a public
	# API; reaching in via HUD._spawn_world_text would couple this
	# spectacle to the HUD's internals.
	_spawn_falls_text(boss.global_position + Vector2(0, -48), display_name, accent_color)

	# 5. Fade out the boss body. We can't tween `modulate` on a
	# CharacterBody2D directly with a property-name "modulate:a" tween
	# AND queue_free at the end without a small race — Tween hangs
	# onto a ref to the node, and queue_free runs deferred, so it's
	# fine. Set process_mode so the tween keeps running through the
	# brief Engine.time_scale dip we kicked off above.
	var tween := boss.create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(boss, "modulate:a", 0.0, FADE_DURATION) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tween.tween_callback(func ():
		if is_instance_valid(boss):
			boss.queue_free()
	)

	# 6. Guaranteed bonus currency burst. Numbers tuned so the boss
	# feels like a notable payoff but doesn't trivialize the
	# soul-currency economy (top mooks drop ~16; bonus drop is 60-120
	# on top of whatever the base loot pool spawns).
	_spawn_bonus_currency(parent, boss.global_position)


# ============================================================================
# INTERNAL HELPERS
# ============================================================================

static func _run_hit_stop(host: Node) -> void:
	# host = the boss; we use its scene-tree to grab a real-time timer.
	var prev_scale: float = Engine.time_scale
	Engine.time_scale = HIT_STOP_SCALE
	# Real-time timer ignores time_scale so the slow-mo actually ends.
	var tree := host.get_tree()
	if tree == null:
		Engine.time_scale = prev_scale
		return
	var timer := tree.create_timer(HIT_STOP_DURATION, true, false, true)
	await timer.timeout
	Engine.time_scale = prev_scale


static func _spawn_falls_text(world_pos: Vector2, display_name: String,
		accent: Color) -> void:
	# Build a CanvasLayer-attached Label that sits at the boss's
	# screen-space position. Couldn't use the HUD's _spawn_world_text
	# because it's private; this is a one-off, simpler copy.
	var camera: Camera2D
	# Look up the active viewport's camera. Engine.get_main_loop() is
	# safer than reaching for HUD's get_viewport because this might be
	# called during a hit-stop window where layer order is volatile.
	var ml: SceneTree = Engine.get_main_loop()
	if ml is SceneTree:
		camera = ml.root.get_viewport().get_camera_2d()
	if camera == null:
		return
	var viewport_size: Vector2 = ml.root.get_viewport().get_visible_rect().size
	var screen_pos: Vector2 = (world_pos - camera.get_screen_center_position()) \
		* camera.zoom + viewport_size * 0.5

	# Layer must outrank the HUD (layer 6 by default for the HUD scene).
	# 50 is well clear of all the menus (10, 11). Free the layer after
	# the text fades, so this doesn't leak.
	var layer := CanvasLayer.new()
	layer.layer = 50
	ml.root.add_child(layer)

	var label := Label.new()
	var text: String = "%s falls." % display_name
	label.text = text
	label.add_theme_font_size_override("font_size", 42)
	label.add_theme_color_override("font_color", Color(1.00, 0.95, 0.70))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	label.add_theme_constant_override("outline_size", 6)
	label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	label.scale = Vector2(1.6, 1.6)
	layer.add_child(label)
	label.position = screen_pos - label.size * 0.5
	label.pivot_offset = label.size * 0.5

	# A small accent block beneath the text — a colored bar tinted to
	# the boss's identity. Subtle, but it ties the spectacle to the
	# specific boss visually.
	var bar := ColorRect.new()
	bar.color = Color(accent.r, accent.g, accent.b, 0.0)
	bar.size = Vector2(label.size.x * 1.1, 4)
	layer.add_child(bar)
	bar.position = Vector2(label.position.x - label.size.x * 0.05,
		label.position.y + label.size.y + 6)

	var t := layer.create_tween()
	t.set_parallel(true)
	# Punch-in then settle. Scale-down + alpha-up over 0.25s.
	t.tween_property(label, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 1.0, 0.20)
	t.tween_property(bar, "color:a", 0.85, 0.30)
	# Linger, then fade.
	t.chain().tween_interval(1.4)
	t.tween_property(label, "modulate:a", 0.0, 0.5)
	t.tween_property(bar, "color:a", 0.0, 0.5)
	t.chain().tween_callback(func ():
		if is_instance_valid(layer):
			layer.queue_free()
	)


static func _spawn_bonus_currency(parent: Node, origin: Vector2) -> void:
	# Total currency split into 3 little piles scattered around the
	# corpse. Multiple piles read as "the boss spilled treasure"
	# better than a single fat blob, and the player gets the
	# satisfaction of vacuuming them up.
	var total: int = randi_range(BONUS_CURRENCY_MIN, BONUS_CURRENCY_MAX)
	var pickup_scene: PackedScene = load("res://pickups/pickup.tscn")
	if pickup_scene == null:
		# Fallback: just dump into GameState directly. Loses the
		# satisfying pickup beat, but the player still gets paid.
		GameState.soul_currency += total
		EventBus.currency_changed.emit(GameState.soul_currency)
		return
	var piles: int = 3
	for i in piles:
		var p: Pickup = pickup_scene.instantiate()
		var amount: int = int(round(float(total) / float(piles)))
		# Last pile absorbs the rounding remainder so totals stay exact.
		if i == piles - 1:
			amount = total - int(round(float(total) / float(piles))) * (piles - 1)
		p.currency_amount = amount
		p.persistent_per_run = true
		parent.add_child(p)
		var offset := Vector2.RIGHT.rotated(TAU * float(i) / float(piles) + randf() * 0.3)
		p.global_position = origin + offset * BONUS_CURRENCY_SPREAD_PX
