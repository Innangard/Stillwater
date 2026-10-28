class_name ConsumableItem
extends Item
## An item that does something when used (typically from inventory click).
## Subclasses can override on_use() for fancier behavior; the base class
## handles the most common case: heal HP and/or apply a status effect.

@export_group("Consumable")
## HP healed on use (0 = no healing).
@export var heal_amount: float = 0.0
## Optional status effect to apply to the user (haste potion, fire shield, etc.).
@export var grants_status: StatusEffect = null


## Called when the user clicks this item in inventory (or otherwise uses it).
## Return true if the item was consumed (remove one from stack), false to keep.
func on_use(user: Node) -> bool:
	var did_something := false

	if heal_amount > 0.0:
		var hc: HealthComponent = user.get_node_or_null("HealthComponent")
		if hc and hc.current_health < hc.max_health:
			hc.heal(heal_amount)
			did_something = true

	if grants_status:
		var sc: StatusEffectComponent = user.get_node_or_null("StatusEffectComponent")
		if sc:
			sc.apply(grants_status, user)
			did_something = true

	return did_something
