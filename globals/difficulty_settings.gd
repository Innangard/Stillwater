extends Node
## Per-save difficulty profile. Chosen once when a new save is created,
## persisted in the save file, and read everywhere combat-tuning happens.
##
## The three profiles tune four enemy-side knobs (health, damage, movement
## speed, projectile speed) plus one player-side knob (out-of-combat HP
## regen). Each multiplier is read live — never cached on the enemy at
## spawn — so a future "change difficulty mid-save" feature would work
## without any extra plumbing here. Today the user picks once at New
## Game and the value sticks for the life of the save.
##
## Read paths:
##   - Enemy.gd reads enemy_health_multiplier at spawn (max_health is
##     fixed for the life of an instance, so it's set once in _ready).
##   - Enemy.gd reads enemy_speed_multiplier every physics frame.
##   - Weapon.gd reads enemy_damage_multiplier inside
##     compute_outgoing_damage when the user is not a Player.
##   - Projectile.gd reads projectile_speed_multiplier at spawn for
##     enemy-team projectiles only — player shots keep their authored
##     speed so weapon feel is consistent across difficulties.
##   - Player.gd reads player_regen_rate / player_regen_cap_fraction
##     every physics frame to drive out-of-combat healing on Easy.
##
## NOTE: No class_name — registered as autoload "DifficultySettings".

enum Difficulty { EASY, NORMAL, HARD }

## Active difficulty for the currently-loaded save. Defaults to NORMAL so
## that any path that reads multipliers BEFORE a save is loaded (e.g.
## the title screen scene's own preview, or a debug run launched from
## the editor without a save) gets baseline numbers, not surprise easy/
## hard tuning.
var current: int = Difficulty.NORMAL


## Mirror layout: each entry is the full profile for one difficulty.
## Authored as constants so the values are easy to find and audit in
## one place — adjust here and every consumer picks it up automatically.
##
## The "opposite-of-easy" relationship for Hard is intentional and the
## design intent: a player who finds Normal too easy should feel a
## symmetric increase, not a punishing one. 30% in either direction on
## health/damage and 20% on speeds keeps the game readable on Hard
## (telegraphs still register, projectiles can still be dodged) while
## making encounters genuinely tougher.
const _PROFILES := {
	Difficulty.EASY: {
		"enemy_health_multiplier": 0.7,
		"enemy_damage_multiplier": 0.7,
		"enemy_speed_multiplier": 0.8,
		"projectile_speed_multiplier": 0.8,
		# 2 HP/sec is roughly "you regain half your bar in 25 seconds of
		# walking around" — fast enough to help between fights, slow
		# enough that you can't out-heal active combat (combat suspends
		# regen anyway, see Player._physics_process).
		"player_regen_rate": 2.0,
		# Regen tops out at 50% of max HP per the design brief. Above
		# 50% the player has to use consumables/heals like normal.
		"player_regen_cap_fraction": 0.5,
	},
	Difficulty.NORMAL: {
		"enemy_health_multiplier": 1.0,
		"enemy_damage_multiplier": 1.0,
		"enemy_speed_multiplier": 1.0,
		"projectile_speed_multiplier": 1.0,
		"player_regen_rate": 0.0,
		"player_regen_cap_fraction": 0.0,
	},
	Difficulty.HARD: {
		"enemy_health_multiplier": 1.3,
		"enemy_damage_multiplier": 1.3,
		"enemy_speed_multiplier": 1.2,
		"projectile_speed_multiplier": 1.2,
		"player_regen_rate": 0.0,
		"player_regen_cap_fraction": 0.0,
	},
}


# ============================================================================
# READ API
# ============================================================================

func get_enemy_health_multiplier() -> float:
	return float(_PROFILES[current]["enemy_health_multiplier"])

func get_enemy_damage_multiplier() -> float:
	return float(_PROFILES[current]["enemy_damage_multiplier"])

func get_enemy_speed_multiplier() -> float:
	return float(_PROFILES[current]["enemy_speed_multiplier"])

func get_projectile_speed_multiplier() -> float:
	return float(_PROFILES[current]["projectile_speed_multiplier"])

func get_player_regen_rate() -> float:
	return float(_PROFILES[current]["player_regen_rate"])

func get_player_regen_cap_fraction() -> float:
	return float(_PROFILES[current]["player_regen_cap_fraction"])


# ============================================================================
# DISPLAY / NAMING
# ============================================================================

## Returns the display name for a given difficulty enum value. Used by
## the title screen for slot summaries and by the new-game difficulty
## picker for button labels.
func display_name(diff: int) -> String:
	match diff:
		Difficulty.EASY:   return "Easy"
		Difficulty.NORMAL: return "Normal"
		Difficulty.HARD:   return "Hard"
	return "Unknown"


## One-line flavor text for each difficulty, shown in the new-game
## picker. Keeps the choice meaningful without burying the player in
## numbers — the player who wants exact multipliers can find them in
## _PROFILES, but most players just want to know what the choice feels
## like.
func flavor_text(diff: int) -> String:
	match diff:
		Difficulty.EASY:
			return "Forgiving. Enemies hit lighter and slower, and you slowly recover up to half your health."
		Difficulty.NORMAL:
			return "The intended challenge. No assistance, no extra punishment, no passive healing."
		Difficulty.HARD:
			return "Brutal. Enemies are tougher, hit harder, and move faster."
	return ""


# ============================================================================
# WRITE API
# ============================================================================

## Set the active difficulty. Validated to one of the enum values; any
## out-of-range int falls back to NORMAL (defensive — a corrupted save
## file shouldn't be able to leave the game in an undefined state).
func set_difficulty(diff: int) -> void:
	if diff != Difficulty.EASY and diff != Difficulty.NORMAL and diff != Difficulty.HARD:
		current = Difficulty.NORMAL
		return
	current = diff


## Reset to NORMAL. Called when returning to the title screen so a
## subsequent New Game / Load starts from a clean baseline rather than
## inheriting whatever the last loaded save's difficulty was.
func reset_to_defaults() -> void:
	current = Difficulty.NORMAL
