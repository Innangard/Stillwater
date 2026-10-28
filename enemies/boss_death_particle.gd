extends Node2D
## A single particle in the boss-death ash burst. Spawned by
## BossDeathFx.play; lives `lifetime` seconds, drifting outward along
## `velocity` while shrinking and fading. Drawn as a small filled
## circle with a slight glow halo so the burst reads from a distance.
##
## Implemented as its own tiny Node2D + script (rather than using
## CPUParticles2D / GPUParticles2D) for total control over the visual
## and zero per-particle setup cost. 24 of these spawn per death;
## measured cost is negligible.

var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 1.2
var color: Color = Color(1.0, 0.6, 0.3)
var size: float = 4.0

var _t: float = 0.0
var _initial_lifetime: float = 1.2


func _ready() -> void:
	_initial_lifetime = lifetime
	z_index = 50


func _process(delta: float) -> void:
	_t += delta
	if _t >= _initial_lifetime:
		queue_free()
		return
	# Drift outward, decelerating slightly so the burst settles.
	# Cubic ease-out gives the particles a "thrown" feel — they hit
	# their peak distance quickly, then coast.
	var damping: float = 1.0 - delta * 1.5
	velocity *= maxf(damping, 0.0)
	position += velocity * delta
	queue_redraw()


func _draw() -> void:
	var t: float = clampf(_t / _initial_lifetime, 0.0, 1.0)
	# Shrink and fade. Alpha drops faster than size so the particle
	# feels like it's dispersing into smoke, not just retreating.
	var s: float = size * (1.0 - t * 0.6)
	var a: float = (1.0 - t) * (1.0 - t)  # quadratic fade
	var halo: Color = Color(color.r, color.g, color.b, a * 0.35)
	var core: Color = Color(1.0, 0.95, 0.70, a)
	# Outer halo for glow at distance.
	draw_circle(Vector2.ZERO, s * 1.8, halo)
	# Bright core.
	draw_circle(Vector2.ZERO, s, core)
