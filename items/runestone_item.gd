class_name RunestoneItem
extends Item
## A rune bearing a passive stat bonus. Collected runes accumulate in the
## rune collection (separate from inventory) and their bonuses stack
## additively. Each rune grants a small percentage increase to a single
## stat — the roguelite build system is "stack runes, shape your run."
##
## The rune's stat type is set per .tres (data-driven). The conduit
## (slate/bone/wood/gold) gates which act the rune can appear in and
## scales the bonus magnitude.
##
## Rune identity:
##   rune letter (fehu, uruz, ...) → which stat
##   conduit (slate, bone, wood, gold) → magnitude + act gate
##   rune_symbol → Elder Futhark glyph for display

## Which stat this rune boosts when collected.
enum RuneStat {
	MELEE_DAMAGE,        ## +X% melee damage
	PROJECTILE_DAMAGE,   ## +X% projectile/ranged damage
	ALL_DAMAGE,          ## +X% all outgoing damage
	DAMAGE_RESISTANCE,   ## +X% damage reduction (incoming)
	FIRE_RESIST,         ## +X% fire element resistance
	ICE_RESIST,          ## +X% ice element resistance
	LIGHTNING_RESIST,    ## +X% lightning element resistance
	POISON_RESIST,       ## +X% poison element resistance
	MOVE_SPEED,          ## +X% movement speed
	MAX_HP,              ## +X% max health
	SHIELD_REDUCTION,    ## +X% shield block effectiveness
	MELEE_SIZE,          ## +X% melee weapon hitbox scale
	DASH_CHARGES,        ## +X extra dashes before cooldown (flat)
	SWAP_SPEED,          ## +X% weapon swap speed (reduces duration)
	DASH_COOLDOWN,       ## +X% dash cooldown reduction
	PROJECTILE_SPEED,    ## +X% projectile speed
	RUNE_REROLLS,        ## +X rerolls per run (flat)
}

## Which conduit this rune was carved into. Determines act availability
## and serves as a visual rarity tier.
enum RuneConduit {
	SLATE,  ## Act 1 — common, weakest bonuses
	BONE,   ## Act 1 — common
	WOOD,   ## Act 2 — mid-tier
	GOLD,   ## Act 3 — strongest bonuses, rarest
}

@export_group("Rune")
## The Elder Futhark symbol (ᚠ, ᚢ, etc.). Display / lore only.
@export var rune_symbol: String = ""
## Which stat this rune boosts.
@export var rune_stat: RuneStat = RuneStat.MELEE_DAMAGE
## The bonus value. For percentage stats this is the percent (e.g. 2.0
## means +2%). For flat stats (DASH_CHARGES, RUNE_REROLLS) this is the
## count (e.g. 1.0 means +1 charge).
@export var bonus_value: float = 1.0
## Conduit determines act availability and visual tier.
@export var conduit: RuneConduit = RuneConduit.SLATE
## Drop weight — lower values are rarer. Default 10 is "common";
## stronger rune letters use 5 (uncommon) or 3 (rare).
@export var drop_weight: float = 10.0


func _init() -> void:
	if category == "misc":
		category = "runestone"
	max_stack = 99


## Human-readable name for the stat this rune boosts.
static func stat_display_name(stat: RuneStat) -> String:
	match stat:
		RuneStat.MELEE_DAMAGE:      return "Melee Damage"
		RuneStat.PROJECTILE_DAMAGE: return "Projectile Damage"
		RuneStat.ALL_DAMAGE:        return "All Damage"
		RuneStat.DAMAGE_RESISTANCE: return "Damage Resistance"
		RuneStat.FIRE_RESIST:       return "Fire Resistance"
		RuneStat.ICE_RESIST:        return "Ice Resistance"
		RuneStat.LIGHTNING_RESIST:  return "Lightning Resistance"
		RuneStat.POISON_RESIST:     return "Poison Resistance"
		RuneStat.MOVE_SPEED:        return "Move Speed"
		RuneStat.MAX_HP:            return "Max HP"
		RuneStat.SHIELD_REDUCTION:  return "Shield Effectiveness"
		RuneStat.MELEE_SIZE:        return "Melee Weapon Size"
		RuneStat.DASH_CHARGES:      return "Dash Charges"
		RuneStat.SWAP_SPEED:        return "Swap Speed"
		RuneStat.DASH_COOLDOWN:     return "Dash Cooldown"
		RuneStat.PROJECTILE_SPEED:  return "Projectile Speed"
		RuneStat.RUNE_REROLLS:      return "Rune Rerolls"
	return "Unknown"


## Format the bonus as a display string: "+2% Melee Damage" or "+1 Dash Charges".
func format_bonus() -> String:
	var is_flat: bool = rune_stat == RuneStat.DASH_CHARGES \
		or rune_stat == RuneStat.RUNE_REROLLS
	if is_flat:
		return "+%d %s" % [int(bonus_value), stat_display_name(rune_stat)]
	return "+%.0f%% %s" % [bonus_value, stat_display_name(rune_stat)]


## Conduit display name for UI.
static func conduit_display_name(c: RuneConduit) -> String:
	match c:
		RuneConduit.SLATE: return "Slate"
		RuneConduit.BONE:  return "Bone"
		RuneConduit.WOOD:  return "Wood"
		RuneConduit.GOLD:  return "Gold"
	return "Unknown"


## Color tint associated with a conduit tier — used by the runes UI
## to visually distinguish act tiers at a glance.
static func conduit_color(c: RuneConduit) -> Color:
	match c:
		RuneConduit.SLATE: return Color(0.55, 0.55, 0.58)
		RuneConduit.BONE:  return Color(0.82, 0.78, 0.70)
		RuneConduit.WOOD:  return Color(0.55, 0.72, 0.45)
		RuneConduit.GOLD:  return Color(0.95, 0.80, 0.35)
	return Color.WHITE
