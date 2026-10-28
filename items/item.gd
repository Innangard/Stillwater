class_name Item
extends Resource
## Base class for all collectible items. Reagents, keys, quest items —
## anything that goes in the inventory.
##
## ConsumableItem subclasses this to add use-on-click behavior. Reagents
## and keys are usually plain Items distinguished by `category`. Subclass
## further only when behavior actually differs.

@export_group("Identity")
@export var item_name: String = "Unnamed Item"
@export_multiline var description: String = ""
@export var icon: Texture2D = null
## Tag for grouping. Suggested values: "reagent", "key", "consumable",
## "quest", "misc". Used by crafting recipes and any future filters.
@export var category: String = "misc"

@export_group("Inventory")
## How many fit in one stack. 1 = unstackable (keys, unique items).
@export_range(1, 99) var max_stack: int = 99

@export_group("Visual")
## Placeholder color for inventory and pickup visuals until you have art.
@export var placeholder_color: Color = Color(0.7, 0.7, 0.7)


# ============================================================================
# DECONSTRUCTION
# ============================================================================
##
## Items can be broken down into a fraction of the reagents (or souls) that
## made them. The Recipe authoring the item is found via CraftingRegistry's
## reverse-lookup map — no per-item .tres edits needed. Source recipes are
## discovered at game start by scanning crafting/instances/.
##
## What you get back depends on the recipe type:
##   - Reagent input  → ~50% probabilistic return per unit
##   - requires_weapon → ~50% chance to return the base weapon (binary)
##   - currency_cost (buy recipes) → 50% return as souls
##
## A weapon crafted from a previous weapon (e.g. an upgraded variant)
## returns BOTH the base weapon and the upgrade-stage reagents at the
## 50% rates. A buy-style reagent recipe (currency_cost > 0, no inputs)
## returns only souls. A distill recipe (inputs, no currency) returns
## reagents. The salvage type is whatever the recipe's input side says.
##
## Returns a Dictionary describing what was salvaged, suitable for the
## inventory UI to display as a toast:
##   {
##     "items": [{"item": Item, "count": int}, ...],
##     "weapons": [Weapon, ...],
##     "souls": int,
##   }
## Empty arrays / zero souls if nothing was salvaged. Returns the empty
## form (not null) if there's no source recipe — that way the caller
## doesn't have to null-check before reading fields.
const _SALVAGE_RATE: float = 0.5


## Convenience: does deconstructing this item produce ANYTHING? Used
## by the UI to gray out the deconstruct button when it would be a no-op
## (items not authored by a recipe, like world-drops or quest items).
func can_deconstruct() -> bool:
	var rec: Recipe = get_source_recipe()
	if rec == null:
		return false
	# A recipe with no inputs and no currency and no required-weapon has
	# nothing to give back. The empty-pool case shouldn't usually exist,
	# but we guard so the player isn't shown a button that does nothing.
	var has_inputs: bool = false
	for entry in rec.inputs:
		if entry != null and entry.item != null and entry.count > 0:
			has_inputs = true
			break
	return has_inputs or rec.requires_weapon != null or rec.currency_cost > 0


## Returns the Recipe whose output produced this item, or null if no
## recipe authored this item (e.g. enemy drops). Routes through the
## CraftingRegistry autoload, which builds the reverse-lookup at game
## start so this call is O(1).
func get_source_recipe() -> Recipe:
	return CraftingRegistry.recipe_for(self)


## Compute and apply the salvage. Removes one of this item from
## inventory, adds the salvage. The caller is responsible for checking
## can_deconstruct() first; this function will still produce sensible
## (empty) output if called on something un-deconstructible, but won't
## remove the item from inventory in that case.
func deconstruct() -> Dictionary:
	var salvage: Dictionary = {
		"items": [],
		"weapons": [],
		"souls": 0,
	}
	var rec: Recipe = get_source_recipe()
	if rec == null:
		return salvage

	# Reagent inputs: each unit rolled independently at _SALVAGE_RATE.
	# Probabilistic rather than rounded-floor so rare 1-count inputs
	# still have a chance to return — without this, deconstructing a
	# weapon that used a single Hoarfrost Tear would deterministically
	# lose that tear, which doesn't match the "refund" feel.
	for entry in rec.inputs:
		if entry == null or entry.item == null:
			continue
		var returned: int = 0
		for _i in entry.count:
			if randf() < _SALVAGE_RATE:
				returned += 1
		if returned > 0:
			salvage["items"].append({"item": entry.item, "count": returned})

	# Required weapon: a single binary roll. This handles upgrade-chain
	# recipes (Pyrelined Cuirass requires a Cinderplate Cuirass; decon
	# of Pyrelined has a 50% chance to give back a Cinderplate).
	if rec.requires_weapon != null:
		if randf() < _SALVAGE_RATE:
			salvage["weapons"].append(rec.requires_weapon)

	# Currency cost: 50% refund as souls. This is the primary salvage
	# path for buy-recipe reagents (inputs are empty, currency_cost > 0)
	# but also fires for any recipe that had a soul cost on top of
	# reagent inputs.
	if rec.currency_cost > 0:
		salvage["souls"] = int(rec.currency_cost * _SALVAGE_RATE)

	# Apply the salvage to player inventory + currency.
	RunState.remove_one_from_inventory(self)
	for entry in salvage["items"]:
		for _i in entry["count"]:
			RunState.add_to_inventory(entry["item"])
	for w in salvage["weapons"]:
		RunState.add_to_inventory(w)
	if salvage["souls"] > 0:
		GameState.add_currency(salvage["souls"])

	return salvage
