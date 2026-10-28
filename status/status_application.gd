class_name StatusApplication
extends Resource
## Wraps a StatusEffect with the chance to apply it. Used in weapon
## on_hit_effects arrays so the same StatusEffect resource can be applied
## with different probabilities by different weapons.
##
## Example: hearthbrand has 35% burn chance, dragontooth_blade has 100%.
## Both reference the same burn.tres — only the chance differs.

## The effect to attempt to apply.
@export var effect: StatusEffect
## Chance to apply, 0.0–1.0. 1.0 always applies.
@export_range(0.0, 1.0) var chance: float = 1.0
