extends Enemy
## Cinder Maw — fire-themed flamethrower mook. Slow, fragile-ish, but
## punishes anyone caught in front of its long cone wind-up.
##
## The only reason this class exists is to override the WIND_UP
## telegraph: the base Enemy class draws a circle arc, which is wrong
## for a directional cone hitbox — the player needs to see WHERE the
## cone will land so they can sidestep, not just "an attack is coming
## from here." Drawing the actual cone shape makes the windup readable
## and lets sidestepping become a learnable skill.
func _draw_attack_telegraph(icon_dir: Vector2, telegraph_color: Color) -> void:
	# Defer to base behavior if the equipped weapon isn't a persistent
	# hitbox — robustness against runtime swaps.
	if not (weapon is PersistentHitboxWeapon):
		super(icon_dir, telegraph_color)
		return
	var ph: PersistentHitboxWeapon = weapon

	# Build the cone outline in local space and rotate it to point at
	# icon_dir. We don't have a transform stack here (draw_* is unwrapped),
	# so we rotate each point manually.
	var aim_angle: float = icon_dir.angle()

	match ph.shape_kind:
		PersistentHitbox.ShapeKind.CONE:
			_draw_cone_telegraph(aim_angle, ph.length, ph.cone_angle_degrees, telegraph_color)
		PersistentHitbox.ShapeKind.RECTANGLE:
			_draw_rect_telegraph(aim_angle, ph.length, ph.rect_width, telegraph_color)

## Outline the cone with an arc of points at the far edge, plus the
## two side lines from origin to the arc endpoints. The fill is drawn
## as a faint polygon so the player can see the danger zone at a glance
## without losing track of enemies behind it.
func _draw_cone_telegraph(aim_angle: float, length: float,
		cone_angle_degrees: float, telegraph_color: Color) -> void:
	var half_rad: float = deg_to_rad(cone_angle_degrees * 0.5)
	var arc_steps: int = 8
	var pts: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	for i in range(arc_steps + 1):
		var t: float = float(i) / float(arc_steps)
		var local_ang: float = lerp(-half_rad, half_rad, t)
		var world_ang: float = aim_angle + local_ang
		pts.append(Vector2(cos(world_ang), sin(world_ang)) * length)

	# Faint fill — same color, much lower alpha — so the cone reads as
	# a "warning area" rather than an obstruction.
	var fill: Color = Color(telegraph_color.r, telegraph_color.g, telegraph_color.b, telegraph_color.a * 0.35)
	draw_colored_polygon(pts, fill)

	# Outline. Thicker stroke at the parry-window stage matches the
	# urgency of the body flash.
	var thickness: float = 2.5 if telegraph_color.r > 0.9 and telegraph_color.g < 0.5 else 2.0
	var n: int = pts.size()
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		draw_line(a, b, telegraph_color, thickness)


## Outline the rectangle (beam) with four sides + faint fill. Used by
## any future enemies that wield rectangle-shape persistent hitboxes.
func _draw_rect_telegraph(aim_angle: float, length: float, rect_width: float,
		telegraph_color: Color) -> void:
	var hw: float = rect_width * 0.5
	var local_pts: PackedVector2Array = PackedVector2Array([
		Vector2(0, -hw),
		Vector2(length, -hw),
		Vector2(length, hw),
		Vector2(0, hw),
	])
	var pts: PackedVector2Array = PackedVector2Array()
	var c: float = cos(aim_angle)
	var s: float = sin(aim_angle)
	for p in local_pts:
		pts.append(Vector2(p.x * c - p.y * s, p.x * s + p.y * c))

	var fill: Color = Color(telegraph_color.r, telegraph_color.g, telegraph_color.b, telegraph_color.a * 0.35)
	draw_colored_polygon(pts, fill)

	var thickness: float = 2.5 if telegraph_color.r > 0.9 and telegraph_color.g < 0.5 else 2.0
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		draw_line(a, b, telegraph_color, thickness)
