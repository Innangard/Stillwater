class_name ItemQuantity
extends Resource
## Pairs an Item with a count. Used as recipe inputs so each input slot
## can be edited as a single sub-resource in the inspector instead of
## fighting parallel arrays.

@export var item: Item
@export_range(1, 99) var count: int = 1
