class_name QuestBoard
extends Node2D
## A notice board players can E-press to browse and accept quests.
##
## Opens a custom modal panel with per-quest accept buttons. Quests
## already accepted or completed are hidden.

@export var board_name: String = "Notice Board"
@export var guaranteed_quest_paths: Array[String] = []
@export var random_quest_count: int = 3

@export_group("Random Quest Pools")
@export var slayer_enemy_paths: Array[String] = []
@export var slayer_enemy_names: Array[String] = []
@export var collect_item_paths: Array[String] = []
@export var collect_item_names: Array[String] = []

@export_group("Reward Pools")
@export var reward_weapon_paths: Array[String] = []
@export var reward_weapon_names: Array[String] = []
@export var reward_armor_paths: Array[String] = []
@export var reward_armor_names: Array[String] = []
@export var reward_rune_paths: Array[String] = []
@export var reward_rune_names: Array[String] = []

@onready var area: Area2D = $Area2D
var _player_in_range: Player = null
var _bob_t: float = 0.0
var _generated_quests: Array[Quest] = []
var _generated_for_seed: int = -1
var _ui_layer: CanvasLayer = null
var _ui_open: bool = false


func _ready() -> void:
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	_bob_t = randf() * TAU


func _process(delta: float) -> void:
	_bob_t += delta
	queue_redraw()
	if _player_in_range and Input.is_action_just_pressed("interact"):
		if _ui_open:
			_close_ui()
		else:
			_open()


func _on_body_entered(body: Node) -> void:
	if body is Player:
		_player_in_range = body
		EventBus.notify_interactable_entered()

func _on_body_exited(body: Node) -> void:
	if body == _player_in_range:
		_player_in_range = null
		EventBus.notify_interactable_exited()


# ============================================================================
# QUEST GENERATION
# ============================================================================

func _ensure_quests_generated() -> void:
	if _generated_for_seed == RunState.world_seed:
		return
	_generated_for_seed = RunState.world_seed
	_generated_quests.clear()

	for path in guaranteed_quest_paths:
		var q: Quest = load(path)
		if q and not QuestManager.is_quest_completed(q.quest_id):
			_generated_quests.append(q)

	var rng := RandomNumberGenerator.new()
	rng.seed = RunState.world_seed + board_name.hash()

	for i in random_quest_count:
		var q := _generate_random_quest(rng, i)
		if q != null and not QuestManager.is_quest_completed(q.quest_id) \
				and not QuestManager.is_quest_active(q.quest_id):
			_generated_quests.append(q)


func _generate_random_quest(rng: RandomNumberGenerator, index: int) -> Quest:
	var roll := rng.randf()
	var quest_type: Quest.QuestType

	if roll < 0.40 and not slayer_enemy_paths.is_empty():
		quest_type = Quest.QuestType.SLAYER
	elif roll < 0.75 and not collect_item_paths.is_empty():
		quest_type = Quest.QuestType.COLLECT
	elif not collect_item_paths.is_empty():
		quest_type = Quest.QuestType.SOUL
	elif not slayer_enemy_paths.is_empty():
		quest_type = Quest.QuestType.SLAYER
	else:
		return null

	var q := Quest.new()
	q.quest_id = "%s_random_%d_%d" % [board_name.to_lower().replace(" ", "_"),
		RunState.world_seed, index]
	q.origin_board = board_name
	q.turn_in_npc = "Notice Board"
	q.quest_type = quest_type

	match quest_type:
		Quest.QuestType.SLAYER:
			var ei := rng.randi_range(0, slayer_enemy_paths.size() - 1)
			q.target_enemy_path = slayer_enemy_paths[ei]
			q.target_enemy_name = slayer_enemy_names[ei] if ei < slayer_enemy_names.size() else "Enemy"
			q.target_count = rng.randi_range(3, 8)
			q.quest_name = "Hunt: %s ×%d" % [q.target_enemy_name, q.target_count]
			q.description = "Eliminate %d %s and return to the notice board." % [
				q.target_count, q.target_enemy_name]
			q.reward_souls = q.target_count * rng.randi_range(8, 15)

		Quest.QuestType.COLLECT:
			var ci := rng.randi_range(0, collect_item_paths.size() - 1)
			q.target_item_path = collect_item_paths[ci]
			q.target_item_name = collect_item_names[ci] if ci < collect_item_names.size() else "Item"
			q.target_count = rng.randi_range(2, 5)
			q.quest_name = "Gather: %s ×%d" % [q.target_item_name, q.target_count]
			q.description = "Collect %d %s and return to the notice board." % [
				q.target_count, q.target_item_name]
			q.reward_souls = q.target_count * rng.randi_range(10, 20)

		Quest.QuestType.SOUL:
			var ci := rng.randi_range(0, collect_item_paths.size() - 1)
			q.target_item_path = collect_item_paths[ci]
			q.target_item_name = collect_item_names[ci] if ci < collect_item_names.size() else "Item"
			q.target_count = rng.randi_range(1, 2)
			q.soul_cost = rng.randi_range(20, 50)
			q.quest_name = "Offering: %s" % q.target_item_name
			q.description = "Bring %d %s and pay %d souls as an offering." % [
				q.target_count, q.target_item_name, q.soul_cost]

	if rng.randf() < 0.4:
		_add_random_reward(q, rng)

	return q


func _add_random_reward(q: Quest, rng: RandomNumberGenerator) -> void:
	var all_paths: Array[String] = []
	var all_names: Array[String] = []
	all_paths.append_array(reward_weapon_paths)
	all_names.append_array(reward_weapon_names)
	all_paths.append_array(reward_armor_paths)
	all_names.append_array(reward_armor_names)
	all_paths.append_array(reward_rune_paths)
	all_names.append_array(reward_rune_names)
	if all_paths.is_empty():
		return
	var ri := rng.randi_range(0, all_paths.size() - 1)
	q.reward_item_paths.append(all_paths[ri])
	q.reward_item_names.append(all_names[ri] if ri < all_names.size() else "Item")


# ============================================================================
# BOARD UI
# ============================================================================

func _open() -> void:
	_ensure_quests_generated()

	# Auto-turn-in completed quests first
	var turn_ins := QuestManager.check_turn_ins_for_npc("Notice Board")
	for q in turn_ins:
		QuestManager.turn_in_quest(q.quest_id)

	# Gather available quests
	var available: Array[Quest] = []
	for q in _generated_quests:
		if not QuestManager.is_quest_active(q.quest_id) \
				and not QuestManager.is_quest_completed(q.quest_id):
			available.append(q)

	if available.is_empty() and turn_ins.is_empty():
		Toast.show_message("No new postings.", Color(0.7, 0.7, 0.7))
		return

	if available.is_empty() and not turn_ins.is_empty():
		# Already turned in above, just notify
		return

	_build_board_ui(available)


func _build_board_ui(available: Array[Quest]) -> void:
	if _ui_layer:
		_ui_layer.queue_free()

	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 8
	_ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(root)

	# Dim background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)

	# Panel
	var panel := PanelContainer.new()
	panel.anchor_left = 0.15
	panel.anchor_right = 0.85
	panel.anchor_top = 0.06
	panel.anchor_bottom = 0.94
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.10, 0.09, 0.12, 0.96)
	ps.border_color = Color(0.55, 0.45, 0.30, 0.85)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(6)
	ps.content_margin_left = 0
	ps.content_margin_right = 0
	ps.content_margin_top = 0
	ps.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", ps)
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Title row
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	var title := Label.new()
	title.text = board_name.to_upper()
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.40))
	title_row.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.add_theme_font_size_override("font_size", 14)
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.45, 0.25, 0.25)
	close_style.set_corner_radius_all(3)
	close_style.content_margin_left = 12
	close_style.content_margin_right = 12
	close_style.content_margin_top = 4
	close_style.content_margin_bottom = 4
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.pressed.connect(_close_ui)
	title_row.add_child(close_btn)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.4, 0.35, 0.28))
	vbox.add_child(sep)

	# Flavor text
	var flavor := Label.new()
	flavor.text = "Postings tacked up with iron nails. Some are fresh. Some have been here longer than anyone living."
	flavor.add_theme_font_size_override("font_size", 13)
	flavor.add_theme_color_override("font_color", Color(0.55, 0.55, 0.50))
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(flavor)

	# Scroll area for quests
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var quest_list := VBoxContainer.new()
	quest_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_list.add_theme_constant_override("separation", 8)
	scroll.add_child(quest_list)

	# Quest entries
	for q in available:
		_add_board_quest_entry(quest_list, q)

	# Bottom hint
	var hint := Label.new()
	hint.text = "[E] or [Esc] to close"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	get_tree().paused = true
	_ui_open = true


func _add_board_quest_entry(parent: VBoxContainer, quest: Quest) -> void:
	var entry := PanelContainer.new()
	var es := StyleBoxFlat.new()
	es.bg_color = Color(0.14, 0.13, 0.16, 0.8)
	es.border_color = Color(0.35, 0.33, 0.38, 0.5)
	es.set_border_width_all(1)
	es.set_corner_radius_all(4)
	es.content_margin_left = 14
	es.content_margin_right = 14
	es.content_margin_top = 10
	es.content_margin_bottom = 10
	entry.add_theme_stylebox_override("panel", es)
	parent.add_child(entry)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	entry.add_child(hbox)

	# Quest info
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	hbox.add_child(info)

	# Type badge + name
	var type_str := ""
	var type_color := Color.WHITE
	match quest.quest_type:
		Quest.QuestType.STORY:
			type_str = "[STORY]"
			type_color = Color(0.95, 0.75, 0.30)
		Quest.QuestType.SLAYER:
			type_str = "[SLAYER]"
			type_color = Color(0.85, 0.40, 0.35)
		Quest.QuestType.COLLECT:
			type_str = "[COLLECT]"
			type_color = Color(0.45, 0.70, 0.85)
		Quest.QuestType.SOUL:
			type_str = "[SOUL]"
			type_color = Color(0.70, 0.55, 0.85)

	var name_label := RichTextLabel.new()
	name_label.bbcode_enabled = true
	name_label.fit_content = true
	name_label.scroll_active = false
	name_label.add_theme_font_size_override("normal_font_size", 15)
	name_label.text = "[color=#%s]%s[/color] %s" % [
		type_color.to_html(false), type_str, quest.quest_name]
	info.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = quest.description
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc_label)

	var reward_label := Label.new()
	reward_label.text = "Reward: %s" % quest.get_reward_text()
	reward_label.add_theme_font_size_override("font_size", 12)
	reward_label.add_theme_color_override("font_color", Color(0.60, 0.55, 0.45))
	info.add_child(reward_label)

	# Accept button
	var accept_btn := Button.new()
	accept_btn.text = "Accept"
	accept_btn.add_theme_font_size_override("font_size", 14)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.25, 0.55, 0.35)
	btn_style.set_corner_radius_all(4)
	btn_style.content_margin_left = 16
	btn_style.content_margin_right = 16
	btn_style.content_margin_top = 8
	btn_style.content_margin_bottom = 8
	accept_btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.30, 0.65, 0.42)
	btn_hover.set_corner_radius_all(4)
	btn_hover.content_margin_left = 16
	btn_hover.content_margin_right = 16
	btn_hover.content_margin_top = 8
	btn_hover.content_margin_bottom = 8
	accept_btn.add_theme_stylebox_override("hover", btn_hover)

	accept_btn.pressed.connect(func():
		if QuestManager.accept_quest(quest):
			# Grey out this entry
			accept_btn.text = "Accepted ✓"
			accept_btn.disabled = true
			var dis_style := StyleBoxFlat.new()
			dis_style.bg_color = Color(0.25, 0.35, 0.28)
			dis_style.set_corner_radius_all(4)
			dis_style.content_margin_left = 16
			dis_style.content_margin_right = 16
			dis_style.content_margin_top = 8
			dis_style.content_margin_bottom = 8
			accept_btn.add_theme_stylebox_override("disabled", dis_style)
			entry.modulate = Color(0.7, 0.7, 0.7, 0.7)
	)
	hbox.add_child(accept_btn)


func _close_ui() -> void:
	if _ui_layer:
		_ui_layer.queue_free()
		_ui_layer = null
	get_tree().paused = false
	_ui_open = false


func _input(event: InputEvent) -> void:
	if _ui_open and event.is_action_pressed("pause"):
		_close_ui()
		get_viewport().set_input_as_handled()


# ============================================================================
# DRAW
# ============================================================================

func _draw() -> void:
	draw_rect(Rect2(-3, -8, 6, 36), Color(0.32, 0.22, 0.16))
	draw_rect(Rect2(-32, -52, 64, 48), Color(0.45, 0.32, 0.22))
	draw_rect(Rect2(-32, -52, 64, 48), Color(0.20, 0.14, 0.10), false, 1.5)

	for i in 3:
		var x = -22 + i * 14
		var y_off = sin(_bob_t * 0.8 + i * 1.5) * 0.5
		draw_rect(Rect2(x, -42 + y_off, 10, 14), Color(0.92, 0.88, 0.74))

	_ensure_quests_generated()
	var has_available := false
	for q in _generated_quests:
		if not QuestManager.is_quest_active(q.quest_id) \
				and not QuestManager.is_quest_completed(q.quest_id):
			has_available = true
			break
	var turn_ins := QuestManager.check_turn_ins_for_npc("Notice Board")

	var font := ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(-60, -64), board_name,
			HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color(1, 1, 1, 0.85))
		if turn_ins.size() > 0:
			var alpha := 0.6 + sin(_bob_t * 3.0) * 0.4
			draw_circle(Vector2(28, -48), 6.0, Color(0.9, 0.75, 0.2, alpha))
			draw_string(font, Vector2(21, -43), "!", HORIZONTAL_ALIGNMENT_CENTER,
				14, 12, Color(0.1, 0.05, 0.0))
		elif has_available:
			draw_circle(Vector2(28, -48), 5.0, Color(0.9, 0.85, 0.3, 0.7))
		if _player_in_range:
			draw_string(font, Vector2(-50, 46), "[E] read",
				HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Color(1.0, 0.95, 0.4))
