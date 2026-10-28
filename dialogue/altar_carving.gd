class_name AltarCarving
extends Node2D
## An interactable stone carving embedded in an altar. Press E nearby
## to read it; the carving picks a random monologue from its
## MonologuePool each time. Same player-proximity + E-press pattern
## as the NPC class, but no crafting station, no dialogue rotation
## across multiple lines from a fixed Dialogue — every interaction
## rolls a fresh monologue from the pool.
##
## Each altar in the world holds one of these, wired to the pool that
## matches its act. The four shipped altars (wickbarrow, eastreach,
## westmoor, sundust) all draw from act_1_pool — the player's first
## arc, where every monologue is voiced by a newly-dead or recently-
## awakened soul on the south shore. Future altars in the west
## (Brann, Storsprunga), north (Skadi's peaks), and NE (King's Tower
## approach) will wire to act_2, act_3, and act_4 pools respectively.
##
## Design notes:
## - The carving is interactable BUT visually subtle. Body is a small
##   dark stone rectangle, not a tinted person-figure. The [E] prompt
##   only appears when the player is in range — same convention NPCs
##   use, kept identical so the player's "I can interact here" read
##   doesn't fork between NPCs and carvings.
## - Re-rolling on every interaction (not "advance through the pool
##   in order") is deliberate. Players who linger at an altar between
##   runs will see variety; players who breeze through will see one
##   line and leave. The monologues are designed to read in any order;
##   none reference each other.
## - If the pool is empty (or null), the [E] prompt still appears but
##   reading shows a fallback line. This lets us ship act-2/3/4 altars
##   before their pools are written, with a visible-but-empty state
##   instead of a hard crash or silent failure.

@export var pool: MonologuePool
## Optional label shown above the carving (e.g. "Weathered Stone").
## Defaults to a generic "Carving" if left empty.
@export var carving_name: String = "Carving"
## Stable identity used to remember which monologue was chosen for this
## carving within a run. MUST be unique across all carvings in the
## world. Convention: "<altar_region_id>_<position>" (e.g.
## "wickbarrow_main", "sundust_main"). If left empty at scene-load time,
## we synthesize one from the carving's region path so legacy scenes
## still work, but explicit ids are preferred.
@export var carving_id: String = ""
## Placeholder visual tint. Dim by default — these are weathered
## stones, not painted shrines.
@export var tint: Color = Color(0.32, 0.30, 0.28)

@onready var area: Area2D = $Area2D

var _player_in_range: Player = null


func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	queue_redraw()
	if _player_in_range and Input.is_action_just_pressed("interact"):
		_read_carving()


## Roll one monologue from the pool and show it. Always opens the
## DialogueUI so the player gets some feedback that interaction
## happened — even when the pool is empty, the fallback line plays
## through the same channel so the UX is uniform.
##
## The roll is LOCKED-IN per run: the first interaction with this
## carving in a given run picks the monologue, and subsequent reads in
## the same run show the same one. The carving feels like a static
## inscription, not a random oracle. RunState's carving_chosen_monologue
## dict holds the per-carving choice; RunState clears it on respawn so
## the next run rolls fresh.
##
## Also emits EventBus.monologue_read so the KenningManager (and any
## future system) can track which lore the player has seen. The signal
## fires on EVERY interaction (including repeats within a run) — this
## is correct for the lorebearer-kenning use case, which deduplicates
## via story_flags and treats "I've read this monologue at least once"
## as the unit of progress.
func _read_carving() -> void:
	var id: String = _resolve_carving_id()
	var chosen: Dialogue = _resolve_run_locked_monologue(id)
	if chosen != null and chosen.resource_path != "":
		EventBus.monologue_read.emit(chosen.resource_path)
	if chosen == null:
		chosen = _build_fallback_dialogue()
	# Carvings have no crafting station — pass empty station name and
	# an empty recipes array so the dialogue UI shows ONLY the text
	# bubble, no shop button.
	DialogueUI.show_dialogue(chosen, "", [])


## Resolve which monologue this carving shows this run. On first
## interaction, picks at random from the pool and stores the choice in
## RunState. On subsequent interactions in the same run, returns the
## stored choice. Returns null if the pool is empty or missing.
func _resolve_run_locked_monologue(id: String) -> Dialogue:
	if pool == null:
		return null
	# Already chose for this run? Load from path and return.
	if RunState.carving_chosen_monologue.has(id):
		var path: String = RunState.carving_chosen_monologue[id]
		if path != "":
			var d: Resource = load(path)
			if d is Dialogue:
				return d as Dialogue
		# Stored path is invalid (file moved, etc.). Fall through and
		# roll a fresh choice — this only happens when the project
		# changes between save & load, so a re-roll is fine.
	# First interaction this run. Roll and store.
	var chosen: Dialogue = pool.pick_random()
	if chosen != null and chosen.resource_path != "":
		RunState.carving_chosen_monologue[id] = chosen.resource_path
	return chosen


## Resolve the carving's identity for the run-scope cache. Prefers the
## explicit carving_id export; falls back to a path-based identity if
## the export wasn't set (legacy scenes).
func _resolve_carving_id() -> String:
	if carving_id != "":
		return carving_id
	# Fallback: scene_file_path of the parent region + this carving's
	# node path. Stable enough for legacy carvings without explicit ids.
	var parent_path: String = ""
	if get_parent() and get_parent().scene_file_path != "":
		parent_path = get_parent().scene_file_path
	return parent_path + ":" + str(get_path())


## Synthesize a one-line fallback Dialogue when the pool is empty or
## null. Stylistically consistent with the bible's "carving" voice:
## tired, weathered, restrained.
##
## Built at runtime rather than as a baked .tres file so empty-pool
## carvings can ship without an additional resource dependency, and
## so the fallback automatically updates if we change the wording.
func _build_fallback_dialogue() -> Dialogue:
	var line := DialogueLine.new()
	line.speaker = "A Carving"
	line.text = "The stone is too weathered to read. Whatever was here was scratched out long before you arrived."
	var d := Dialogue.new()
	d.lines = [line]
	return d


func _on_body_entered(body: Node) -> void:
	if body is Player:
		_player_in_range = body
		EventBus.notify_interactable_entered()


func _on_body_exited(body: Node) -> void:
	if body == _player_in_range:
		_player_in_range = null
		EventBus.notify_interactable_exited()


# Placeholder visual: a small dark stone slab with the carving name
# overhead and [E] prompt when in range. Same draw pattern as NPC,
# scaled down and color-shifted toward "weathered stone" so the
# player can tell a carving apart from a person at a glance.
func _draw() -> void:
	# Body — narrower than NPCs and squat, reading as a tablet, not a
	# figure. Outline is bold so it stays visible against the dim
	# altar palettes.
	draw_rect(Rect2(-10, -14, 20, 24), tint)
	draw_rect(Rect2(-10, -14, 20, 24), Color.BLACK, false, 1.5)
	# A small horizontal scratch across the front, suggesting carved
	# text without us actually drawing letters at this zoom level.
	draw_rect(Rect2(-7, -8, 14, 2), Color(0.16, 0.14, 0.12, 0.8))
	draw_rect(Rect2(-7, -2, 14, 2), Color(0.16, 0.14, 0.12, 0.8))
	draw_rect(Rect2(-7,  4, 10, 2), Color(0.16, 0.14, 0.12, 0.8))

	var font := ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(-80, -24), carving_name,
			HORIZONTAL_ALIGNMENT_CENTER, 160, 11, Color(0.85, 0.82, 0.78, 0.85))
		if _player_in_range:
			draw_string(font, Vector2(-15, 28), "[E]",
				HORIZONTAL_ALIGNMENT_CENTER, 30, 14, Color(1.0, 0.95, 0.4))
