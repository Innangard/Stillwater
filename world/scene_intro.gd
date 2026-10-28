class_name SceneIntro
extends Node
## A small helper node that triggers SceneTransition.play_opening_lore
## on _ready. Gated on a story flag so the intro plays only once per
## save — re-loading the save (or saving inside the scene before
## crossing out of it) skips the narration.
##
## Usage: drop one of these as a child of any region scene that wants
## a narrated reveal. Set `intro_lore_text` to the narration content
## and `intro_flag` to a unique story flag name (typically
## `<scene>_intro_played`). The first time the scene loads, the intro
## plays and the flag is set. Subsequent loads see the flag and skip.
##
## The flag is set BEFORE the tween starts, so even if the player
## somehow saved during the intro (impossible in practice — tree is
## paused, save menu can't open — but conceptually), the load would
## correctly skip the re-played intro.

## The lore content shown over the black overlay. Multi-line text is
## supported; the label wraps long lines. Leave empty to no-op (the
## helper does nothing if there's no text to show).
@export_multiline var intro_lore_text: String = ""

## Story flag that gates the intro. Set once after the intro starts.
## If the flag is already set when _ready fires, the intro is skipped.
## Leave empty to play the intro EVERY scene load (rare — most callers
## want one-shot behavior).
@export var intro_flag: String = ""


func _ready() -> void:
	if intro_lore_text == "":
		return
	# One-shot gate: skip if the flag is already set. This catches
	# save reloads and any future re-entry paths.
	if intro_flag != "" and GameState.has_flag(intro_flag):
		return
	# Set the flag IMMEDIATELY (before the tween). This ensures save
	# resilience: if a save fires anywhere during the intro sequence
	# (currently impossible — tree is paused — but defensive coding),
	# the saved state already shows the intro as played.
	if intro_flag != "":
		GameState.set_flag(intro_flag)
	SceneTransition.play_opening_lore(intro_lore_text)
