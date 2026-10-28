class_name Quest
extends Resource
## A quest definition. Authored as .tres files or built at runtime by
## the quest board's random generator.
##
## Quest types:
##   STORY   — guaranteed, progresses the narrative (e.g. clear Sprekken)
##   SLAYER  — kill N of enemy type X
##   COLLECT — gather N of item X
##   SOUL    — pay soul currency + fewer reagents
##
## Rewards are a list of QuestReward sub-resources.

enum QuestType { STORY, SLAYER, COLLECT, SOUL }
enum RewardType { SOULS, WEAPON, ARMOR, ITEM }

## Unique identifier. Auto-generated for random quests, hand-set for story.
@export var quest_id: String = ""
@export var quest_name: String = "Untitled Quest"
@export_multiline var description: String = ""
@export var quest_type: QuestType = QuestType.SLAYER
## NPC to return to (display name). Empty = auto-complete.
@export var turn_in_npc: String = ""
## Board that originally posted it (for display).
@export var origin_board: String = ""

@export_group("Objectives")
## For STORY: boss name that completes this quest when defeated (empty = not boss-gated)
@export var target_boss: String = ""
## For SLAYER: enemy scene path (e.g. "res://enemies/skeleton_toss.tscn")
@export var target_enemy_path: String = ""
## For SLAYER: enemy display name (shown in UI)
@export var target_enemy_name: String = ""
## For SLAYER / COLLECT: how many
@export var target_count: int = 0
## For COLLECT: item resource path
@export var target_item_path: String = ""
## For COLLECT: item display name
@export var target_item_name: String = ""
## For SOUL: soul cost to complete
@export var soul_cost: int = 0

@export_group("Rewards")
@export var reward_souls: int = 0
## Weapon/Armor/Item reward paths (loaded on completion)
@export var reward_item_paths: Array[String] = []
## Display names for reward items
@export var reward_item_names: Array[String] = []

## Runtime tracking (not saved in .tres — managed by QuestManager)
var current_count: int = 0
var is_complete: bool = false
var is_turned_in: bool = false


func get_objective_text() -> String:
	match quest_type:
		QuestType.STORY:
			return description
		QuestType.SLAYER:
			return "Slay %d %s (%d/%d)" % [target_count, target_enemy_name,
				current_count, target_count]
		QuestType.COLLECT:
			return "Collect %d %s (%d/%d)" % [target_count, target_item_name,
				current_count, target_count]
		QuestType.SOUL:
			var parts: Array[String] = []
			if target_item_path != "":
				parts.append("Gather %d %s (%d/%d)" % [target_count, target_item_name,
					current_count, target_count])
			if soul_cost > 0:
				parts.append("Pay %d souls" % soul_cost)
			return " — ".join(parts)
	return description


func get_reward_text() -> String:
	var parts: Array[String] = []
	if reward_souls > 0:
		parts.append("%d souls" % reward_souls)
	for rn in reward_item_names:
		parts.append(rn)
	if parts.is_empty():
		return "None"
	return ", ".join(parts)


func check_completion() -> bool:
	if is_complete:
		return true
	match quest_type:
		QuestType.SLAYER:
			is_complete = current_count >= target_count
		QuestType.COLLECT:
			is_complete = current_count >= target_count
		QuestType.SOUL:
			var item_ok := true
			if target_item_path != "":
				item_ok = current_count >= target_count
			is_complete = item_ok
		QuestType.STORY:
			pass  # Story quests are completed by flag
	return is_complete


func to_save_dict() -> Dictionary:
	return {
		"quest_id": quest_id,
		"current_count": current_count,
		"is_complete": is_complete,
		"is_turned_in": is_turned_in,
	}


func load_from_save(data: Dictionary) -> void:
	current_count = data.get("current_count", 0)
	is_complete = data.get("is_complete", false)
	is_turned_in = data.get("is_turned_in", false)
