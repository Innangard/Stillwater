extends CanvasLayer
## Autoloaded scene transitioner. Public APIs:
##
##   SceneTransition.go_to("res://world/regions/forest.tscn", "south_path")
##     — Used by ExitZones during normal traversal.
##
##   SceneTransition.respawn_at_arch()
##     — Called when the player dies. Fades to black with a slightly
##       longer hold, resets the run state, and teleports to whichever
##       arch the player most recently activated (or south_arch as
##       fallback).
##
## Listens to EventBus.player_died directly so individual scenes don't
## need to wire death handling — it just works.
##
## NOTE: No class_name (autoload "SceneTransition").

const FADE_DURATION := 0.18
const DEATH_FADE_HOLD := 0.6 # extra time the screen stays black on death

# Lore-overlay timing. The lore text fades in over LORE_FADE_DURATION,
# holds for LORE_HOLD_DURATION, then fades out. Two seconds of fade
# feels meditative without dragging; three-and-a-half seconds of hold
# is enough to read five short lines at a comfortable pace. Tuneable
# per-call by future overrides if any sequence needs different timing.
const LORE_FADE_DURATION := 1.2
const LORE_HOLD_DURATION := 3.5

## Runtime registry of all arches the player has ever encountered. Each
## arch self-registers when its _ready() runs via register_arch(), so
## new arches added to scenes automatically work as respawn destinations
## with no manual table edits. (The old hardcoded ARCH_REGISTRY const
## broke the moment a second arch existed — the player could activate
## it, but death respawned at south because the dict had only one entry.)
##
## Schema: arch_id -> { scene: String, spawn: String }
## The default fallback registration ensures south_arch is known before
## the first scene even loads — needed because death-respawn could fire
## before the player has visited south_cliff in this session.
var _arch_registry: Dictionary = {
	"south_arch": {
		"scene": "res://world/regions/south_cliff.tscn",
		"spawn": "default",
	},
}
const FALLBACK_ARCH_ID := "south_arch"

var _fade: ColorRect
var _lore_label: Label
var _busy: bool = false


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	layer = 50
	_build_ui()
	EventBus.player_died.connect(_on_player_died)


func _build_ui() -> void:
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.modulate = Color(1, 1, 1, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	# Lore overlay — a centered label that floats over the fade for
	# scene-intro narrations. Sized to ~60% of screen width so lines
	# wrap naturally without going edge to edge. Sits as a sibling
	# of _fade (not a child) so its alpha animates independently —
	# the lore can fade out while the black fade is still solid, then
	# the black itself fades out to reveal the new scene.
	_lore_label = Label.new()
	_lore_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lore_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lore_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lore_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lore_label.add_theme_font_size_override("font_size", 22)
	_lore_label.add_theme_color_override("font_color", Color(0.92, 0.95, 0.98, 1))
	_lore_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lore_label.modulate = Color(1, 1, 1, 0)
	# Inset the text horizontally so wrapped lines have margin from
	# the screen edges. Vertical center stays at the middle.
	_lore_label.offset_left = 160
	_lore_label.offset_right = -160
	add_child(_lore_label)


# ============================================================================
# NORMAL TRAVERSAL
# ============================================================================

func go_to(scene_path: String, spawn_point: String = "") -> void:
	if _busy:
		return
	_busy = true
	RunState.requested_spawn_point = spawn_point
	get_tree().paused = true

	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, FADE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_do_swap.bind(scene_path))
	tween.tween_property(_fade, "modulate:a", 0.0, FADE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_finish)
	# Auto-save AFTER the new scene is fully up. Tween callbacks run in
	# order, so this fires after _finish — by which point the new scene's
	# RegionRoot has spawned the player and RunState.current_region is
	# accurate. Auto-saving mid-transition would snapshot a half-loaded
	# state. SaveManager.autosave_if_active no-ops on the title screen
	# (current_slot == 0), so this is safe to call unconditionally.
	tween.tween_callback(SaveManager.autosave_if_active)


# ============================================================================
# NARRATED TRANSITIONS
# ============================================================================
## Two methods for scene-bracketing lore narrations:
##   play_opening_lore — for a fresh scene that should display lore
##     over a black screen before revealing itself (game start, etc.)
##   go_to_with_lore — for a scene transition that should display
##     lore in the middle of the fade (the passage at Ginnungagap's
##     north edge, etc.)
##
## Both keep the tree paused while lore is on screen, so the player
## can't move during narration. Both ride on the same _fade overlay
## and _lore_label, so calling either while another is mid-sequence
## is guarded by _busy.


## Plays opening lore at scene start. Forces the fade to fully opaque
## IMMEDIATELY (preventing a first-frame flash of the scene before the
## lore begins), fades the lore in over LORE_FADE_DURATION, holds for
## LORE_HOLD_DURATION, fades the lore out, then fades the scene in.
## Tree stays paused until the scene fade-in completes — the player
## can't move during the narration.
##
## Called from a scene's ready handler (typically via a SceneIntro
## child node) when the scene wants a narrated reveal. The caller is
## responsible for any one-time gating (a story flag check to avoid
## replaying on save reload).
func play_opening_lore(lore_text: String) -> void:
	if _busy:
		return
	_busy = true
	# Immediately black — sets the alpha before the engine renders the
	# first frame of the new scene, so the player never glimpses the
	# scene through a transparent fade. This is the whole reason the
	# fade alpha lives on a CanvasLayer at layer 50: it's the topmost
	# pixel-buffer modifier in the render order, and changes here
	# apply to the very next frame.
	_fade.modulate.a = 1.0
	_lore_label.text = lore_text
	_lore_label.modulate.a = 0.0
	get_tree().paused = true

	var tween := create_tween()
	# Phase 1: lore fades in over black
	tween.tween_property(_lore_label, "modulate:a", 1.0, LORE_FADE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Phase 2: lore holds — player reads it
	tween.tween_interval(LORE_HOLD_DURATION)
	# Phase 3: lore fades out (still over black)
	tween.tween_property(_lore_label, "modulate:a", 0.0, LORE_FADE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Phase 4: black fades out, revealing the scene
	tween.tween_property(_fade, "modulate:a", 0.0, FADE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Phase 5: unpause so the player can move
	tween.tween_callback(_finish_intro)


## Plays closing lore as part of a scene transition. Fade to black,
## fade lore in, hold, fade lore out, swap scene, fade in new scene.
## Equivalent to go_to() with a narrated beat in the middle. Used by
## passage-style interactables that have a story bookend on their
## transition.
##
## Called from a Passage's activation handler when its closing_lore_text
## is set. The narrative timing: the player sees the lore over a black
## screen for ~7 seconds total (1.2 fade-in + 3.5 hold + 1.2 fade-out
## + ~0.2 scene fade) before they're back in control on the other side.
func go_to_with_lore(scene_path: String, spawn_marker: String, lore_text: String) -> void:
	if _busy:
		return
	_busy = true
	RunState.requested_spawn_point = spawn_marker
	get_tree().paused = true
	_lore_label.text = lore_text
	_lore_label.modulate.a = 0.0

	var tween := create_tween()
	# Phase 1: current scene fades to black
	tween.tween_property(_fade, "modulate:a", 1.0, FADE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Phase 2: lore fades in over black
	tween.tween_property(_lore_label, "modulate:a", 1.0, LORE_FADE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Phase 3: lore holds
	tween.tween_interval(LORE_HOLD_DURATION)
	# Phase 4: lore fades out
	tween.tween_property(_lore_label, "modulate:a", 0.0, LORE_FADE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Phase 5: swap scene (this unpauses the tree internally — see
	# _do_swap). The new scene is hidden behind the still-opaque _fade.
	tween.tween_callback(_do_swap.bind(scene_path))
	# Phase 6: black fades out, revealing the new scene
	tween.tween_property(_fade, "modulate:a", 0.0, FADE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_finish)
	tween.tween_callback(SaveManager.autosave_if_active)


## Internal end-of-sequence for play_opening_lore. Unlike _finish (which
## just clears _busy), this also unpauses the tree — necessary because
## play_opening_lore pauses the tree but never calls _do_swap (which
## is where the pause normally lifts).
func _finish_intro() -> void:
	get_tree().paused = false
	_busy = false


# ============================================================================
# DEATH RESPAWN
# ============================================================================

func _on_player_died() -> void:
	respawn_at_arch()


## Called by every Arch on _ready to register itself as a valid respawn
## destination. Schema matches _arch_registry: scene_path is the scene
## file the arch lives in, spawn_marker is the Marker2D name in that
## scene to teleport the player to. Spawn marker defaults to "default"
## which RegionRoot already treats as the canonical entry point.
func register_arch(arch_id: String, scene_path: String, spawn_marker: String = "default") -> void:
	if arch_id == "":
		return
	_arch_registry[arch_id] = {
		"scene": scene_path,
		"spawn": spawn_marker,
	}


## Public entry — call directly if you want to teleport to an arch
## without it being a death (warp scrolls, debug shortcuts, etc.).
func respawn_at_arch() -> void:
	if _busy:
		return
	_busy = true
	get_tree().paused = true
	print("[respawn] last_arch_id=", GameState.last_arch_id,
		" registry=", _arch_registry)   # ← first print goes here

	# Pick the destination from the persistent last-arch record. If the
	# player has never activated any arch, or the recorded arch isn't
	# registered (e.g. they activated an arch in a scene that has since
	# been deleted), fall back to the south arch.
	var arch_id: String = GameState.last_arch_id
	if arch_id == "" or not _arch_registry.has(arch_id):
		arch_id = FALLBACK_ARCH_ID
	var dest: Dictionary = _arch_registry[arch_id]
	
	print("[respawn] dest=", dest)

	# Run-state reset happens DURING the black hold so the player never
	# sees the empty-handed sprite for a frame in the old scene before
	# the swap.
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, FADE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(RunState.reset_for_new_run)
	tween.tween_interval(DEATH_FADE_HOLD)
	# Swap into the arch's scene, spawning at its named marker.
	tween.tween_callback(func():
		RunState.requested_spawn_point = dest["spawn"]
		_do_swap(dest["scene"])
	)
	tween.tween_property(_fade, "modulate:a", 0.0, FADE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_finish)
	# Auto-save the post-respawn state. After this, quitting and
	# reloading puts the player exactly where they respawned — no
	# free do-over by quitting mid-death. The increased death_count
	# is captured in the save too.
	tween.tween_callback(SaveManager.autosave_if_active)


# ============================================================================
# INTERNAL
# ============================================================================

func _do_swap(scene_path: String) -> void:
	get_tree().paused = false
	EventBus.reset_interactables()
	var err: int = get_tree().change_scene_to_file(scene_path)
	print("[respawn] change_scene_to_file(", scene_path, ") -> err=", err)
	if err != OK:
		push_error("SceneTransition: failed to load %s (err %d)" % [scene_path, err])


func _finish() -> void:
	_busy = false
