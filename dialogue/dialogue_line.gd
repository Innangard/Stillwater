class_name DialogueLine
extends Resource
## A single line of dialogue. Speaker name + text.
## Speaker can be empty for narration / unnamed text.

@export var speaker: String = ""
@export_multiline var text: String = ""
