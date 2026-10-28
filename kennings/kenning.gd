class_name Kenning
extends Resource
## A Norse-style title the player can earn and equip for run-long bonuses.
## Persists across deaths (it's meta-progression — the dead-island setting
## says these are *names the gods grant a soul who has done something
## worthy*; they don't unstick when you die). Up to 4 equipped at a time;
## the loadout itself also persists in GameState so the player isn't
## punished for tinkering between runs.
##
## Design notes for the catalog author:
##   - Starter kennings: small numbers (±5–10%), unlocked early, no tradeoff.
##   - Mid kennings: ±15%, gated on a quest or area completion.
##   - Boss kennings: ±20–25%, or grant a full element immunity (multiplier 0.0).
##   - Tradeoff kennings: bigger numbers on BOTH sides (e.g. +25% damage
##     dealt with +15% damage taken). These are build-defining, so they
##     should feel chunky.
##
## A single kenning can layer effects (overall + element + weapon-type).
## The aggregate is composed multiplicatively across all 4 equipped
## kennings in KenningManager, which mirrors how StatusEffectComponent
## composes status modifiers. This keeps the math predictable.

enum Category {
	OFFENSE,
	DEFENSE,
	ELEMENTAL,
	MOBILITY,
	UTILITY,
}

## Which family of weapons a damage_dealt_multiplier applies to. ANY = all.
## Maps onto Weapon.category strings ("melee", "ranged", "spell").
enum WeaponFilter {
	ANY,
	MELEE,
	RANGED,
	SPELL,
}

## Runtime condition gating this kenning's stat multipliers. ALWAYS is the
## default (kenning is unconditionally active — every pre-existing kenning
## behaves exactly as before). HEALTH_BELOW / HEALTH_ABOVE gate the stat
## multipliers on the player's current HP fraction — "clutch" kennings
## (Noose-Breaker: +15% move speed while below half health) use these.
##
## IMPORTANT: the condition gates the MULTIPLIER fields (damage dealt/taken,
## element mults, move speed, dash cooldown) but deliberately NOT
## max_health_bonus. A max-HP bonus conditioned on your HP fraction is
## circular (the fraction depends on max HP), and max HP is only recomputed
## on loadout changes anyway — it would go stale the moment HP crossed the
## threshold mid-combat. Keep conditional kennings to multiplier effects.
enum Condition {
	ALWAYS,
	HEALTH_BELOW,
	HEALTH_ABOVE,
}


# ---------------- Identity ----------------

@export_group("Identity")
## Unique save-key. Snake_case, e.g. "wolf_friend". Used in GameState dicts
## and as the lookup key for save/load.
@export var kenning_id: String = ""
## The kenning itself — a Norse compound title shown in the UI.
@export var display_name: String = "Unnamed-One"
## Optional second line. Old-skald style: "He who walks the whale-road."
@export var epithet: String = ""
## Plain-language description of what the kenning DOES. Shown in the
## detail area. Keep to 1–3 short sentences.
@export_multiline var description: String = ""
## Flavor text rendered in italics under the description. Lore voice.
@export_multiline var flavor_text: String = ""
@export var icon: Texture2D
@export var category: Category = Category.OFFENSE


# ---------------- Unlock ----------------

@export_group("Unlock")
## The single GameState flag that unlocks this kenning. The KenningManager
## listens on story_flag_set and unlocks any kenning whose unlock_flag now
## matches. Empty string = unlocked from the start (good for one or two
## starter options so the player isn't loadout-empty on first launch).
##
## Conventions used in the catalog:
##   - "boss_dead_<boss_id>"        for boss kennings (set by GameState.mark_boss_dead)
##   - "quest_<quest_id>"           for quest kennings (set by QuestManager.turn_in_quest)
##   - "arch_activated_<arch_id>"   for area-discovery kennings
##   - any custom flag the user wants to set elsewhere
@export var unlock_flag: String = ""
## Single-sentence hint shown on the LOCKED entry in the catalog. Tells the
## player WHERE to look without spelling out the exact action. Good: "Bring
## down the bone-king beneath Sprekken." Bad: "Set boss_dead_skeleton_king."
@export var unlock_hint: String = "Unknown deeds will earn this name."

## If true, this kenning does NOT appear in the catalog at all while it's
## locked — it only shows up once unlocked. Used for "surprise" rewards
## where the existence of the kenning would itself be a spoiler. Boss
## kennings use this so the player doesn't see "Bone-King's-Bane (locked)"
## sitting in the catalog before they know there's a bone king. Default
## false: locked kennings show with a hint, which is the normal pattern
## for area / quest gated unlocks where the existence is part of the
## breadcrumb trail toward unlocking it.
@export var hidden_when_locked: bool = false


# ---------------- Combat — broad multipliers ----------------

@export_group("Combat — Overall")
## Multiplier on all damage you DEAL. 1.10 = +10%.
## If weapon_filter is set, the multiplier ONLY applies to that family.
@export var damage_dealt_multiplier: float = 1.0
@export var weapon_filter: WeaponFilter = WeaponFilter.ANY
## Multiplier on all damage you TAKE. 0.85 = 15% damage reduction.
@export var damage_taken_multiplier: float = 1.0


# ---------------- Combat — per-element ----------------

@export_group("Combat — Element")
## Damage-dealt multipliers per element type, keyed by Weapon.Element int.
## Example: { Weapon.Element.FIRE: 1.25 } = +25% fire damage. Stacks
## multiplicatively with damage_dealt_multiplier.
@export var element_damage_multipliers: Dictionary = {}
## Damage-taken multipliers per incoming element. 0.0 = full immunity to
## that element. 0.5 = halved. Stacks multiplicatively with
## damage_taken_multiplier and with armor's element_multipliers.
@export var element_resistance_multipliers: Dictionary = {}


# ---------------- Mobility / vitality ----------------

@export_group("Mobility & Vitality")
## Movement speed multiplier. 1.10 = 10% faster.
@export var move_speed_multiplier: float = 1.0
## Dash cooldown multiplier. 0.8 = 20% shorter cooldown.
@export var dash_cooldown_multiplier: float = 1.0
## Additive max HP bonus. Applied at run start.
@export var max_health_bonus: float = 0.0
## Immunity to all BINDING effects — nets, grabs, roots, drags (any
## StatusEffect with binding == true) — and to pull impulses (negative
## knockback). The Net-Cutter boss kenning uses this. Boolean rather
## than a multiplier because partial binding resistance reads terribly
## in play ("my root was 40% shorter?"); binding immunity is all or
## nothing. Respects the kenning's Condition like every multiplier.
@export var binding_immunity: bool = false


# ---------------- Condition ----------------

@export_group("Condition")
## When this kenning's multipliers apply. ALWAYS = unconditional (default;
## all pre-existing kennings). HEALTH_BELOW = active while player HP is at
## or below condition_fraction of max. HEALTH_ABOVE = active while HP is
## above condition_fraction of max.
@export var condition: Condition = Condition.ALWAYS
## HP fraction threshold for HEALTH_BELOW / HEALTH_ABOVE. 0.5 = half health.
## Ignored when condition == ALWAYS.
@export_range(0.0, 1.0) var condition_fraction: float = 0.5


# ---------------- Visual ----------------

@export_group("Visual")
## Accent color for the catalog tile (the left-edge stripe and the title
## glyph color). Pick something that hints at the kenning's domain — warm
## ember for fire-themed, sea-blue for sea-themed, bone-white for death.
@export var tier_color: Color = Color(0.75, 0.65, 0.40)


# ============================================================================
# HELPERS
# ============================================================================

## Is this kenning's stat package currently active? Reads player HP from
## RunState (the mirror the Player writes every health change), so this is
## two float reads and a compare — safe for the combat hot path, where
## KenningManager's aggregate getters call it per equipped kenning per frame.
##
## Boundary semantics: HEALTH_BELOW is inclusive (<=) so a kenning gated at
## 0.5 activates exactly at half health — "below half" in the UI copy reads
## naturally as "at or below." HEALTH_ABOVE is the strict complement (>), so
## a BELOW-0.5 and an ABOVE-0.5 kenning can never both be active or both be
## inactive at the same instant.
func is_active() -> bool:
	match condition:
		Condition.ALWAYS:
			return true
		Condition.HEALTH_BELOW:
			return _health_fraction() <= condition_fraction
		Condition.HEALTH_ABOVE:
			return _health_fraction() > condition_fraction
	return true


## Player HP fraction from RunState. Defensive against max_health == 0
## (can only happen before the first Player _ready writes it; returning
## 1.0 then means HEALTH_BELOW kennings read "full health, inactive,"
## which is the safe default).
func _health_fraction() -> float:
	if RunState.max_health <= 0.0:
		return 1.0
	return RunState.current_health / RunState.max_health


## Does this kenning have any negative side (so the UI can mark it
## "tradeoff")? Used for visual flagging only; doesn't affect math.
func has_tradeoff() -> bool:
	if damage_dealt_multiplier < 1.0:
		return true
	if damage_taken_multiplier > 1.0:
		return true
	if move_speed_multiplier < 1.0:
		return true
	if dash_cooldown_multiplier > 1.0:
		return true
	if max_health_bonus < 0.0:
		return true
	for v in element_damage_multipliers.values():
		if float(v) < 1.0:
			return true
	for v in element_resistance_multipliers.values():
		if float(v) > 1.0:
			return true
	return false


## Build the human-readable list of bullets shown in the UI detail panel.
## Order: broad mults first, then element, then mobility/vitality. Skips
## any field that's at its neutral value (1.0 or 0.0).
func format_effect_lines() -> Array[String]:
	var lines: Array[String] = []

	if damage_dealt_multiplier != 1.0:
		var pct: int = int(round((damage_dealt_multiplier - 1.0) * 100.0))
		var prefix: String = "+" if pct >= 0 else ""
		var scope: String = ""
		match weapon_filter:
			WeaponFilter.MELEE:  scope = " (melee)"
			WeaponFilter.RANGED: scope = " (ranged)"
			WeaponFilter.SPELL:  scope = " (spell)"
			_:                   scope = ""
		lines.append("%s%d%% damage dealt%s" % [prefix, pct, scope])

	if damage_taken_multiplier != 1.0:
		var pct: int = int(round((damage_taken_multiplier - 1.0) * 100.0))
		var prefix: String = "+" if pct >= 0 else ""
		lines.append("%s%d%% damage taken" % [prefix, pct])

	# Per-element damage dealt
	for k in element_damage_multipliers.keys():
		var mult: float = float(element_damage_multipliers[k])
		if mult == 1.0:
			continue
		var pct: int = int(round((mult - 1.0) * 100.0))
		var prefix: String = "+" if pct >= 0 else ""
		lines.append("%s%d%% %s damage dealt" % [prefix, pct, _element_name(int(k))])

	# Per-element resistance — special-case 0.0 as "immune"
	for k in element_resistance_multipliers.keys():
		var mult: float = float(element_resistance_multipliers[k])
		if mult == 1.0:
			continue
		if mult == 0.0:
			lines.append("Immune to %s" % _element_name(int(k)))
			continue
		var pct: int = int(round((mult - 1.0) * 100.0))
		var prefix: String = "+" if pct >= 0 else ""
		lines.append("%s%d%% %s damage taken" % [prefix, pct, _element_name(int(k))])

	if move_speed_multiplier != 1.0:
		var pct: int = int(round((move_speed_multiplier - 1.0) * 100.0))
		var prefix: String = "+" if pct >= 0 else ""
		lines.append("%s%d%% move speed" % [prefix, pct])

	if dash_cooldown_multiplier != 1.0:
		# A LOWER cooldown is the BUFF — invert sign so the UI reads "faster dash".
		# dash_cd 0.8 → pct -20 → display "+20% faster" (less cooldown).
		# dash_cd 1.2 → pct +20 → display "-20% slower" (more cooldown, penalty).
		var pct: int = int(round((dash_cooldown_multiplier - 1.0) * 100.0))
		var prefix: String = "+" if pct <= 0 else "-"
		lines.append("%s%d%% dash cooldown" % [prefix, absi(pct)])

	if max_health_bonus != 0.0:
		var prefix: String = "+" if max_health_bonus > 0.0 else ""
		lines.append("%s%d max HP" % [prefix, int(max_health_bonus)])

	if binding_immunity:
		lines.append("Immune to nets, grabs, and roots")

	if lines.is_empty():
		lines.append("(no mechanical effect)")

	# Condition rider — appended LAST so it reads as a qualifier on
	# everything above it, matching how the math actually gates.
	match condition:
		Condition.HEALTH_BELOW:
			lines.append("(only while at or below %d%% health)" % int(round(condition_fraction * 100.0)))
		Condition.HEALTH_ABOVE:
			lines.append("(only while above %d%% health)" % int(round(condition_fraction * 100.0)))

	return lines


## Element-int → display name. Kept local rather than reaching into Weapon
## so the UI doesn't depend on the weapon module being loaded.
static func _element_name(elem: int) -> String:
	match elem:
		0: return "physical"
		1: return "fire"
		2: return "ice"
		3: return "lightning"
		4: return "poison"
		5: return "holy"
		6: return "dark"
	return "unknown"
