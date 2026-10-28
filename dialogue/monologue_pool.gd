class_name MonologuePool
extends Resource
## A pool of in-world monologues for altar carvings (and any future
## interactable that wants to display a random one-off voice).
##
## Each entry is a full Dialogue resource — usually a single-line
## carving in the world bible's voice. When an interactable wants to
## display a monologue, it calls pick_random() to choose one. Picking
## is fully random per call; we don't track which have been seen so a
## player who visits the same altar twice can roll the same monologue
## twice in a row. This is intentional — the monologues are short
## enough that repeats are not disruptive, and over many visits the
## distribution evens out without us needing to track per-session
## state.
##
## Pools are organized by act so that altars in different regions can
## thematically pull from different time-of-game voices:
##   - Act I (South Arch & Marshes): early-game voices, newly-dead souls
##   - Act II (West Arch & Volcano): defiance, world-rot beats
##   - Act III (North Arch & Peaks): tragedy crystallizes
##   - Act IV (NE → Center): final reckoning beats
##
## Currently the four shipped altars (wickbarrow, eastreach, westmoor,
## sundust) all draw from Act I — the player's first arc. Future altars
## in act-specific regions will use the matching higher-act pool.
## Empty pools are valid; pick_random returns null in that case and
## the carving interactable degrades to "no inscription readable."

@export var monologues: Array[Dialogue] = []


## Pick a random monologue. Returns null if the pool is empty.
## Callers should null-check and either skip showing the dialogue or
## display a fallback ("the stone is too weathered to read").
func pick_random() -> Dialogue:
	if monologues.is_empty():
		return null
	return monologues[randi() % monologues.size()]


## Return the set of monologue identities in this pool — the resource
## paths of every Dialogue in the array. Used by KenningManager to
## check pool-level completion against the player's read-set.
##
## resource_path is the right key because:
##   - It's automatically unique per .tres file on disk
##   - It's stable across builds (we don't renumber paths between
##     versions) so saves stay valid across patches
##   - We don't need to add a field to Dialogue just for this — the
##     identity is intrinsic to the file itself
##
## Returns paths as a String Array. Empty pool returns an empty array.
func get_monologue_ids() -> Array[String]:
	var ids: Array[String] = []
	for d in monologues:
		if d != null and d.resource_path != "":
			ids.append(d.resource_path)
	return ids
