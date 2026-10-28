class_name RegionRoot
extends Node2D
## Attach this to the root node of every region scene. It handles:
##   - Setting RunState.current_region
##   - Spawning the player at the requested spawn point
##   - Connecting children to the global "spawn_points" group
##   - Adapting camera limits to the viewport size on resize

@export var region_id: String = ""
@export var player_scene: PackedScene

var _room_bounds: Rect2 = Rect2()
var _has_bounds: bool = false


func _ready() -> void:
	if region_id != "":
		RunState.current_region = region_id

	PathManager.apply_overrides(self)

	# Find or spawn the player.
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null and player_scene != null:
		player = player_scene.instantiate()
		add_child(player)

	# Place at the requested spawn point.
	if player is Node2D:
		var p2: Node2D = player
		if SaveManager.has_pending_load_position:
			p2.global_position = SaveManager.pending_load_position
			SaveManager.has_pending_load_position = false
			SaveManager.pending_load_position = Vector2.ZERO
		else:
			var marker: Node2D = _find_spawn_marker(RunState.requested_spawn_point)
			if marker:
				p2.global_position = marker.global_position
		RunState.requested_spawn_point = ""

	PathManager.on_scene_entered(scene_file_path)

	# Pass the player to the bounds calculation so we have a reference point
	# for where the "inside" of the room is.
	_compute_room_bounds(player)
	_refresh_camera_limits(player)
	
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)


func _on_viewport_size_changed() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	_refresh_camera_limits(player)


## Walk the wall tree and stash the resulting Rect2 of room bounds.
## Uses the player's start position to deduce which limits a Polygon sets.
func _compute_room_bounds(player: Node) -> void:
	_has_bounds = false

	var left: float = -100000.0
	var right: float = 100000.0
	var top: float = -100000.0
	var bottom: float = 100000.0

	var px: float = 0.0
	var py: float = 0.0
	var has_player: bool = player is Node2D
	if has_player:
		px = player.global_position.x
		py = player.global_position.y

	for static_body in _get_all_descendants(self):
		if not (static_body is StaticBody2D):
			continue
			
		for shape_node in static_body.get_children():
			if shape_node is CollisionShape2D:
				var shape = shape_node.shape
				if shape is WorldBoundaryShape2D:
					var wb: WorldBoundaryShape2D = shape
					var offset: Vector2 = shape_node.position + static_body.position
					var n: Vector2 = wb.normal
					var d: float = wb.distance

					if abs(n.x) > 0.5 and abs(n.y) < 0.5:
						if n.x > 0:
							left = max(left, d + offset.x)
						else:
							right = min(right, -d + offset.x)
						_has_bounds = true
					elif abs(n.y) > 0.5 and abs(n.x) < 0.5:
						if n.y > 0:
							top = max(top, d + offset.y)
						else:
							bottom = min(bottom, -d + offset.y)
						_has_bounds = true
						
			elif shape_node is CollisionPolygon2D:
				var poly: CollisionPolygon2D = shape_node
				if poly.polygon.is_empty():
					continue
					
				var p_min := Vector2(INF, INF)
				var p_max := Vector2(-INF, -INF)
				
				# Get absolute world coordinates for all vertices
				for pt in poly.polygon:
					var world_pt: Vector2 = poly.to_global(pt)
					p_min.x = min(p_min.x, world_pt.x)
					p_min.y = min(p_min.y, world_pt.y)
					p_max.x = max(p_max.x, world_pt.x)
					p_max.y = max(p_max.y, world_pt.y)
					
				# HEURISTIC: Compare polygon's AABB to player's starting position 
				# to figure out which wall it acts as.
				if has_player:
					# If polygon's lowest edge is above the player -> Top Wall
					if p_max.y < py:
						top = max(top, p_max.y)
					# If polygon's highest edge is below the player -> Bottom Wall
					elif p_min.y > py:
						bottom = min(bottom, p_min.y)
						
					# If polygon's rightmost edge is left of the player -> Left Wall
					if p_max.x < px:
						left = max(left, p_max.x)
					# If polygon's leftmost edge is right of the player -> Right Wall
					elif p_min.x > px:
						right = min(right, p_min.x)
				else:
					# Safe fallback if no player is found (applies all 4 sides)
					left = max(left, p_min.x)
					right = min(right, p_max.x)
					top = max(top, p_min.y)
					bottom = min(bottom, p_max.y)
					
				_has_bounds = true

	if _has_bounds:
		_room_bounds = Rect2(left, top, right - left, bottom - top)


func _refresh_camera_limits(player: Node) -> void:
	if not (player is Node2D):
		return
	var camera: Camera2D = null
	for child in player.get_children():
		if child is Camera2D:
			camera = child
			break
	if camera == null:
		return

	# Reset limits
	camera.limit_left = -10000000
	camera.limit_right = 10000000
	camera.limit_top = -10000000
	camera.limit_bottom = 10000000

	if not _has_bounds:
		return

	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var viewport_size: Vector2 = vp.get_visible_rect().size
	var zoom: Vector2 = camera.zoom
	if zoom.x <= 0.0 or zoom.y <= 0.0:
		return
	var visible_world: Vector2 = viewport_size / zoom

	var room_w: float = _room_bounds.size.x
	var room_h: float = _room_bounds.size.y
	var room_center: Vector2 = _room_bounds.position + _room_bounds.size * 0.5

	# X axis.
	if room_w >= visible_world.x:
		camera.limit_left = int(_room_bounds.position.x)
		camera.limit_right = int(_room_bounds.position.x + room_w)
	else:
		var x: int = int(room_center.x)
		camera.limit_left = x
		camera.limit_right = x

	# Y axis.
	if room_h >= visible_world.y:
		camera.limit_top = int(_room_bounds.position.y)
		camera.limit_bottom = int(_room_bounds.position.y + room_h)
	else:
		var y: int = int(room_center.y)
		camera.limit_top = y
		camera.limit_bottom = y

	camera.limit_smoothed = true


func _find_spawn_marker(spawn_name: String) -> Node2D:
	var target_name: String = spawn_name if spawn_name != "" else "default"
	for node in _get_all_descendants(self):
		if node is Marker2D and node.name == target_name:
			return node
	for node in get_tree().get_nodes_in_group("spawn_points"):
		if node is Marker2D and node.get_parent() != null and is_ancestor_of(node):
			return node
	return null


func _get_all_descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_get_all_descendants(child))
	return result
