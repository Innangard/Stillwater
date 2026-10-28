class_name Norn
extends NPC
## The Norn — a runic NPC who inscribes runestones.
## Auto-loads every Recipe .tres in res://crafting/instances/runes/
## so new runestone recipes are picked up without editing any scene.
##
## Extends NPC: the player presses [E] to open dialogue, and a "Norn"
## craft button appears from line 1 (or immediately if no dialogue is set).

const RUNE_RECIPE_DIR := "res://crafting/instances/runes/"


func _ready() -> void:
	npc_name = "Norn"
	station_name = "Norn"
	tint = Color(0.45, 0.30, 0.55, 1.0)
	_load_rune_recipes()
	super()


func _load_rune_recipes() -> void:
	recipes.clear()
	var dir := DirAccess.open(RUNE_RECIPE_DIR)
	if dir == null:
		push_warning("Norn: could not open recipe directory '%s'. Error: %s" % [
			RUNE_RECIPE_DIR, DirAccess.get_open_error()])
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var clean_name := file_name.replace(".remap", "")
		if clean_name.ends_with(".tres"):
			var path := RUNE_RECIPE_DIR + clean_name
			var recipe: Recipe = load(path) as Recipe
			if recipe != null:
				recipes.append(recipe)
			else:
				push_warning("Norn: failed to load recipe at '%s'." % path)
		file_name = dir.get_next()
	dir.list_dir_end()

	recipes.sort_custom(_sort_by_name)
	print("Norn: loaded %d rune recipes." % recipes.size())


static func _sort_by_name(a: Recipe, b: Recipe) -> bool:
	return a.recipe_name.naturalnocasecmp_to(b.recipe_name) < 0


# --- Override placeholder visual: diamond shape distinct from NPCs ---
func _draw() -> void:
	var half := Vector2(25, 25)

	# Outer glow
	draw_circle(Vector2.ZERO, 32.0, Color(tint.r, tint.g, tint.b, 0.15))

	# Body — diamond shape
	var points := PackedVector2Array([
		Vector2(0, -half.y),
		Vector2(half.x, 0),
		Vector2(0, half.y),
		Vector2(-half.x, 0),
	])
	draw_colored_polygon(points, tint)
	draw_polyline(points + PackedVector2Array([points[0]]), Color.BLACK, 2.0)

	# Inner rune mark
	draw_circle(Vector2.ZERO, 6.0, Color(0.85, 0.75, 0.55))

	var font := ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(-80, -34), npc_name,
			HORIZONTAL_ALIGNMENT_CENTER, 160, 14, Color(0.85, 0.75, 0.95))
		if _player_in_range:
			draw_string(font, Vector2(-15, 44), "[E]",
				HORIZONTAL_ALIGNMENT_CENTER, 30, 14, Color(1.0, 0.95, 0.4))
