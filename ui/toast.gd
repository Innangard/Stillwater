extends CanvasLayer
## Toast notifications. Autoloaded.
##
## Public API: Toast.show_message("Crafted Soul Phial")
##
## Toasts stack vertically and auto-dismiss after a short duration.
## Process_mode = ALWAYS so they show during paused menus (crafting UI
## pauses the game; we still want feedback).
##
## Stays above the HUD (layer 7) but below menus (10/11) so menu dialogs
## don't get covered.

const TOAST_DURATION := 2.0
const TOAST_FADE_DURATION := 0.4
const MAX_TOASTS := 5

var _container: VBoxContainer


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	layer = 7
	_build_ui()


func _build_ui() -> void:
	_container = VBoxContainer.new()
	_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_container.offset_left = -340
	_container.offset_right = -20
	_container.offset_top = 70 # below the currency display
	_container.offset_bottom = 70
	_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	_container.add_theme_constant_override("separation", 6)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)


## Public: show a single-line toast.
##   tint: optional accent color used for a small left bar. Color(0,0,0,0)
##         (default) uses the theme default neutral color.
func show_message(message: String, tint: Color = Color(0, 0, 0, 0)) -> void:
	# Drop the oldest if we're at the cap so things never pile up.
	while _container.get_child_count() >= MAX_TOASTS:
		var oldest: Node = _container.get_child(0)
		_container.remove_child(oldest)
		oldest.queue_free()

	_container.add_child(_make_toast(message, tint))


func _make_toast(message: String, tint: Color) -> Control:
	var panel := PanelContainer.new()
	panel.modulate = Color(1, 1, 1, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	# Accent bar — a 4px-wide tint marker. Subtle but reads at a glance.
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(4, 0)
	bar.color = tint if tint.a > 0.0 else Color(0.7, 0.7, 0.75, 1.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(margin)

	var label := Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(label)

	# Animate: fade in → wait → fade out → free.
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, TOAST_FADE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(TOAST_DURATION)
	tween.tween_property(panel, "modulate:a", 0.0, TOAST_FADE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(panel.queue_free)

	return panel
