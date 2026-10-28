class_name Dialogue
extends Resource
## A sequence of dialogue lines. Authored as .tres files.
##
## Minimal version: just an array of lines. Each line has a speaker and text.
## Future extensions (not built yet, but the shape is here):
##   - Branching choices (player picks an option mid-conversation)
##   - Story-flag conditions (line only shows if GameState.has_flag(...))
##   - Effect callbacks (set_flag, give_item, etc.) that fire when a line plays
##
## For now: linear, advance-on-click, close at the end.

@export var lines: Array[DialogueLine] = []
