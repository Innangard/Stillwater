class_name Recipe
extends Resource
## A crafting recipe.
##
## Two flavors, both handled by the same class:
##   - Item recipe:    inputs only → output_item
##   - Weapon recipe:  inputs + requires_weapon → output_weapon
##                     (the required weapon can be EQUIPPED or in inventory)
##
## Requirements UI: get_requirement_status() returns a structured list that
## the crafting UI renders as green/red chips, always visible.

@export_group("Identity")
@export var recipe_name: String = "Unnamed Recipe"
@export_multiline var description: String = ""

@export_group("Inputs")
@export var inputs: Array[ItemQuantity] = []
## If set, this exact weapon must be present (equipped OR in inventory).
## On craft, the weapon is consumed: equipped instance replaced in its slot,
## or one inventory copy consumed.
@export var requires_weapon: Weapon = null
## Currency cost. Goes through the normal requirements check (red chip if
## you can't afford it). Used by merchants — a "recipe" with no inputs and
## a currency_cost is just a shop item.
@export var currency_cost: int = 0

@export_group("Outputs")
@export var output_item: Item = null
@export var output_item_count: int = 1
@export var output_weapon: Weapon = null


# ============================================================================
# REQUIREMENTS
# ============================================================================
##
## Returns one entry per requirement, always populated regardless of state.
## Each entry is a Dictionary with:
##   "label"     : String   - what to display ("Worn Blade", "2 Pale Ash")
##   "satisfied" : bool     - whether the player meets this requirement now
##   "detail"    : String   - extra context ("equipped", "have 1", etc.)
##
## The UI renders entries green if satisfied, red if not.

func get_requirement_status() -> Array:
	var entries: Array = []

	if currency_cost > 0:
		var have: int = GameState.soul_currency
		entries.append({
			"label": "%d souls" % currency_cost,
			"satisfied": have >= currency_cost,
			"detail": "have %d" % have,
		})

	if requires_weapon != null:
		var have_weapon: bool = _is_weapon_equipped(requires_weapon) \
			or RunState.has_in_inventory(requires_weapon)
		var detail: String = ""
		if _is_weapon_equipped(requires_weapon):
			detail = "equipped"
		elif RunState.has_in_inventory(requires_weapon):
			detail = "in inventory"
		else:
			detail = "missing"
		entries.append({
			"label": requires_weapon.weapon_name,
			"satisfied": have_weapon,
			"detail": detail,
		})

	for entry in inputs:
		if entry == null or entry.item == null:
			continue
		var have: int = RunState.count_in_inventory(entry.item)
		entries.append({
			"label": "%s ×%d" % [entry.item.item_name, entry.count],
			"satisfied": have >= entry.count,
			"detail": "have %d" % have,
		})

	return entries


func can_craft() -> bool:
	for entry in get_requirement_status():
		if not entry.satisfied:
			return false
	return true


# ============================================================================
# CRAFTING
# ============================================================================

func craft() -> bool:
	if not can_craft():
		return false

	# Spend currency first. If this fails (race condition where currency
	# changed between can_craft and here), bail and don't consume reagents.
	if currency_cost > 0:
		if not GameState.spend_currency(currency_cost):
			return false

	# Consume reagents from inventory.
	for entry in inputs:
		if entry == null or entry.item == null:
			continue
		for _i in entry.count:
			RunState.remove_one_from_inventory(entry.item)

	# Handle the required-weapon consumption + output_weapon placement.
	if requires_weapon != null:
		var slot: String = _find_equipped_slot(requires_weapon)
		if slot != "":
			# Equipped path: replace in-slot. The previous weapon is consumed
			# (not stashed), since this is a transformation, not a swap.
			_consume_equipped_and_replace(slot, output_weapon)
		else:
			# Inventory path: remove one copy, then place output.
			RunState.remove_one_from_inventory(requires_weapon)
			if output_weapon != null:
				RunState.add_to_inventory(output_weapon)
	elif output_weapon != null:
		# Standalone weapon output (no requires_weapon to replace) —
		# goes to inventory like any other crafted item.
		RunState.add_to_inventory(output_weapon)

	# Grant item output.
	if output_item != null:
		for _i in output_item_count:
			RunState.add_to_inventory(output_item)

	return true


# ============================================================================
# HELPERS
# ============================================================================

func _is_weapon_equipped(w: Weapon) -> bool:
	return RunState.primary_weapon == w \
		or RunState.secondary_weapon == w \
		or RunState.prepared_primary == w \
		or RunState.prepared_secondary == w


func _find_equipped_slot(w: Weapon) -> String:
	if RunState.primary_weapon == w:      return "primary"
	if RunState.secondary_weapon == w:    return "secondary"
	if RunState.prepared_primary == w:    return "prepared_primary"
	if RunState.prepared_secondary == w:  return "prepared_secondary"
	return ""


## Replace the equipped weapon in `slot` with `new_weapon`. Crucially,
## the OLD weapon is NOT stashed back into inventory — it's consumed,
## because crafting transforms the source. We do this by clearing the
## slot first (so the equip helper's "stash old" branch sees an empty
## slot) and then equipping the new one.
func _consume_equipped_and_replace(slot: String, new_weapon: Weapon) -> void:
	match slot:
		"primary":            RunState.primary_weapon = null
		"secondary":          RunState.secondary_weapon = null
		"prepared_primary":   RunState.prepared_primary = null
		"prepared_secondary": RunState.prepared_secondary = null

	if new_weapon == null:
		# Unusual — recipe with requires_weapon but no output. Just emit
		# the slot-cleared signal so HUD/inventory refresh.
		EventBus.weapon_equipped.emit(null, slot)
		return

	# `_skip_inventory = true` because the new weapon was just created,
	# not pulled from inventory.
	match slot:
		"primary":            RunState.equip_primary(new_weapon, true)
		"secondary":          RunState.equip_secondary(new_weapon, true)
		"prepared_primary":   RunState.equip_prepared_primary(new_weapon, true)
		"prepared_secondary": RunState.equip_prepared_secondary(new_weapon, true)
