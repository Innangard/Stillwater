extends NPC
## The Observer at the South Cliff. First encounter plays the full lore
## introduction. Every subsequent visit (after at least one death) cycles
## through lines of curiosity, mocking, and exasperation — one set per
## death, wrapping around when the pool is exhausted.
##
## The original Dialogue resource (set in the inspector) is the first-
## time lore speech. Post-death lines are built in code so they don't
## need dozens of .tres files.

## The authored dialogue resource — used only on the very first encounter
## (death_count == 0). Set in the scene inspector as usual.
@export var first_dialogue: Dialogue


# ============================================================================
# POST-DEATH LINE POOL
# ============================================================================
# Each entry is an Array of [speaker, text] pairs forming one conversation.
# The Observer cycles through these in order, wrapping, so the player
# always gets a fresh quip until they've died 20+ times.

const POST_DEATH_LINES: Array = [
	# --- Death 1: gentle curiosity ---
	[
		["Observer", "Ah. Back already."],
		["Observer", "That was quick. Did you trip, or did something trip you?"],
		["Observer", "The arch pulled you back together nicely, at least. Off you go."],
	],
	# --- Death 2: mild amusement ---
	[
		["Observer", "Twice now. I'm starting to see a pattern."],
		["Observer", "You know, most pilgrims last at least a full day before their first return. You are... efficient."],
	],
	# --- Death 3: mocking ---
	[
		["Observer", "Three. I've begun keeping count. Don't look at me like that — someone should."],
		["Observer", "The arch is doing fine, by the way. You're giving it a real workout."],
	],
	# --- Death 4: backhanded encouragement ---
	[
		["Observer", "Still breathing. Well. Breathing again."],
		["Observer", "I once watched a pilgrim die forty-seven times before they cleared the forest. You have room to grow."],
		["Observer", "That was not encouragement."],
	],
	# --- Death 5: exasperation ---
	[
		["Observer", "You."],
		["Observer", "..."],
		["Observer", "Go north. Hit things. Try not to stand in the middle of them while you do it."],
	],
	# --- Death 6: philosophical ---
	[
		["Observer", "Do you remember dying? They never do, at first. Eventually the memories start to bleed through."],
		["Observer", "It's not pleasant. But it does make you more careful. Eventually."],
	],
	# --- Death 7: dark humor ---
	[
		["Observer", "At this point the arch knows your shape better than you do."],
		["Observer", "I think it's starting to cut corners. Did you always have that mole?"],
	],
	# --- Death 8: tired ---
	[
		["Observer", "I felt the arch fire again and thought, 'surely not.' And yet."],
		["Observer", "Go. Shoo. I have things to watch that aren't you dying repeatedly."],
	],
	# --- Death 9: resigned ---
	[
		["Observer", "Hello again."],
		["Observer", "I've stopped counting. That's not true. I just don't want to say the number out loud."],
	],
	# --- Death 10: genuine concern ---
	[
		["Observer", "...Are you alright? Truly?"],
		["Observer", "The arch rebuilds the body. The mind, it's less precise about. If things start to feel thin — tell someone. Not me. Someone who cares."],
		["Observer", "That was unkind. I do care. A little. Go on."],
	],
	# --- Death 11: bored ---
	[
		["Observer", "You again. I was watching a very interesting cloud."],
		["Observer", "It looked like a kobold. Which I suppose is fitting, given your track record."],
	],
	# --- Death 12: conspiracy ---
	[
		["Observer", "I'm beginning to suspect you're dying on purpose just to talk to me."],
		["Observer", "I'm flattered. Stop it."],
	],
	# --- Death 13: academic ---
	[
		["Observer", "Interesting. Your reassembly took point-three heartbeats longer than last time."],
		["Observer", "The arch may be getting tired of you. I didn't know they could do that."],
	],
	# --- Death 14: sarcastic advice ---
	[
		["Observer", "Quick tip: the pointy end of the sword goes toward the enemy."],
		["Observer", "Also, enemies are the ones trying to kill you. I realize that may also need clarifying."],
	],
	# --- Death 15: breaking the fourth wall slightly ---
	[
		["Observer", "Have you considered... dodging?"],
		["Observer", "It's the thing where you move your body away from the thing that's about to hit you. Revolutionary concept."],
	],
	# --- Death 16: melancholy ---
	[
		["Observer", "The Pool used to send the dead home. Now it just... churns."],
		["Observer", "And you keep walking back to the same stretch of dirt to die on it again. There's a metaphor there, but I'm too tired to find it."],
	],
	# --- Death 17: grudging respect ---
	[
		["Observer", "I'll give you this: you're persistent."],
		["Observer", "Terrible at staying alive, but persistent."],
	],
	# --- Death 18: conspiratorial ---
	[
		["Observer", "Between you and me — the goblins talk about you."],
		["Observer", "They have a name for you. I won't translate it. It's not flattering."],
	],
	# --- Death 19: fed up ---
	[
		["Observer", "No."],
		["Observer", "No, I'm not doing the speech. You know where Wickbarrow is. You know what kills you. Go figure it out."],
	],
	# --- Death 20: exhausted affection ---
	[
		["Observer", "...You're still trying."],
		["Observer", "After everything. You're still trying."],
		["Observer", "Fine. I suppose that counts for something. The smith in Wickbarrow can help. The Norn can help. I can only watch."],
		["Observer", "But I'm watching. For whatever that's worth."],
	],
]


func _open_dialogue() -> void:
	var d: Dialogue

	if GameState.death_count == 0:
		# First visit — play the full lore introduction.
		d = first_dialogue if first_dialogue else dialogue
	else:
		# Post-death — cycle through the pool.
		var pool_index: int = (GameState.death_count - 1) % POST_DEATH_LINES.size()
		d = _build_dialogue(POST_DEATH_LINES[pool_index])

	if d == null or d.lines.is_empty():
		return

	DialogueUI.show_dialogue(d, station_name if station_name != "" else "", recipes)


func _build_dialogue(line_data: Array) -> Dialogue:
	var d := Dialogue.new()
	for entry in line_data:
		var line := DialogueLine.new()
		line.speaker = entry[0]
		line.text = entry[1]
		d.lines.append(line)
	return d
