extends Node
## Global signal hub. Anything in the game can emit/listen here without
## holding direct references to other systems.
##
## Rule of thumb: if more than one system needs to know about an event,
## route it through here. If only one system cares, use a local signal.
##
## Every signal here is "unused in this file" by definition — emitters
## and listeners live elsewhere. Disable the warning file-wide.
@warning_ignore_start("unused_signal")

# --- Combat ---
signal damage_dealt(target: Node, amount: float, info: Dictionary)
signal entity_died(entity: Node)
## Like entity_died, but carries the damage_info that landed the killing
## blow. Subscribers that need to know HOW something died (weapon category,
## element, source) use this. Both signals fire for every death; pick
## whichever your subscriber needs.
signal enemy_killed(entity: Node, kill_info: Dictionary)

# --- Player ---
signal player_spawned(player: Node)
signal player_died
signal player_health_changed(current: float, maximum: float)
## Detection signature changes — fired by player/RunState so HUD updates.
signal noise_changed(current: float, maximum: float)
signal smell_changed(current: float, maximum: float)
## Player-specific status events. Re-emitted by Player from its
## StatusEffectComponent so the HUD doesn't need a direct reference.
signal player_status_applied(effect: Resource, stacks: int)
signal player_status_removed(effect: Resource)
## Fired when any entity takes damage. The HUD uses this to spawn
## floating damage numbers; other systems can use it for screen shake,
## kill attribution, etc.
signal damage_dealt_visual(target: Node, amount: float, info: Dictionary)

# --- World / runs ---
signal arch_activated(arch_id: String)
signal entered_dungeon(dungeon_id: String)
signal exited_dungeon(dungeon_id: String, completed: bool)
signal run_started(is_restore: bool) # false = fresh run (death/new game), true = save restore
signal run_ended(cause: String) # "death", "complete"

# --- Inventory / progression ---
signal item_picked_up(item: Resource)
signal weapon_equipped(weapon: Resource, slot: String)
signal armor_equipped(armor: Resource)
signal currency_changed(new_amount: int)
signal story_flag_set(flag: String, value: Variant)
signal inventory_changed

# --- UI ---
signal request_dialogue(npc_id: String, dialogue_id: String)
signal request_screen_shake(strength: float, duration: float)

# --- Lore / Carvings ---
## Fired when the player reads a monologue at an AltarCarving (or any
## future carving-style interactable). `monologue_id` is the unique
## identity of the read monologue — by convention, the resource_path of
## the Dialogue resource, which is stable across builds and unique per
## file. KenningManager listens for this to track read-progress against
## each act pool's full set, gating the "lorebearer" kennings.
##
## Why fire the signal regardless of whether this is the player's first
## time reading this specific monologue: the KenningManager's listener
## deduplicates via the Set stored in story_flags, so re-reading the
## same monologue is harmless. Centralizing dedupe in the listener keeps
## the firing side simple and means future systems that care about
## "monologues read" don't each need their own dedupe logic.
signal monologue_read(monologue_id: String)

# --- Map ---
signal map_graph_rebuilt
signal map_section_revealed(flag: String)

# --- Boss ---
signal boss_engaged(boss_name: String, current_hp: float, max_hp: float)
signal boss_health_changed(current_hp: float, max_hp: float)
signal boss_phase_changed(phase: int)
signal boss_defeated(boss_name: String)
## Fired when a boss's stagger meter changes. `threshold` is the
## per-boss stagger trigger (when current reaches threshold, the boss
## takes a long stun). HUD listens to draw the stagger bar.
signal boss_stagger_changed(current: float, threshold: float)
## Fired when any enemy enters STUNNED state (from a wind-up interrupt).
## Used for hit-stop / screen-shake feedback so the player feels the punish.
signal enemy_staggered(enemy: Node, duration: float, is_long_stun: bool)
## Fired when the player dodges a hostile projectile or attack via the
## i-frame dash window. HUD plays a brief flash; gameplay refunds a
## fraction of cooldown to encourage skilled play.
signal player_perfect_dodge
## Weapon set swap (Q key). Fired when the swap animation begins and
## when it completes. HUD uses these to animate the prepared-slot display.
signal weapon_swap_started
signal weapon_swap_completed

# --- Quests ---
signal quest_accepted(quest: Quest)
signal quest_progress_updated
signal quest_completed(quest: Quest)
signal quest_abandoned(quest: Quest)

# --- Kennings (meta-progression titles) ---
## Fires when a previously-locked kenning becomes available. The UI uses
## this to refresh its catalog list and the Toast shown is handled inside
## KenningManager (so the message can include the display name without the
## listener needing to look it up).
signal kenning_unlocked(kenning_id: String)
## Fires when a kenning is added to or removed from the player's equipped
## loadout. The HUD/player listen so live stat caps (max HP, speed) update
## without waiting for the next run.
signal kenning_equipped(kenning_id: String)
signal kenning_unequipped(kenning_id: String)

# --- Interactables tracking ---
## Count of interactable objects (arches, NPCs, pickups, workbenches, etc.)
## currently within range of the player. Used so the inventory key (E) can
## fall back to opening the inventory when nothing is in range. Each
## interactable calls notify_interactable_entered/exited as the player
## enters/leaves its trigger area.
var interactables_in_range: int = 0


func notify_interactable_entered() -> void:
	interactables_in_range += 1


func notify_interactable_exited() -> void:
	interactables_in_range = maxi(0, interactables_in_range - 1)


## Called when a scene transition is about to happen so the counter doesn't
## leak across rooms — _exit_tree on interactables doesn't always fire
## reliably during scene swaps.
func reset_interactables() -> void:
	interactables_in_range = 0


func has_interactable_in_range() -> bool:
	return interactables_in_range > 0
