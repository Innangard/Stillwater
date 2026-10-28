class_name MagicSpell
extends Weapon
## A magic spell. Lives in the player's "magic" slot (Q key).
## Currently behaves like a single-projectile ranged weapon with a mana cost
## (mana not enforced yet — that comes with the stats system later).
##
## Kept as its own class so the player has a distinct slot for spells, and
## so that future spells (AoE, beams, summons, channeled) can override
## attack() with completely different behavior without confusing the
## "ranged weapon" category.

@export_group("Spell")
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 600.0
@export var projectile_lifetime: float = 1.8
## Mana cost. Stored but not enforced yet — wire to player stats later.
@export var mana_cost: float = 10.0
@export var pierce: int = 0


func _init() -> void:
	super()
	if category == "weapon":
		category = "spell"


func attack(user: Node2D, aim: Vector2) -> void:
	if projectile_scene == null:
		push_error("MagicSpell '%s' has no projectile_scene assigned." % weapon_name)
		return

	# TODO: when stats system exists, check & spend user.mana here.

	var proj: Projectile = projectile_scene.instantiate()

	# Status buffs + (for the player) kenning multipliers fold in here.
	var effective: float = compute_outgoing_damage(user)
	var info := build_damage_info()
	info["amount"] = effective

	# Set properties BEFORE add_child — _ready uses these.
	proj.direction = aim.normalized()
	proj.speed = projectile_speed
	proj.lifetime = projectile_lifetime
	proj.pierce = pierce
	proj.damage = effective
	proj.owning_team = user.team if "team" in user else "neutral"
	proj.damage_info = info

	user.get_parent().add_child(proj)
	proj.global_position = user.global_position
