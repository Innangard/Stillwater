class_name SmellReducer
extends ConsumableItem
## A consumable that reduces smell on use. Can also grant a temporary
## smell-block (held below a percent of max for some duration) — for
## bath-house style items.
##
## Subclassing ConsumableItem keeps it slot-compatible with all the
## existing consumable plumbing (inventory click, use-from-inventory,
## return-bool-on-success).

@export_group("Smell")
## Flat amount of smell to remove on use.
@export var smell_reduction: float = 30.0
## If > 0, also grants a smell-block effect: smell can't rise above
## block_threshold * max_smell for block_duration seconds.
@export var block_duration: float = 0.0
@export_range(0.0, 1.0) var block_threshold: float = 0.0


func on_use(user: Node) -> bool:
	# Standard consumable behavior first (heal, status grant) so this can
	# also be a heal+deodorant combo if you want.
	var did_something: bool = super(user)

	if smell_reduction > 0.0 and RunState.smell > 0.0:
		RunState.reduce_smell(smell_reduction)
		did_something = true

	if block_duration > 0.0:
		RunState.grant_smell_block(block_threshold, block_duration)
		did_something = true

	return did_something
