extends Node
## Autoloaded quest manager. Tracks active and completed quests,
## listens for kill/pickup events to update progress, and handles
## quest completion and reward distribution.
##
## Quests persist across death (stored in GameState). The player keeps
## quest progress even when they die — only inventory resets.

# --- Active quest storage ---
## quest_id → Quest resource (with runtime state)
var active_quests: Dictionary = {}
## quest_ids that have been turned in (so boards don't re-offer them)
var completed_quest_ids: Dictionary = {}
## quest_ids that have been offered and declined or are currently active
## (prevents re-rolling the same random quest within a run)
var seen_quest_ids: Dictionary = {}

## Maximum active quests at once.
const MAX_ACTIVE_QUESTS := 8


func _ready() -> void:
	EventBus.entity_died.connect(_on_entity_died)
	EventBus.item_picked_up.connect(_on_item_picked_up)
	EventBus.run_started.connect(_on_run_started.unbind(1))
	EventBus.boss_defeated.connect(_on_boss_defeated)


func on_scene_entered(scene_path: String) -> void:
	# Check story quests triggered by entering a scene
	if scene_path.find("nasus_city") != -1:
		_complete_story_quest("story_reach_nasus")


func _on_run_started() -> void:
	# Re-evaluate collect quest progress against current inventory
	# (inventory resets on death, so collect progress resets too)
	for quest_id in active_quests:
		var q: Quest = active_quests[quest_id]
		if q.quest_type == Quest.QuestType.COLLECT or q.quest_type == Quest.QuestType.SOUL:
			if q.target_item_path != "":
				var item: Item = load(q.target_item_path)
				if item:
					q.current_count = RunState.count_in_inventory(item)
				else:
					q.current_count = 0
			q.is_complete = false
			q.check_completion()
	EventBus.quest_progress_updated.emit()


# ============================================================================
# QUEST LIFECYCLE
# ============================================================================

func accept_quest(quest: Quest) -> bool:
	if active_quests.size() >= MAX_ACTIVE_QUESTS:
		Toast.show_message("Quest log full (%d/%d)" % [active_quests.size(), MAX_ACTIVE_QUESTS],
			Color(0.9, 0.5, 0.3))
		return false
	if active_quests.has(quest.quest_id):
		return false
	active_quests[quest.quest_id] = quest
	seen_quest_ids[quest.quest_id] = true

	# Initialize collect quest progress from current inventory
	if quest.quest_type == Quest.QuestType.COLLECT or quest.quest_type == Quest.QuestType.SOUL:
		if quest.target_item_path != "":
			var item: Item = load(quest.target_item_path)
			if item:
				quest.current_count = RunState.count_in_inventory(item)
			quest.check_completion()

	EventBus.quest_accepted.emit(quest)
	Toast.show_message("Quest accepted: %s" % quest.quest_name, Color(0.4, 0.8, 0.5))
	_save_quests()
	return true


func abandon_quest(quest_id: String) -> void:
	if not active_quests.has(quest_id):
		return
	var quest: Quest = active_quests[quest_id]
	active_quests.erase(quest_id)
	EventBus.quest_abandoned.emit(quest)
	Toast.show_message("Quest abandoned: %s" % quest.quest_name, Color(0.7, 0.5, 0.3))
	_save_quests()


func turn_in_quest(quest_id: String) -> bool:
	if not active_quests.has(quest_id):
		return false
	var quest: Quest = active_quests[quest_id]
	if not quest.is_complete:
		return false

	# For SOUL quests: spend the souls
	if quest.quest_type == Quest.QuestType.SOUL and quest.soul_cost > 0:
		if not GameState.spend_currency(quest.soul_cost):
			Toast.show_message("Not enough souls (%d needed)" % quest.soul_cost,
				Color(0.9, 0.4, 0.4))
			return false

	# For COLLECT / SOUL quests: consume the items from inventory
	if quest.target_item_path != "" and quest.target_count > 0:
		if quest.quest_type == Quest.QuestType.COLLECT or quest.quest_type == Quest.QuestType.SOUL:
			var item: Item = load(quest.target_item_path)
			if item:
				for i in quest.target_count:
					RunState.remove_one_from_inventory(item)

	# Grant rewards
	if quest.reward_souls > 0:
		GameState.add_currency(quest.reward_souls)
	for path in quest.reward_item_paths:
		var reward_res: Resource = load(path)
		if reward_res is Item:
			RunState.add_to_inventory(reward_res)

	quest.is_turned_in = true
	active_quests.erase(quest_id)
	completed_quest_ids[quest_id] = true
	# Set a story flag that listeners (e.g. KenningManager) can watch for
	# without needing to know anything about the quest system. Convention:
	# "quest_<quest_id>". This is the single unified channel through which
	# both quest completions and boss kills (boss_dead_<id>) unlock kennings.
	GameState.set_flag("quest_" + quest_id, true)
	EventBus.quest_completed.emit(quest)
	Toast.show_message("Quest complete: %s" % quest.quest_name, Color(0.5, 0.9, 0.4))
	_save_quests()
	return true


func is_quest_active(quest_id: String) -> bool:
	return active_quests.has(quest_id)


func is_quest_completed(quest_id: String) -> bool:
	return completed_quest_ids.has(quest_id)


func has_seen_quest(quest_id: String) -> bool:
	return seen_quest_ids.has(quest_id) or completed_quest_ids.has(quest_id)


# ============================================================================
# PROGRESS TRACKING
# ============================================================================

func _on_entity_died(entity: Node) -> void:
	if not entity.has_method("get") or not ("scene_file_path" in entity):
		# Try the enemy scene path from the entity's owner or metadata
		pass
	var enemy_scene: String = ""
	if entity.has_meta("source_scene"):
		enemy_scene = entity.get_meta("source_scene")
	elif entity.scene_file_path != "":
		enemy_scene = entity.scene_file_path

	if enemy_scene == "":
		return

	for quest_id in active_quests:
		var q: Quest = active_quests[quest_id]
		if q.quest_type == Quest.QuestType.SLAYER and not q.is_complete:
			if q.target_enemy_path == enemy_scene:
				q.current_count += 1
				q.check_completion()
				EventBus.quest_progress_updated.emit()
				if q.is_complete:
					Toast.show_message("Quest ready: %s" % q.quest_name,
						Color(0.4, 0.9, 0.5))


func _on_item_picked_up(item: Item) -> void:
	if item == null:
		return
	var item_path: String = item.resource_path
	for quest_id in active_quests:
		var q: Quest = active_quests[quest_id]
		if (q.quest_type == Quest.QuestType.COLLECT or q.quest_type == Quest.QuestType.SOUL) \
				and not q.is_complete and q.target_item_path == item_path:
			q.current_count = RunState.count_in_inventory(item)
			q.check_completion()
			EventBus.quest_progress_updated.emit()
			if q.is_complete:
				Toast.show_message("Quest ready: %s" % q.quest_name,
					Color(0.4, 0.9, 0.5))


func _on_boss_defeated(boss_name: String) -> void:
	for quest_id in active_quests:
		var q: Quest = active_quests[quest_id]
		if q.quest_type == Quest.QuestType.STORY and not q.is_complete:
			if q.target_boss != "" and q.target_boss == boss_name:
				q.is_complete = true
				q.current_count = 1
				EventBus.quest_progress_updated.emit()
				Toast.show_message("Quest ready: %s" % q.quest_name,
					Color(0.5, 0.9, 0.4))


func _complete_story_quest(quest_id: String) -> void:
	if not active_quests.has(quest_id):
		return
	var q: Quest = active_quests[quest_id]
	if q.is_complete:
		return
	q.is_complete = true
	q.current_count = q.target_count
	EventBus.quest_progress_updated.emit()
	Toast.show_message("Quest ready: %s" % q.quest_name, Color(0.5, 0.9, 0.4))


## Called by NPC dialogue when player talks to the turn-in NPC.
func check_turn_ins_for_npc(npc_name: String) -> Array[Quest]:
	var completed: Array[Quest] = []
	for quest_id in active_quests:
		var q: Quest = active_quests[quest_id]
		if q.is_complete and not q.is_turned_in and q.turn_in_npc == npc_name:
			completed.append(q)
	return completed


# ============================================================================
# SAVE / LOAD
# ============================================================================

func _save_quests() -> void:
	var save_data: Array = []
	for quest_id in active_quests:
		var q: Quest = active_quests[quest_id]
		var d := q.to_save_dict()
		# Also save the quest definition so random quests can be reconstructed
		d["quest_name"] = q.quest_name
		d["description"] = q.description
		d["quest_type"] = q.quest_type
		d["target_enemy_path"] = q.target_enemy_path
		d["target_enemy_name"] = q.target_enemy_name
		d["target_count"] = q.target_count
		d["target_item_path"] = q.target_item_path
		d["target_item_name"] = q.target_item_name
		d["soul_cost"] = q.soul_cost
		d["reward_souls"] = q.reward_souls
		d["reward_item_paths"] = q.reward_item_paths
		d["reward_item_names"] = q.reward_item_names
		d["turn_in_npc"] = q.turn_in_npc
		d["origin_board"] = q.origin_board
		save_data.append(d)
	GameState.set_flag("_quest_active_data", save_data)
	GameState.set_flag("_quest_completed_ids", completed_quest_ids.keys())


func load_quests() -> void:
	active_quests.clear()
	completed_quest_ids.clear()

	var completed_arr: Array = GameState.get_flag("_quest_completed_ids", [])
	for cid in completed_arr:
		completed_quest_ids[cid] = true

	var save_data: Array = GameState.get_flag("_quest_active_data", [])
	for d in save_data:
		var q := Quest.new()
		q.quest_id = d.get("quest_id", "")
		q.quest_name = d.get("quest_name", "")
		q.description = d.get("description", "")
		q.quest_type = d.get("quest_type", 0)
		q.target_enemy_path = d.get("target_enemy_path", "")
		q.target_enemy_name = d.get("target_enemy_name", "")
		q.target_count = d.get("target_count", 0)
		q.target_item_path = d.get("target_item_path", "")
		q.target_item_name = d.get("target_item_name", "")
		q.soul_cost = d.get("soul_cost", 0)
		q.reward_souls = d.get("reward_souls", 0)
		q.reward_item_paths = d.get("reward_item_paths", [])
		q.reward_item_names = d.get("reward_item_names", [])
		q.turn_in_npc = d.get("turn_in_npc", "")
		q.origin_board = d.get("origin_board", "")
		q.load_from_save(d)
		if not q.is_turned_in:
			active_quests[q.quest_id] = q
			seen_quest_ids[q.quest_id] = true
