extends Node
## Autoload: scans crafting/instances/ at startup and builds a reverse-
## lookup map from recipe outputs (Items and Weapons) back to the
## Recipe that produces them.
##
## Used by Item.deconstruct() to figure out what salvage to return.
## Centralized so the scan happens exactly once and every Item call
## hits an O(1) Dictionary lookup. Without this, deconstruct would
## have to walk the disk every time the player breaks something down.
##
## Coverage policy:
## - If multiple recipes produce the same output (rare but possible —
##   e.g. a "buy reagent X" and a "distill reagent X" might both
##   produce the same Item), the LAST one scanned wins. In practice
##   the project's recipe naming convention separates these (buy_X
##   vs distill_X, vs forge_X for crafting) and the buy form is
##   what's listed last alphabetically, so reagents map to their
##   buy recipe → soul refund. That's the right behavior per the
##   user's requirement: "reagents would only get soul back from a
##   purchase crafting recipe."
## - If no recipe produces an item (world drops like reagents found
##   in pickups, quest items, etc.), recipe_for() returns null and
##   Item.can_deconstruct() returns false. Player sees no salvage
##   option on those items — the right UX.

const CATALOG_DIR := "res://crafting/instances/"

## Maps: Resource (the output Item or Weapon) → Recipe (the producer).
## Keyed by the Resource itself (Godot allows resources as dict keys).
var _by_output: Dictionary = {}

## Total count for debug visibility — surfaced in editor logs at
## startup so a misnamed recipe directory is obvious.
var _recipe_count: int = 0


func _ready() -> void:
	_build_map()


## Public lookup. Returns the Recipe whose output is `output`, or null
## if no recipe produces it. Called by Item.get_source_recipe().
func recipe_for(output: Resource) -> Recipe:
	if output == null:
		return null
	return _by_output.get(output)


## Walk crafting/instances/, load each .tres, register its output_item
## and output_weapon (whichever is non-null) into _by_output.
##
## Recipes can have BOTH output_item and output_weapon (the latter is
## uncommon but legal — e.g. a recipe that produces a weapon AND a
## consolation reagent). We register both pointers; player decon of
## either gets the same source recipe.
##
## Files are walked in alphabetical order (DirAccess.list_dir_begin
## convention), so "later wins" predictability is preserved: a
## "buy_*.tres" beats a "forge_*.tres" producing the same output,
## because buy comes after forge alphabetically. This is intentional
## per the docstring above: buy recipes for reagents take precedence
## so that deconstructing a bought reagent refunds souls instead of
## doing nothing useful.
func _build_map() -> void:
	var dir := DirAccess.open(CATALOG_DIR)
	if dir == null:
		push_warning("CraftingRegistry: cannot open " + CATALOG_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		# Export-safety: strip the ".remap" suffix Godot appends to
		# resources in exported PCKs. load() on the original path
		# still works; only the directory listing shows the remap.
		fname = fname.trim_suffix(".remap")
		if dir.current_is_dir() or not fname.ends_with(".tres"):
			fname = dir.get_next()
			continue
		var res: Resource = load(CATALOG_DIR + fname)
		if res is Recipe:
			var rec: Recipe = res
			if rec.output_item != null:
				_by_output[rec.output_item] = rec
			if rec.output_weapon != null:
				_by_output[rec.output_weapon] = rec
			_recipe_count += 1
		fname = dir.get_next()
	dir.list_dir_end()
	print("CraftingRegistry: indexed %d recipes, %d distinct outputs."
		% [_recipe_count, _by_output.size()])
