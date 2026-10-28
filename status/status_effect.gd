class_name StatusEffect
extends Resource
## A status effect definition. This is the DATA — the rules of how burn,
## poison, freeze, etc. behave. Author one .tres per effect type and
## reference it everywhere it's needed.
##
## A StatusEffect is NOT applied directly. Weapons and other sources use
## StatusApplication to specify "this effect, with this chance". Each
## entity has a StatusEffectComponent that holds the runtime state
## (remaining duration, stack count) — see ActiveEffect.
##
## For exotic effects that need custom logic (curse that summons spirits,
## brand that explodes on death, etc.), subclass this and override the
## virtual methods at the bottom.

enum StackBehavior {
	## Reapplying refreshes the duration to full but doesn't increase stacks.
	REFRESH,
	## Reapplying adds a stack (up to max_stacks) AND refreshes duration.
	## Damage per tick scales with stacks.
	ADD_STACK,
	## Reapplying does nothing while the effect is already active.
	IGNORE,
}

@export_group("Identity")
## Used for stacking lookups. Same id = same effect bucket on a target.
## Different ids stack independently (you can be burned AND poisoned).
@export var effect_id: StringName = &"unnamed"
@export var display_name: String = "Effect"
@export_multiline var description: String = ""
@export var icon: Texture2D

@export_group("Timing")
## How long the effect lasts (seconds). Use -1 for permanent until cleansed.
@export var duration: float = 3.0
## How often on_tick fires (seconds). 0 = never tick (pure stat modifier).
@export var tick_interval: float = 0.0

@export_group("Damage Over Time")
## Damage applied per tick. Multiplied by current stacks.
@export var damage_per_tick: float = 0.0
@export var damage_element: Weapon.Element = Weapon.Element.PHYSICAL

@export_group("Healing Over Time")
## HP restored per tick. Multiplied by current stacks. Uses tick_interval.
@export var heal_per_tick: float = 0.0

@export_group("Stat Modifiers")
## Multiplier applied to target's movement speed. 0.5 = halved, 1.5 = haste.
@export var speed_multiplier: float = 1.0
## Multiplier applied to incoming damage. 1.5 = vulnerable, 0.5 = resist.
@export var damage_taken_multiplier: float = 1.0
## Multiplier applied to damage the target deals. 0.5 = weakened.
@export var damage_dealt_multiplier: float = 1.0
## If true, target cannot move or attack while the effect is active.
@export var prevents_action: bool = false
## Marks this effect as a physical BINDING — a net, grab, root, or drag
## that holds the body in place (as opposed to elemental slows like
## freeze, which are resisted through element channels). The Net-Cutter
## kenning grants immunity to all binding effects: StatusEffectComponent
## checks this flag at apply() time for player-group owners, and the
## player's knockback receiver uses the same immunity to negate pull
## (negative-knockback) impulses. Mark true on: netted, dragged_under,
## snare. Leave false on ordinary slows (freeze, rope_drag, wave_slow,
## waterlogged) — those hamper movement but nothing has hold of you.
@export var binding: bool = false

@export_group("Stacking")
@export var stack_behavior: StackBehavior = StackBehavior.REFRESH
## Hard cap on stacks (only used by ADD_STACK).
@export_range(1, 99) var max_stacks: int = 1

@export_group("Visual")
## Tint color blended onto the entity sprite while active.
## Set alpha = 0 to disable tinting.
@export var tint_color: Color = Color(1, 1, 1, 0)
## How strongly the tint blends in (0 = none, 1 = full replacement).
@export_range(0.0, 1.0) var tint_intensity: float = 0.5


# --- Virtual hooks for special effects (subclass to override) ---

## Called when the effect is first applied to a target.
## Default does nothing; subclasses can do special setup.
func on_apply(_target: Node, _stacks: int) -> void:
	pass

## Called every tick_interval seconds. Default deals damage_per_tick * stacks
## via the StatusEffectComponent's tick_damage signal — override only if you
## want completely custom tick behavior (e.g., teleport target, summon).
## Returning true skips the default damage logic.
func on_tick(_target: Node, _stacks: int) -> bool:
	return false

## Called when the effect expires or is cleansed.
func on_remove(_target: Node) -> void:
	pass
