extends CanvasLayer
## Full-screen world map overlay, toggled with the "toggle_map" action (M).
## Reads from PathManager.scene_graph to draw rooms, connections, and icons.
## Progressive reveal is controlled by PathManager.is_section_visible().
##
## Visual design inspired by Rogue Legacy 2's map: coloured room rectangles
## on a dark background with small connectors between rooms, special icons
## for towns and clearings, and a parchment-style legend.
##
## NOTE: No class_name (autoload "WorldMap").

# ============================================================================
# SIZING
# ============================================================================

const CELL_W := 64  ## Room width in pixels.
const CELL_H := 48  ## Room height in pixels.
const GRID_W := 80  ## Horizontal distance between room centres.
const GRID_H := 64  ## Vertical distance between room centres.
const CONN_W := 4   ## Connection line thickness.
const ICON_R := 8   ## Icon radius.

const PAN_SPEED := 400.0
const ZOOM_MIN := 0.35
const ZOOM_MAX := 2.0
const ZOOM_STEP := 0.1

# ============================================================================
# SECTION COLOURS — fill (visited), outline (revealed-not-visited)
# ============================================================================

const SECTION_COLORS := {
	PathManager.SECTION_START:       Color(0.55, 0.42, 0.28),   # warm brown
	PathManager.SECTION_STORSPRUNGA: Color(0.28, 0.48, 0.58),   # coastal blue
	PathManager.SECTION_NASUS:       Color(0.30, 0.50, 0.32),   # forest green
	PathManager.SECTION_NORTH_CHAIN: Color(0.42, 0.32, 0.52),   # mystic purple
	PathManager.SECTION_EAST:        Color(0.50, 0.40, 0.28),   # amber
	PathManager.SECTION_EAST_CHAIN:  Color(0.55, 0.38, 0.30),   # burnt sienna
	PathManager.SECTION_SPREKKEN:    Color(0.45, 0.28, 0.50),   # deep violet
	PathManager.SECTION_BRANN:       Color(0.65, 0.30, 0.18),   # ember red
	PathManager.SECTION_COAST:       Color(0.32, 0.52, 0.55),   # sea-green
	PathManager.SECTION_WESTMOOR:    Color(0.40, 0.46, 0.54),   # steel slate-blue
	PathManager.SECTION_EASTREACH:   Color(0.65, 0.55, 0.38),   # warm chalk-tan
	## Bridging color between eastreach chalk-tan and sprekken deep-
	## violet — a muted dusk that reads as "leaving the pilgrim road,
	## approaching the dungeon" without belonging fully to either.
	PathManager.SECTION_SPREKKEN_APPROACH: Color(0.52, 0.42, 0.48),  # dusk plum
	## Sundust: drier, brighter desert tone — a step warmer than
	## Eastreach's chalk-tan, signaling the climb up into the
	## sun-scorched highlands. Reads as "deeper desert" against the
	## pilgrim road's softer warmth.
	PathManager.SECTION_SUNDUST: Color(0.78, 0.60, 0.32),  # dry desert ochre
	## Deep Desert: bleached bone-white with a hint of amber — the sand
	## past the broodmother gate. Distinct from Sundust's warm ochre by
	## being lighter and more washed-out, signaling "you've gone past
	## the last outpost."
	PathManager.SECTION_DEEP_DESERT: Color(0.88, 0.78, 0.55),  # bleached sand
	## Hollowmere: cold, muted teal — standing water, peat bogs, mist.
	## A deliberate temperature shift from Westmoor's steel-blue: same
	## coolness but greener, reading as "the moors got wetter."
	PathManager.SECTION_HOLLOWMERE: Color(0.30, 0.52, 0.48),  # bog teal
	## Storsprunga Altar corridor + the coast→westmoor connector: a
	## weathered stone-gray with a hint of the coastal blue. This
	## section is the wilderness north of Storsprunga — exposed rock,
	## sea spray, altar ruins.
	PathManager.SECTION_STORSPRUNGA_ALTAR: Color(0.38, 0.45, 0.50),  # sea-stone
	## Hindarfjall: warm volcanic ash. Reads as "mountain, but the
	## kind with geothermal vents" — ember undertones under gray.
	PathManager.SECTION_HINDARFJALL: Color(0.52, 0.38, 0.35),  # volcanic ash
	## Hrimbjarg: ice-blue frost. The coldest section on the map;
	## pairs with the name ("frost cliff") and the altar's frost
	## boss thematically.
	PathManager.SECTION_HRIMBJARG: Color(0.42, 0.55, 0.68),  # frost blue
	## Thursdal: deep forest green with a golden warmth — old-growth
	## mountain timber. Distinct from Nasus's forest green by being
	## darker and warmer, signaling altitude + ancient growth.
	PathManager.SECTION_THURSDAL: Color(0.32, 0.45, 0.28),  # old-growth pine
	## Missing Act 1 sections (pre-existing)
	PathManager.SECTION_MYRKFEN_APPROACH: Color(0.48, 0.42, 0.45),  # twilight mauve
	PathManager.SECTION_BRANN_APPROACH: Color(0.60, 0.32, 0.22),  # smolder
	PathManager.SECTION_MYRKFEN: Color(0.35, 0.42, 0.32),  # swamp-moss
	PathManager.SECTION_GARNVIK: Color(0.32, 0.40, 0.48),  # sea-cavern slate
	## Act 2 sections
	PathManager.SECTION_STRANDVIK: Color(0.45, 0.52, 0.55),  # driftwood gray
	PathManager.SECTION_DRIFTWORKS: Color(0.35, 0.50, 0.58),  # harbour blue
	PathManager.SECTION_BARRHOLT: Color(0.48, 0.42, 0.32),  # fur-trade brown
	PathManager.SECTION_KALDRHOLT: Color(0.28, 0.48, 0.35),  # deep pine
	PathManager.SECTION_VINDFELL: Color(0.38, 0.55, 0.42),  # highland green
	PathManager.SECTION_FROSTGARD: Color(0.50, 0.58, 0.65),  # mountain steel
	PathManager.SECTION_ISVARDA: Color(0.45, 0.55, 0.62),  # glacier blue
	PathManager.SECTION_VATNBORG: Color(0.32, 0.48, 0.50),  # lake-water teal
	PathManager.SECTION_VATNSTEINN: Color(0.38, 0.45, 0.42),  # waterstone gray
	PathManager.SECTION_ASHFELD: Color(0.55, 0.38, 0.28),  # volcanic amber
	PathManager.SECTION_KOLFJALL: Color(0.48, 0.32, 0.25),  # magma brown
	PathManager.SECTION_SINDRI_APPROACH: Color(0.58, 0.42, 0.30),  # forge-glow
	PathManager.SECTION_GYMIR_APPROACH: Color(0.52, 0.48, 0.38),  # mountain pass
	PathManager.SECTION_SKADI_APPROACH: Color(0.42, 0.52, 0.45),  # hunter's trail
	PathManager.SECTION_HRIMFAXI_APPROACH: Color(0.48, 0.58, 0.65),  # frost trail
	PathManager.SECTION_ASHSPROUT_APPROACH: Color(0.42, 0.45, 0.35),  # rotting wood
	PathManager.SECTION_EIR_APPROACH: Color(0.55, 0.42, 0.52),  # valkyrie dusk
	PathManager.SECTION_BRIDGE: Color(0.58, 0.52, 0.42),  # bridge stone
	PathManager.SECTION_KINGS_TOWER: Color(0.62, 0.55, 0.38),  # royal gold
}

const COLOR_CURRENT   := Color(1.0, 0.9, 0.35)   # highlight ring for current room
const COLOR_CONN      := Color(0.45, 0.45, 0.50)  # connection lines
const COLOR_CONN_DIM  := Color(0.25, 0.25, 0.28)  # connections to unvisited rooms
const COLOR_TOWN_ICON := Color(1.0, 0.85, 0.25)   # town star
const COLOR_CLR_ICON  := Color(0.35, 0.85, 0.45)  # clearing diamond
const COLOR_ARCH_ICON := Color(0.85, 0.55, 1.0)   # arch glyph
const COLOR_BG        := Color(0.04, 0.04, 0.07, 0.93)
const COLOR_LEGEND_BG := Color(0.18, 0.15, 0.12, 0.92)
const COLOR_LABEL     := Color(0.88, 0.85, 0.78)

# ============================================================================
# STATE
# ============================================================================

var is_open: bool = false
var _camera: Vector2 = Vector2.ZERO   # pan offset (world-space pixels)
var _zoom: float = 1.0
var _current_scene: String = ""       # scene_path of the room the player is in

var _bg: ColorRect
var _surface: Control   # we draw onto this
var _legend: Control

var _tooltip_text: String = ""
var _tooltip_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	layer = 40  # below SceneTransition (50)

	_build_ui()
	visible = false

	EventBus.map_graph_rebuilt.connect(_on_graph_rebuilt)
	EventBus.map_section_revealed.connect(_on_section_revealed)


func _build_ui() -> void:
	# Dark background.
	_bg = ColorRect.new()
	_bg.color = COLOR_BG
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	# Drawing surface.
	_surface = Control.new()
	_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_PASS
	_surface.draw.connect(_on_surface_draw)
	add_child(_surface)

	# Legend overlay (bottom-right).
	_legend = Control.new()
	_legend.set_anchors_preset(Control.PRESET_FULL_RECT)
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.draw.connect(_on_legend_draw)
	add_child(_legend)


# ============================================================================
# INPUT
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		_toggle()
		get_viewport().set_input_as_handled()
		return

	if not is_open:
		return

	# Zoom with scroll wheel.
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom = clampf(_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
				_surface.queue_redraw()
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom = clampf(_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
				_surface.queue_redraw()
				get_viewport().set_input_as_handled()

	# Consume all key presses while open so the player doesn't move.
	if event is InputEventKey:
		get_viewport().set_input_as_handled()

	# Consume mouse clicks to prevent gameplay interaction.
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_map_click(mb.position)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open:
		return

	# Pan with arrow keys / WASD (these are already the movement actions).
	var pan_dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		pan_dir.y -= 1.0
	if Input.is_action_pressed("move_down"):
		pan_dir.y += 1.0
	if Input.is_action_pressed("move_left"):
		pan_dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		pan_dir.x += 1.0

	if pan_dir != Vector2.ZERO:
		_camera += pan_dir.normalized() * PAN_SPEED * delta / _zoom
		_surface.queue_redraw()

	# Tooltip from mouse hover.
	_update_tooltip()


func _toggle() -> void:
	if not is_open:
		# Don't open the map if something else has the tree paused
		# (e.g. a scene transition), or if another overlay is showing.
		if get_tree().paused:
			return
		is_open = true
	else:
		is_open = false

	visible = is_open
	get_tree().paused = is_open

	if is_open:
		_current_scene = _get_current_scene_path()
		_centre_on_current_room()
		_surface.queue_redraw()
		_legend.queue_redraw()


func _centre_on_current_room() -> void:
	if not PathManager.scene_graph.has(_current_scene):
		return
	var pos: Vector2i = PathManager.scene_graph[_current_scene]["pos"]
	_camera = Vector2(pos.x * GRID_W, pos.y * GRID_H)


func _get_current_scene_path() -> String:
	var root := get_tree().current_scene
	if root:
		return root.scene_file_path
	return ""


# ============================================================================
# DRAWING — SURFACE
# ============================================================================

func _on_surface_draw() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var centre: Vector2 = vp_size * 0.5

	# Draw title.
	var font := ThemeDB.fallback_font
	if font:
		var title: String = "WORLD MAP"
		match PathManager.in_dungeon:
			"sprekken": title = "SPREKKEN DEPTHS"
			"brann":    title = "BRANN PYRE"
		_surface.draw_string(font, Vector2(centre.x - 80, 36), title,
			HORIZONTAL_ALIGNMENT_CENTER, 160, 20, COLOR_LABEL)
		_surface.draw_string(font, Vector2(centre.x - 200, 56),
			"[M / Tab] close   |   WASD pan   |   scroll zoom",
			HORIZONTAL_ALIGNMENT_CENTER, 400, 11, Color(COLOR_LABEL, 0.5))
		if _is_at_travel_point():
			_surface.draw_string(font, Vector2(centre.x - 200, 72),
				"Click a visited town, altar, or dungeon entrance to fast-travel",
				HORIZONTAL_ALIGNMENT_CENTER, 400, 11, Color(0.4, 0.85, 0.5, 0.6))

	# Connection pass (behind rooms).
	for path in PathManager.scene_graph:
		var data: Dictionary = PathManager.scene_graph[path]
		if not _is_visible(data):
			continue
		for conn_path in data["connections"]:
			if not PathManager.scene_graph.has(conn_path):
				continue
			var conn_data: Dictionary = PathManager.scene_graph[conn_path]
			if not _is_visible(conn_data):
				continue
			# Only draw each connection once (lower path string draws it).
			if path > conn_path:
				continue
			# Skip non-orthogonally-adjacent connections. The graph stores
			# some "logical" connections that are real in-game scene
			# transitions but aren't physically adjacent on the map grid:
			#   - chain-end → side-buffer rerouting created by the
			#     extreme-clearing swap (Nasus, Sprekken endpoints)
			#   - the coast loop closing from its far end back to
			#     Storsprunga
			# Drawing those as straight lines slashes across the whole map
			# and is misleading — the player can't actually walk in a
			# straight line between the two rooms. We show a small marker
			# instead (see far-link pass below).
			if not _is_orthogonally_adjacent(data["pos"], conn_data["pos"]):
				continue
			var a_screen: Vector2 = _grid_to_screen(data["pos"], centre)
			var b_screen: Vector2 = _grid_to_screen(conn_data["pos"], centre)
			var col: Color = COLOR_CONN if (data["visited"] and conn_data["visited"]) else COLOR_CONN_DIM
			_surface.draw_line(a_screen, b_screen, col, CONN_W * _zoom, true)

	# Far-link marker pass — for each non-adjacent connection, draw a
	# small chevron on the source room's edge pointing toward the
	# destination. Conveys "this room has an exit that leads somewhere
	# off the local grid" without claiming a false adjacency. Cheaper
	# than wiring full tooltip text; the existing room tooltip already
	# names the destination when the player hovers either endpoint.
	for path in PathManager.scene_graph:
		var data: Dictionary = PathManager.scene_graph[path]
		if not _is_visible(data):
			continue
		# Only draw the marker on visited rooms — otherwise the chevron
		# would leak fog-of-war info about distant unvisited rooms.
		if not data["visited"]:
			continue
		for conn_path in data["connections"]:
			if not PathManager.scene_graph.has(conn_path):
				continue
			var conn_data: Dictionary = PathManager.scene_graph[conn_path]
			if not _is_visible(conn_data):
				continue
			if _is_orthogonally_adjacent(data["pos"], conn_data["pos"]):
				continue
			_draw_far_link_marker(_grid_to_screen(data["pos"], centre),
				data["pos"], conn_data["pos"])

	# Room pass.
	for path in PathManager.scene_graph:
		var data: Dictionary = PathManager.scene_graph[path]
		if not _is_visible(data):
			continue
		var screen_pos: Vector2 = _grid_to_screen(data["pos"], centre)
		_draw_room(screen_pos, data, path == _current_scene)

	# Tooltip.
	if _tooltip_text != "" and font:
		var tp := _tooltip_pos + Vector2(14, -10)
		var text_w: float = font.get_string_size(_tooltip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_surface.draw_rect(Rect2(tp.x - 4, tp.y - 13, text_w + 8, 18),
			Color(0.08, 0.08, 0.1, 0.9))
		_surface.draw_string(font, tp, _tooltip_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_LABEL)


func _draw_room(screen: Vector2, data: Dictionary, is_current: bool) -> void:
	var half := Vector2(CELL_W, CELL_H) * 0.5 * _zoom
	var rect := Rect2(screen - half, half * 2.0)
	var section: String = data["section"]
	var base_col: Color = SECTION_COLORS.get(section, Color(0.4, 0.4, 0.4))

	if data["visited"]:
		# Filled room.
		_surface.draw_rect(rect, Color(base_col, 0.65))
		_surface.draw_rect(rect, Color(base_col.lightened(0.3), 0.9), false, 2.0)
	else:
		# Outline only (fog-of-war room that's revealed but unvisited).
		_surface.draw_rect(rect, Color(base_col, 0.12))
		_surface.draw_rect(rect, Color(base_col, 0.35), false, 1.5)

	# Current-room highlight.
	if is_current:
		var glow_rect := rect.grow(3.0 * _zoom)
		_surface.draw_rect(glow_rect, Color(COLOR_CURRENT, 0.55), false, 3.0 * _zoom)
		_surface.draw_rect(rect, Color(COLOR_CURRENT, 0.8), false, 2.5)

	# Type icon.
	match data["type"]:
		PathManager.TYPE_TOWN:
			_draw_town_icon(screen)
		PathManager.TYPE_CLEARING:
			_draw_clearing_icon(screen)
		PathManager.TYPE_ARCH:
			_draw_arch_icon(screen)
		PathManager.TYPE_DUNGEON_ENTRANCE:
			_draw_dungeon_icon(screen)
		PathManager.TYPE_BOSS:
			_draw_boss_icon(screen)
		PathManager.TYPE_ALTAR:
			_draw_altar_icon(screen)


func _draw_town_icon(centre: Vector2) -> void:
	## Small 5-pointed star.
	var r: float = ICON_R * _zoom
	var pts := PackedVector2Array()
	for i in 10:
		var angle: float = -PI / 2.0 + i * TAU / 10.0
		var radius: float = r if i % 2 == 0 else r * 0.45
		pts.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	_surface.draw_colored_polygon(pts, COLOR_TOWN_ICON)
	for i in 10:
		_surface.draw_line(pts[i], pts[(i + 1) % 10], Color.BLACK, 1.0)


func _draw_clearing_icon(centre: Vector2) -> void:
	## Small diamond.
	var r: float = ICON_R * 0.8 * _zoom
	var pts := PackedVector2Array([
		centre + Vector2(0, -r),
		centre + Vector2(r, 0),
		centre + Vector2(0, r),
		centre + Vector2(-r, 0),
	])
	_surface.draw_colored_polygon(pts, COLOR_CLR_ICON)
	for i in 4:
		_surface.draw_line(pts[i], pts[(i + 1) % 4], Color.BLACK, 1.0)


func _draw_arch_icon(centre: Vector2) -> void:
	## Small arch/keystone shape.
	var r: float = ICON_R * 0.75 * _zoom
	var pts := PackedVector2Array([
		centre + Vector2(-r, r),
		centre + Vector2(-r, -r * 0.3),
		centre + Vector2(-r * 0.5, -r),
		centre + Vector2(r * 0.5, -r),
		centre + Vector2(r, -r * 0.3),
		centre + Vector2(r, r),
	])
	_surface.draw_colored_polygon(pts, COLOR_ARCH_ICON)
	for i in pts.size():
		_surface.draw_line(pts[i], pts[(i + 1) % pts.size()], Color.BLACK, 1.0)


const COLOR_DUNGEON_ICON := Color(0.55, 0.35, 0.65)   # dungeon entrance
const COLOR_BOSS_ICON    := Color(0.90, 0.30, 0.30)   # boss room
const COLOR_ALTAR_ICON   := Color(0.95, 0.80, 0.45)   # altar — warm gold/flame

func _draw_dungeon_icon(centre: Vector2) -> void:
	## Doorway / gate shape.
	var r: float = ICON_R * 0.8 * _zoom
	var pts := PackedVector2Array([
		centre + Vector2(-r, r),
		centre + Vector2(-r, -r * 0.6),
		centre + Vector2(-r * 0.4, -r),
		centre + Vector2(r * 0.4, -r),
		centre + Vector2(r, -r * 0.6),
		centre + Vector2(r, r),
	])
	_surface.draw_colored_polygon(pts, COLOR_DUNGEON_ICON)
	for i in pts.size():
		_surface.draw_line(pts[i], pts[(i + 1) % pts.size()], Color.BLACK, 1.0)
	# Dark interior
	_surface.draw_rect(Rect2(centre.x - r * 0.3, centre.y - r * 0.3,
		r * 0.6, r * 1.1), Color(0.1, 0.08, 0.14))

func _draw_boss_icon(centre: Vector2) -> void:
	## Skull-like shape (simple).
	var r: float = ICON_R * 0.9 * _zoom
	_surface.draw_circle(centre + Vector2(0, -r * 0.15), r * 0.85, COLOR_BOSS_ICON)
	_surface.draw_circle(centre + Vector2(0, -r * 0.15), r * 0.85, Color.BLACK, false, 1.0)
	# Eyes
	_surface.draw_circle(centre + Vector2(-r * 0.3, -r * 0.25), r * 0.18, Color.BLACK)
	_surface.draw_circle(centre + Vector2(r * 0.3, -r * 0.25), r * 0.18, Color.BLACK)


func _draw_altar_icon(centre: Vector2) -> void:
	## A wide stone slab with a flame on top — reads as a sacred site
	## at any zoom, distinct from town/boss/dungeon icons. Flame is
	## a small upward triangle, slab is a thin wider rectangle below.
	var r: float = ICON_R * _zoom
	# Slab base
	var slab := Rect2(centre.x - r * 0.9, centre.y + r * 0.1, r * 1.8, r * 0.5)
	_surface.draw_rect(slab, Color(0.55, 0.50, 0.46))
	_surface.draw_rect(slab, Color.BLACK, false, 1.0)
	# Flame on top — small upward-pointing triangle in warm gold
	var flame := PackedVector2Array([
		centre + Vector2(0, -r * 0.9),
		centre + Vector2(r * 0.45, r * 0.1),
		centre + Vector2(-r * 0.45, r * 0.1),
	])
	_surface.draw_colored_polygon(flame, COLOR_ALTAR_ICON)
	for i in 3:
		_surface.draw_line(flame[i], flame[(i + 1) % 3], Color.BLACK, 1.0)


# ============================================================================
# DRAWING — LEGEND
# ============================================================================

func _on_legend_draw() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size

	# Legend background (bottom-right).
	var lw: float = 175.0
	var lh: float = 185.0
	var lx: float = vp_size.x - lw - 20.0
	var ly: float = vp_size.y - lh - 20.0
	var legend_rect := Rect2(lx, ly, lw, lh)
	_legend.draw_rect(legend_rect, COLOR_LEGEND_BG)
	_legend.draw_rect(legend_rect, Color(0.5, 0.45, 0.35, 0.6), false, 2.0)

	# Title.
	var tx: float = lx + 12.0
	var ty: float = ly + 22.0
	_legend.draw_string(font, Vector2(tx, ty), "Legend",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_LABEL)
	ty += 6.0

	# Entries.
	var entries := [
		[COLOR_TOWN_ICON, "Town"],
		[COLOR_CLR_ICON, "Forest Clearing"],
		[COLOR_ARCH_ICON, "Arch (respawn)"],
		[COLOR_DUNGEON_ICON, "Dungeon Entrance"],
		[COLOR_BOSS_ICON, "Boss Room"],
		[COLOR_ALTAR_ICON, "Altar"],
	]
	for entry in entries:
		ty += 20.0
		var col: Color = entry[0]
		var label: String = entry[1]
		# Icon swatch.
		_legend.draw_rect(Rect2(tx, ty - 10, 14, 14), col)
		_legend.draw_rect(Rect2(tx, ty - 10, 14, 14), Color.BLACK, false, 1.0)
		_legend.draw_string(font, Vector2(tx + 22, ty + 2), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_LABEL)

	# Visited / unvisited.
	ty += 24.0
	_legend.draw_rect(Rect2(tx, ty - 10, 14, 14), Color(0.45, 0.42, 0.38, 0.65))
	_legend.draw_rect(Rect2(tx, ty - 10, 14, 14), Color(0.6, 0.55, 0.5), false, 1.5)
	_legend.draw_string(font, Vector2(tx + 22, ty + 2), "Visited",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_LABEL)

	ty += 20.0
	_legend.draw_rect(Rect2(tx, ty - 10, 14, 14), Color(0.3, 0.3, 0.3, 0.15))
	_legend.draw_rect(Rect2(tx, ty - 10, 14, 14), Color(0.4, 0.4, 0.4, 0.4), false, 1.5)
	_legend.draw_string(font, Vector2(tx + 22, ty + 2), "Unexplored",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_LABEL)


# ============================================================================
# TOOLTIP
# ============================================================================

func _update_tooltip() -> void:
	var old := _tooltip_text
	_tooltip_text = ""

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var centre: Vector2 = vp_size * 0.5
	var mouse: Vector2 = get_viewport().get_mouse_position()
	_tooltip_pos = mouse

	var half := Vector2(CELL_W, CELL_H) * 0.5 * _zoom

	for path in PathManager.scene_graph:
		var data: Dictionary = PathManager.scene_graph[path]
		if not _is_visible(data):
			continue
		var screen_pos: Vector2 = _grid_to_screen(data["pos"], centre)
		var rect := Rect2(screen_pos - half, half * 2.0)
		if rect.has_point(mouse):
			if data["visited"]:
				_tooltip_text = data["name"]
			else:
				_tooltip_text = "???"
			break

	if _tooltip_text != old:
		_surface.queue_redraw()


# ============================================================================
# HELPERS
# ============================================================================

func _grid_to_screen(grid_pos: Vector2i, viewport_centre: Vector2) -> Vector2:
	var world := Vector2(grid_pos.x * GRID_W, grid_pos.y * GRID_H)
	return (world - _camera) * _zoom + viewport_centre


func _is_visible(data: Dictionary) -> bool:
	return PathManager.is_section_visible(data["section"])


## True when two grid cells share an edge (Manhattan distance == 1).
## Every legitimate connection in the graph — static scene chains, the
## randomized buffer chains, side-clearing offshoots — places rooms in
## a single cardinal direction one cell apart, so this is the correct
## test for "the two rooms should have a line drawn between them on the
## map". Same-cell (distance 0) is treated as not-adjacent because
## overlapping rooms shouldn't draw a degenerate dot.
func _is_orthogonally_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return abs(a.x - b.x) + abs(a.y - b.y) == 1


## Draw a small chevron on the source room's edge pointing toward a
## distant connected room. The chevron sits just outside the room
## rectangle in the direction of the destination, so the player can
## tell at a glance "this room has an off-grid exit going north" without
## the map drawing a long straight line that implies the two rooms are
## adjacent. The pointer direction is the dominant axis of the offset,
## so a destination at (+1, -9) reads as "up", (+8, 0) reads as "right".
func _draw_far_link_marker(source_screen: Vector2, source_pos: Vector2i,
		target_pos: Vector2i) -> void:
	var dx: int = target_pos.x - source_pos.x
	var dy: int = target_pos.y - source_pos.y
	# Pick the dominant axis so the chevron snaps to one of the four
	# cardinal edges of the room — feels grid-native, fits the same
	# visual language as the rest of the map.
	var dir: Vector2
	if abs(dx) > abs(dy):
		dir = Vector2(signf(float(dx)), 0.0)
	else:
		dir = Vector2(0.0, signf(float(dy)))
	if dir == Vector2.ZERO:
		return

	# Place the chevron just outside the room's edge so it reads as an
	# "exit toward..." marker rather than something inside the room.
	var half := Vector2(CELL_W, CELL_H) * 0.5 * _zoom
	var edge_offset := Vector2(dir.x * (half.x + 6.0 * _zoom),
		dir.y * (half.y + 6.0 * _zoom))
	var tip: Vector2 = source_screen + edge_offset

	# Chevron points: a "V" opening back toward the source room. The
	# perpendicular axis spreads the wings.
	var size: float = 5.0 * _zoom
	var perp := Vector2(-dir.y, dir.x)
	var p1: Vector2 = tip + (perp * size) - (dir * size)
	var p2: Vector2 = tip - (perp * size) - (dir * size)
	_surface.draw_line(tip, p1, COLOR_CONN, max(1.5, CONN_W * _zoom * 0.6), true)
	_surface.draw_line(tip, p2, COLOR_CONN, max(1.5, CONN_W * _zoom * 0.6), true)


# ============================================================================
# ============================================================================
# POI FAST-TRAVEL — click any visited point of interest while standing
# at one yourself to teleport. Previously restricted to the three named
# town scenes; now any node whose `type` is in TRAVEL_TYPES qualifies as
# both a SOURCE and a DESTINATION. That means towns, altars, and dungeon
# entrances are all interchangeable travel hubs.
# ============================================================================

## Types the player can teleport FROM and TO. Both ends of the trip
## must be one of these — the player can fast-travel between any two
## visited POIs regardless of category. Picked by type rather than a
## hardcoded scene list so new altars / dungeon entrances added later
## work automatically without touching this file.
##
## Arches were added to the list because they're the player's primary
## navigation landmarks — South Arch, East Arch, North Arch — and once
## visited they should serve as fast-travel anchors the same way altars
## and towns do.
const TRAVEL_TYPES := [
	PathManager.TYPE_TOWN,
	PathManager.TYPE_ALTAR,
	PathManager.TYPE_DUNGEON_ENTRANCE,
	PathManager.TYPE_ARCH,
]


func _handle_map_click(click_pos: Vector2) -> void:
	if not _is_at_travel_point():
		return

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var centre: Vector2 = vp_size * 0.5
	var click_radius: float = max(CELL_W, CELL_H) * 0.5 * _zoom

	# Find which scene node was clicked
	for path in PathManager.scene_graph:
		var data: Dictionary = PathManager.scene_graph[path]
		if not _is_visible(data):
			continue
		if not data["visited"]:
			continue
		# Only teleport between travel-eligible POIs (towns, altars,
		# dungeon entrances). Type check replaces the old hardcoded
		# TOWN_SCENES dict and automatically covers all current and
		# future altars / entrances registered in scene_graph.
		if not (data.get("type", "") in TRAVEL_TYPES):
			continue
		if path == _current_scene:
			continue

		var screen_pos: Vector2 = _grid_to_screen(data["pos"], centre)
		if click_pos.distance_to(screen_pos) <= click_radius:
			_teleport_to_poi(path)
			return


func _is_at_travel_point() -> bool:
	# Type-based check via the scene graph — works for any POI, not
	# just the three original town scenes. Falls back to false if the
	# current scene isn't tracked by PathManager (e.g. menus, dungeon
	# interiors, or any scene that hasn't been registered in the
	# graph yet).
	var data: Dictionary = PathManager.scene_graph.get(_current_scene, {})
	if data.is_empty():
		return false
	return data.get("type", "") in TRAVEL_TYPES


func _teleport_to_poi(target_scene: String) -> void:
	# All POI scenes (towns, altars, dungeon entrances) define a
	# "default" Marker2D — that's the canonical drop point regardless
	# of which direction the player would normally arrive from. No
	# per-scene spawn lookup is needed; if a new POI is added later,
	# it just needs a "default" marker like every existing one.
	_toggle()  # Close the map first
	SceneTransition.go_to(target_scene, "default")


# ============================================================================
# SIGNAL HANDLERS
# ============================================================================

func _on_graph_rebuilt() -> void:
	if is_open:
		_surface.queue_redraw()


func _on_section_revealed(_flag: String) -> void:
	if is_open:
		_surface.queue_redraw()
		_legend.queue_redraw()
