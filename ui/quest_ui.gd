extends CanvasLayer
## Autoloaded quest journal UI. Toggled with "toggle_quest_log" (J).
## Shows all active quests with progress, completion status, and an
## abandon button.

var _root: Control
var _panel: PanelContainer
var _title_label: Label
var _quest_list: VBoxContainer
var _scroll: ScrollContainer
var _close_hint: Label
var _empty_label: Label


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	layer = 9
	_build_ui()
	visible = false
	EventBus.quest_progress_updated.connect(_refresh)
	EventBus.quest_accepted.connect(func(_q): _refresh())
	EventBus.quest_completed.connect(func(_q): _refresh())
	EventBus.quest_abandoned.connect(func(_q): _refresh())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_quest_log"):
		_toggle()
		get_viewport().set_input_as_handled()
		return
	if visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("toggle_quest_log"):
			_toggle()
			get_viewport().set_input_as_handled()


func _toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	if visible:
		_refresh()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Dim background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.65)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bg)

	_panel = PanelContainer.new()
	# Anchors match inventory_ui.gd and kennings_ui.gd (0.15/0.85
	# horizontal, 0.06/0.94 vertical) so all three menus fill the same
	# rectangle. The unified MenuTabs strip swaps between them; the
	# panel chrome shouldn't shift as the player tabs.
	_panel.anchor_left = 0.15
	_panel.anchor_right = 0.85
	_panel.anchor_top = 0.06
	_panel.anchor_bottom = 0.94
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.10, 0.09, 0.12, 0.96)
	ps.border_color = Color(0.55, 0.50, 0.42, 0.85)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(6)
	ps.content_margin_left = 0
	ps.content_margin_right = 0
	ps.content_margin_top = 0
	ps.content_margin_bottom = 0
	_panel.add_theme_stylebox_override("panel", ps)
	_root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "QUEST LOG"
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.40))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	# Subtitle in the same flavor-color voice the other two menus use, so
	# all three feel like pages of the same book when the player tabs.
	var subtitle := Label.new()
	subtitle.text = "Tasks taken. Debts owed. Roads still to be walked."
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.58, 0.55, 0.62))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.4, 0.38, 0.34))
	vbox.add_child(sep)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_scroll)

	_quest_list = VBoxContainer.new()
	_quest_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_quest_list)

	_empty_label = Label.new()
	_empty_label.text = "No active quests. Visit a notice board to pick up work."
	_empty_label.add_theme_font_size_override("font_size", 14)
	_empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quest_list.add_child(_empty_label)

	_close_hint = Label.new()
	_close_hint.text = "[J] or [Esc] to close"
	_close_hint.add_theme_font_size_override("font_size", 11)
	_close_hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_close_hint)


func _refresh() -> void:
	# Clear existing entries
	for child in _quest_list.get_children():
		if child != _empty_label:
			child.queue_free()

	var quests: Dictionary = QuestManager.active_quests
	_empty_label.visible = quests.is_empty()
	if quests.is_empty():
		return

	# Sort: story first, then by type, then alphabetical
	var sorted_ids: Array = quests.keys()
	sorted_ids.sort_custom(func(a, b):
		var qa: Quest = quests[a]
		var qb: Quest = quests[b]
		if qa.quest_type != qb.quest_type:
			return qa.quest_type < qb.quest_type
		return qa.quest_name < qb.quest_name
	)

	for quest_id in sorted_ids:
		var quest: Quest = quests[quest_id]
		_add_quest_entry(quest)


func _add_quest_entry(quest: Quest) -> void:
	var entry := PanelContainer.new()
	var entry_style := StyleBoxFlat.new()
	if quest.is_complete:
		entry_style.bg_color = Color(0.12, 0.18, 0.12, 0.8)
		entry_style.border_color = Color(0.4, 0.7, 0.4, 0.6)
	else:
		entry_style.bg_color = Color(0.14, 0.13, 0.16, 0.8)
		entry_style.border_color = Color(0.35, 0.33, 0.38, 0.5)
	entry_style.set_border_width_all(1)
	entry_style.set_corner_radius_all(4)
	entry_style.content_margin_left = 14
	entry_style.content_margin_right = 14
	entry_style.content_margin_top = 10
	entry_style.content_margin_bottom = 10
	entry.add_theme_stylebox_override("panel", entry_style)
	_quest_list.add_child(entry)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	entry.add_child(hbox)

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
	var status := " ✓ READY" if quest.is_complete else ""
	name_label.text = "[color=#%s]%s[/color] %s[color=#66dd66]%s[/color]" % [
		type_color.to_html(false), type_str, quest.quest_name, status]
	info.add_child(name_label)

	# Objective
	var obj_label := Label.new()
	obj_label.text = quest.get_objective_text()
	obj_label.add_theme_font_size_override("font_size", 13)
	obj_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	obj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(obj_label)

	# Reward line
	var reward_label := Label.new()
	reward_label.text = "Reward: %s" % quest.get_reward_text()
	reward_label.add_theme_font_size_override("font_size", 12)
	reward_label.add_theme_color_override("font_color", Color(0.60, 0.55, 0.45))
	info.add_child(reward_label)

	# Turn-in info
	if quest.turn_in_npc != "" and quest.is_complete:
		var turn_in_label := Label.new()
		turn_in_label.text = "Return to: %s" % quest.turn_in_npc
		turn_in_label.add_theme_font_size_override("font_size", 12)
		turn_in_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
		info.add_child(turn_in_label)

	# Buttons column
	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", 4)
	hbox.add_child(btn_col)

	# Turn-in button (if complete and has turn-in NPC as "Notice Board")
	if quest.is_complete and (quest.turn_in_npc == "" or quest.turn_in_npc == "Notice Board"):
		var turn_in_btn := Button.new()
		turn_in_btn.text = "Complete"
		turn_in_btn.add_theme_font_size_override("font_size", 12)
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0.25, 0.55, 0.35)
		btn_style.set_corner_radius_all(3)
		btn_style.content_margin_left = 10
		btn_style.content_margin_right = 10
		btn_style.content_margin_top = 4
		btn_style.content_margin_bottom = 4
		turn_in_btn.add_theme_stylebox_override("normal", btn_style)
		turn_in_btn.pressed.connect(func():
			QuestManager.turn_in_quest(quest.quest_id)
			_refresh()
		)
		btn_col.add_child(turn_in_btn)

	# Abandon button (not for story quests)
	if quest.quest_type != Quest.QuestType.STORY:
		var abandon_btn := Button.new()
		abandon_btn.text = "Abandon"
		abandon_btn.add_theme_font_size_override("font_size", 11)
		var abn_style := StyleBoxFlat.new()
		abn_style.bg_color = Color(0.45, 0.25, 0.25)
		abn_style.set_corner_radius_all(3)
		abn_style.content_margin_left = 8
		abn_style.content_margin_right = 8
		abn_style.content_margin_top = 3
		abn_style.content_margin_bottom = 3
		abandon_btn.add_theme_stylebox_override("normal", abn_style)
		abandon_btn.pressed.connect(func():
			QuestManager.abandon_quest(quest.quest_id)
			_refresh()
		)
		btn_col.add_child(abandon_btn)
