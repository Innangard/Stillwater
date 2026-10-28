extends CanvasLayer
## Autoloaded crafting UI. Opened by Workbench.open(self). Pauses the
## game and lists this workbench's recipes with colored category badges.

signal crafting_closed

const COLOR_SATISFIED := Color(0.40, 0.80, 0.45, 1.0)
const COLOR_MISSING   := Color(0.85, 0.35, 0.35, 1.0)

const CATEGORY_COLORS := {
	"weapon":   Color(0.85, 0.40, 0.35),
	"armor":    Color(0.45, 0.70, 0.85),
	"purchase": Color(0.90, 0.75, 0.30),
	"rune":     Color(0.70, 0.55, 0.85),
	"item":     Color(0.55, 0.80, 0.50),
}

var _root: Control
var _panel: PanelContainer
var _title_label: Label
var _recipe_list: VBoxContainer
var _current_station_name: String = ""
var _current_recipes: Array[Recipe] = []

# Floating tooltip — follows cursor, replaces the old static detail panel.
const TOOLTIP_MAX_WIDTH := 340.0
const TOOLTIP_OFFSET := Vector2(16, 16)
var _tooltip_panel: PanelContainer
var _tooltip_label: RichTextLabel


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	layer = 11
	_build_ui()
	visible = false
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.weapon_equipped.connect(_on_weapon_equipped.unbind(2))
	EventBus.currency_changed.connect(_on_currency_changed.unbind(1))


func _process(_delta: float) -> void:
	if not visible:
		return
	if _tooltip_panel.visible:
		_position_tooltip()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("toggle_inventory"):
		_close()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()


func open_station(stn_name: String, recipe_list: Array[Recipe]) -> void:
	_current_station_name = stn_name
	_current_recipes = recipe_list
	_title_label.text = stn_name
	visible = true
	get_tree().paused = true
	_refresh()

func open(workbench: Workbench) -> void:
	open_station(workbench.station_name, workbench.recipes)

func _close() -> void:
	_hide_tooltip()
	visible = false
	get_tree().paused = false
	_current_station_name = ""
	_current_recipes = []
	crafting_closed.emit()


func _on_inventory_changed() -> void:
	if visible: _refresh()
func _on_weapon_equipped() -> void:
	if visible: _refresh()
func _on_currency_changed() -> void:
	if visible: _refresh()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.12
	_panel.anchor_right = 0.88
	_panel.anchor_top = 0.06
	_panel.anchor_bottom = 0.94
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.10, 0.09, 0.12, 0.96)
	ps.border_color = Color(0.55, 0.50, 0.42, 0.85)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", ps)
	_root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Title row
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	_title_label = Label.new()
	_title_label.text = "Workbench"
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.40))
	title_row.add_child(_title_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.add_theme_font_size_override("font_size", 13)
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.40, 0.25, 0.25)
	cs.set_corner_radius_all(3)
	cs.content_margin_left = 12
	cs.content_margin_right = 12
	cs.content_margin_top = 4
	cs.content_margin_bottom = 4
	close_btn.add_theme_stylebox_override("normal", cs)
	var ch := StyleBoxFlat.new()
	ch.bg_color = Color(0.55, 0.30, 0.30)
	ch.set_corner_radius_all(3)
	ch.content_margin_left = 12
	ch.content_margin_right = 12
	ch.content_margin_top = 4
	ch.content_margin_bottom = 4
	close_btn.add_theme_stylebox_override("hover", ch)
	close_btn.pressed.connect(_close)
	title_row.add_child(close_btn)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.4, 0.38, 0.34))
	vbox.add_child(sep)

	# Recipe list scroll
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_recipe_list = VBoxContainer.new()
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_recipe_list)

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator", Color(0.4, 0.38, 0.34))
	vbox.add_child(sep2)

	# Bottom hint
	var hint := Label.new()
	hint.text = "[E] or [Esc] to close   ·   hover for details"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	# --- Floating tooltip ---
	_build_tooltip()


func _build_tooltip() -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.z_index = 100
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.08, 0.07, 0.10, 0.96)
	ts.border_color = Color(0.55, 0.50, 0.42, 0.90)
	ts.set_border_width_all(2)
	ts.set_corner_radius_all(5)
	ts.content_margin_left = 12
	ts.content_margin_right = 12
	ts.content_margin_top = 10
	ts.content_margin_bottom = 10
	_tooltip_panel.add_theme_stylebox_override("panel", ts)
	add_child(_tooltip_panel)

	_tooltip_label = RichTextLabel.new()
	_tooltip_label.bbcode_enabled = true
	_tooltip_label.fit_content = true
	_tooltip_label.scroll_active = false
	_tooltip_label.custom_minimum_size = Vector2(TOOLTIP_MAX_WIDTH, 0)
	_tooltip_label.add_theme_font_size_override("normal_font_size", 12)
	_tooltip_label.add_theme_color_override("default_color", Color(0.78, 0.78, 0.78))
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.add_child(_tooltip_label)


func _position_tooltip() -> void:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var tip_size: Vector2 = _tooltip_panel.size
	var pos: Vector2 = mouse_pos + TOOLTIP_OFFSET
	if pos.x + tip_size.x > vp_size.x:
		pos.x = mouse_pos.x - tip_size.x - TOOLTIP_OFFSET.x
	if pos.y + tip_size.y > vp_size.y:
		pos.y = mouse_pos.y - tip_size.y - TOOLTIP_OFFSET.y
	_tooltip_panel.position = pos


func _show_tooltip(text: String) -> void:
	_tooltip_label.text = text
	_tooltip_panel.visible = true
	_tooltip_panel.reset_size()
	_position_tooltip()


func _hide_tooltip() -> void:
	_tooltip_panel.visible = false


func _refresh() -> void:
	for child in _recipe_list.get_children():
		_recipe_list.remove_child(child)
		child.queue_free()

	if _current_recipes.is_empty():
		var empty := Label.new()
		empty.text = "Nothing available here."
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_recipe_list.add_child(empty)
		return

	for recipe in _current_recipes:
		if recipe == null:
			continue
		_recipe_list.add_child(_make_recipe_entry(recipe))


func _get_category(recipe: Recipe) -> String:
	if recipe.output_weapon != null:
		if recipe.requires_weapon == null and recipe.inputs.is_empty():
			return "purchase"
		return "weapon"
	if recipe.output_item != null:
		if recipe.output_item is Armor:
			if recipe.inputs.size() > 0:
				return "armor"
			return "purchase"
		if recipe.output_item.category == "runestone" or recipe.output_item.category == "runebone":
			return "rune"
		if recipe.inputs.is_empty() and recipe.requires_weapon == null:
			return "purchase"
		return "item"
	return "item"


func _make_recipe_entry(recipe: Recipe) -> Control:
	var craftable: bool = recipe.can_craft()
	var category: String = _get_category(recipe)
	var cat_color: Color = CATEGORY_COLORS.get(category, Color.WHITE)

	var entry := PanelContainer.new()
	var es := StyleBoxFlat.new()
	if craftable:
		es.bg_color = Color(0.12, 0.16, 0.12, 0.8)
		es.border_color = Color(cat_color.r, cat_color.g, cat_color.b, 0.5)
	else:
		es.bg_color = Color(0.14, 0.13, 0.16, 0.7)
		es.border_color = Color(0.30, 0.28, 0.32, 0.4)
	es.set_border_width_all(1)
	es.set_corner_radius_all(4)
	es.content_margin_left = 14
	es.content_margin_right = 14
	es.content_margin_top = 10
	es.content_margin_bottom = 10
	entry.add_theme_stylebox_override("panel", es)
	entry.mouse_entered.connect(_on_recipe_hovered.bind(recipe))
	entry.mouse_exited.connect(_on_recipe_unhovered)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	entry.add_child(hbox)

	# Left: badge + name + output
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	hbox.add_child(info)

	var name_rt := RichTextLabel.new()
	name_rt.bbcode_enabled = true
	name_rt.fit_content = true
	name_rt.scroll_active = false
	name_rt.add_theme_font_size_override("normal_font_size", 15)
	var badge: String = "[%s]" % category.to_upper()
	name_rt.text = "[color=#%s]%s[/color] %s" % [
		cat_color.to_html(false), badge, recipe.recipe_name]
	info.add_child(name_rt)

	var output_label := Label.new()
	output_label.text = "→ %s" % _short_output_text(recipe)
	output_label.add_theme_font_size_override("font_size", 12)
	output_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.68))
	info.add_child(output_label)

	# Center: requirement chips
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	chips.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_child(chips)

	for req in recipe.get_requirement_status():
		chips.add_child(_make_chip(req))

	# Right: craft button
	var craft_btn := Button.new()
	craft_btn.text = "Craft" if category != "purchase" else "Buy"
	craft_btn.disabled = not craftable
	craft_btn.add_theme_font_size_override("font_size", 13)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.25, 0.50, 0.35) if craftable else Color(0.25, 0.25, 0.28)
	bs.set_corner_radius_all(4)
	bs.content_margin_left = 14
	bs.content_margin_right = 14
	bs.content_margin_top = 6
	bs.content_margin_bottom = 6
	craft_btn.add_theme_stylebox_override("normal", bs)
	if craftable:
		var bh := StyleBoxFlat.new()
		bh.bg_color = Color(0.30, 0.60, 0.42)
		bh.set_corner_radius_all(4)
		bh.content_margin_left = 14
		bh.content_margin_right = 14
		bh.content_margin_top = 6
		bh.content_margin_bottom = 6
		craft_btn.add_theme_stylebox_override("hover", bh)
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.20, 0.20, 0.22)
	ds.set_corner_radius_all(4)
	ds.content_margin_left = 14
	ds.content_margin_right = 14
	ds.content_margin_top = 6
	ds.content_margin_bottom = 6
	craft_btn.add_theme_stylebox_override("disabled", ds)
	craft_btn.pressed.connect(_on_craft.bind(recipe))
	hbox.add_child(craft_btn)

	return entry


func _make_chip(req: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: Color = COLOR_SATISFIED if req.satisfied else COLOR_MISSING

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(col.r, col.g, col.b, 0.20)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 3)
	m.add_theme_constant_override("margin_bottom", 3)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(m)

	var label := Label.new()
	label.text = req.label
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", col)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(label)

	return panel


func _short_output_text(recipe: Recipe) -> String:
	var parts: Array[String] = []
	if recipe.output_weapon:
		parts.append(recipe.output_weapon.weapon_name)
	if recipe.output_item:
		var n: int = recipe.output_item_count
		var suffix: String = " ×%d" % n if n > 1 else ""
		parts.append("%s%s" % [recipe.output_item.item_name, suffix])
	if parts.is_empty():
		return "(no output)"
	return ", ".join(parts)


func _on_craft(recipe: Recipe) -> void:
	if not recipe.craft():
		return
	var label: String = ""
	var tint: Color = Color(0, 0, 0, 0)
	if recipe.output_weapon:
		label = "Crafted %s" % recipe.output_weapon.weapon_name
		tint = Weapon.element_color(recipe.output_weapon.element)
	elif recipe.output_item:
		var qty: int = recipe.output_item_count
		var suffix: String = " ×%d" % qty if qty > 1 else ""
		label = "Crafted %s%s" % [recipe.output_item.item_name, suffix]
		tint = recipe.output_item.placeholder_color
	else:
		label = "Crafted"
	Toast.show_message(label, tint)
	_on_recipe_hovered(recipe)

func _on_recipe_hovered(recipe: Recipe) -> void:
	var category: String = _get_category(recipe)
	var cat_color: Color = CATEGORY_COLORS.get(category, Color.WHITE)
	var lines: Array[String] = []

	# Title: category badge + recipe name.
	lines.append("[color=#%s][%s][/color]  [color=#%s][b]%s[/b][/color]" % [
		cat_color.to_html(false), category.to_upper(),
		cat_color.to_html(false), recipe.recipe_name])

	# Description.
	if recipe.description != "":
		lines.append("[color=#c8c8c8]%s[/color]" % recipe.description)

	# Output.
	lines.append("[color=#aaaaae]→ %s[/color]" % _short_output_text(recipe))

	# Output item stats — show the same detail the inventory tooltip does.
	var output_res: Resource = recipe.output_weapon if recipe.output_weapon != null \
		else recipe.output_item
	if output_res != null:
		var stat_lines: Array[String] = _format_output_stats(output_res)
		for sl in stat_lines:
			lines.append("  [color=#c8c8c8]• %s[/color]" % sl)

	# Requirements summary.
	var reqs: Array = recipe.get_requirement_status()
	if not reqs.is_empty():
		var req_parts: Array[String] = []
		for req in reqs:
			var col: String = COLOR_SATISFIED.to_html(false) if req.satisfied \
				else COLOR_MISSING.to_html(false)
			req_parts.append("[color=#%s]%s[/color]" % [col, req.label])
		lines.append("\n" + "  ".join(req_parts))

	_show_tooltip("\n".join(lines))


func _on_recipe_unhovered() -> void:
	_hide_tooltip()


## Build stat bullet strings for a recipe's output resource. Mirrors
## the inventory tooltip's stat display so players see the same info
## whether they're looking at an item in inventory or in the shop.
func _format_output_stats(res: Resource) -> Array[String]:
	var bullets: Array[String] = []
	if res is ShieldWeapon:
		var s: ShieldWeapon = res
		var block_pct: int = int((1.0 - s.melee_damage_reduction) * 100)
		bullets.append("Blocks %d%% melee damage" % block_pct)
		bullets.append("Destroys projectiles on contact")
		var speed_pct: int = int((1.0 - s.movement_speed_multiplier) * 100)
		if speed_pct > 0:
			bullets.append("-%d%% move speed while blocking" % speed_pct)
		if s.max_health_bonus > 0:
			bullets.append("+%d max HP (passive)" % int(s.max_health_bonus))
	elif res is MeleeWeapon:
		var m: MeleeWeapon = res
		bullets.append("Damage %d  ·  cooldown %.2fs" % [int(m.base_damage), m.cooldown])
		if m.two_handed:
			bullets.append("Two-handed")
		if m.element != Weapon.Element.PHYSICAL:
			bullets.append("%s damage" % _element_name(m.element))
	elif res is RangedWeapon:
		var r: RangedWeapon = res
		bullets.append("Damage %d  ·  cooldown %.2fs" % [int(r.base_damage), r.cooldown])
		if r.projectile_count > 1:
			bullets.append("%d projectiles  ·  %.0f° spread" % [r.projectile_count, r.spread_degrees])
		if r.pierce > 0:
			bullets.append("Pierces %d target%s" % [r.pierce, "s" if r.pierce > 1 else ""])
		if r.element != Weapon.Element.PHYSICAL:
			bullets.append("%s damage" % _element_name(r.element))
	elif res is Weapon:
		var w: Weapon = res
		bullets.append("Damage %d  ·  cooldown %.2fs" % [int(w.base_damage), w.cooldown])

	if res is Armor:
		var a: Armor = res
		if a.damage_reduction > 0:
			bullets.append("%.0f flat damage reduction" % a.damage_reduction)
		if a.damage_taken_multiplier < 1.0:
			var pct: int = int((1.0 - a.damage_taken_multiplier) * 100)
			bullets.append("%d%% damage resistance" % pct)
		if a.melee_damage_multiplier != 1.0:
			var pct: int = int((a.melee_damage_multiplier - 1.0) * 100)
			var prefix: String = "+" if pct > 0 else ""
			bullets.append("%s%d%% melee damage" % [prefix, pct])
		if a.ranged_damage_multiplier != 1.0:
			var pct: int = int((a.ranged_damage_multiplier - 1.0) * 100)
			var prefix: String = "+" if pct > 0 else ""
			bullets.append("%s%d%% ranged damage" % [prefix, pct])
		if a.move_speed_multiplier != 1.0:
			var pct: int = int((a.move_speed_multiplier - 1.0) * 100)
			var prefix: String = "+" if pct > 0 else ""
			bullets.append("%s%d%% move speed" % [prefix, pct])
		if a.max_health_bonus > 0:
			bullets.append("+%d max HP" % int(a.max_health_bonus))

	if res is RunestoneItem:
		var r: RunestoneItem = res
		bullets.append(r.format_bonus())

	return bullets


static func _element_name(elem: int) -> String:
	match elem:
		Weapon.Element.PHYSICAL:  return "Physical"
		Weapon.Element.FIRE:      return "Fire"
		Weapon.Element.ICE:       return "Ice"
		Weapon.Element.LIGHTNING: return "Lightning"
		Weapon.Element.POISON:    return "Poison"
		Weapon.Element.HOLY:      return "Holy"
		Weapon.Element.DARK:      return "Dark"
	return "Unknown"
