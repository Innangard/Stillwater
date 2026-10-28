# Jörmund — Boss Roster

This is the proposed boss lineup for the player's south → west → north → NE → center journey, plus three optional bosses on the eastern fork, plus the final king. The two existing bosses (Skeleton King, Cinder Sovereign) are slotted into the new flow rather than rebuilt.

**Design principles applied to every boss in the list:**

1. **One new mechanical "verb" per boss.** The first encounter teaches a thing the player has not had to do before. The boss is the test of whether they learned it.
2. **HP scales with player kit, not boss complexity.** Earlier bosses have less HP because the player has fewer kennings, no rune stockpile, weaker weapon tier. The middle of the curve is widest. Final boss is dramatic, not bloated.
3. **Every boss drops a kenning.** That's the meta-progression promise — beat it, get a permanent title slot.
4. **Distinct silhouette and palette.** Both existing bosses are circle-bodies with crowns. As art comes in, each boss below should have a *shape* readable at one glance from across a darkened arena.
5. **Phase shifts change behaviour, not just numbers.** No "now I do 20% more damage and wind up faster." A phase shift should be a *new fight* sharing an arena with the old one.

---

## Difficulty / HP curve (rule of thumb)

Player at base 100 HP, weapon DPS ~30 early to ~40 mid-late, plus kennings and runes. Targeting **25–60-second fights** for the curve — long enough to test a pattern twice, short enough that one death isn't catastrophic.

| Slot | Boss | Suggested HP | Suggested fight time |
|---|---|---|---|
| 1 | Skeleton King *(existing)* | 1000 | ~30s |
| 2 | Galgi the Bound | 1200 | ~35s |
| 3 | The Drowned Crone | 1400 | ~40s |
| 4 | Cinder Sovereign *(existing)* | 1600 | ~45s |
| 5 | Sindri's Apprentice | 1700 | ~50s |
| 6 | Gymir of the Hollow Mountain | 1800 | ~50s |
| 7 | Skadi the Hoarfrost | 1900 | ~55s |
| 8 | Hrímfaxi's Get (mother + pups) | 1400 + 200×2 = 1800 | ~55s |
| 9 | The Ash-Sprout | 2000 (with damage-reduction trunk) | ~60s |
| 10 | Eir of Broken Wings | 1500 + 1200 revive = 2700 | ~75s |
| 11 | Heimdall's Echo | 2400 | ~60s |
| 12 | **The Tyrant King → Níðhöggr** | 1000 + 1000 + 1500 = 3500 | ~90s |
| E1 | Gullveig Thrice-Burned | 800 × 3 rounds, no full heal | ~70s |
| E2 | The Howling Hollow (Garmr-spawn) | 2200 | ~60s |
| E3 | Sea-Mire (Jörmungandr's spawn) | 2500 | ~70s |

Total main path: 11 named bosses + the king = 12 fights to credits, matching the original "around 12" target.

---

# MAIN PATH

## Boss 1 — The Skeleton King *(existing)*

**Location (proposed):** A barrow-mound mausoleum south of Wickbarrow, reached via the eastern path out of town. The approach is a short corridor of consecrated tombs the player walks through after the South arch.

**Why he is here:** He was the first king-soul to refuse the Pool, three centuries before Hjarrandi. He never built a kingdom, just a tomb of bones. He is what Hjarrandi *would* have been if Hjarrandi were stupid. He is a foreshadow.

**Mechanics already implemented are good** — three-attack rotation (toss / fan / burst), phase 2 at 30% spawns four stationary pillars. The pillars are the test: they break sight-lines and limit dash paths.

**Skill tested:** Reading projectile spreads and using cover.

**Kenning drop:** Bone-King's-Bane *(already in game)* — +18% damage dealt.

**Visual tuning notes:** The phase-2 purple tint is good. The current crown silhouette reads. Once art comes in, give him a *high* silhouette (very tall crown, hunched shoulders) — he should be visually skeletal and *tall*.

---

## Boss 2 — Galgi the Bound

**Concept:** A draugr of corpses bound together by rope, hanged from a gallows-tree. Odin hanged himself on Yggdrasil for nine nights to learn the runes; Galgi is that image gone wrong — a knot of people who refused the Pool and tied themselves up rather than be sorted into individuals at the water's edge.

**Location:** A sunken grove between Wickbarrow and the western marshes. There is one tree in the middle of the room. Galgi hangs from it at fight start.

**Phase 1 — Hanged:** Stationary. Swings on his rope. Attacks:
- **Pendulum slam.** Swings forward through the arena along an arc. Telegraphs by lifting the gallows beam (~0.7s windup). One-shot to a careless player at low HP, but lateral dodge is trivial — the arc is fixed.
- **Rope-arm grab.** Three rope-tendrils erupt from the floor at telegraphed positions and grab; a grabbed player is slowed 80% for 1.5s. Two-rune chance per fight to break early.
- **Choke-cough.** Stationary AoE cone of black blood vomit out of his mouth. Burns like the burn status. Dodge inward.

**Phase 2 — Cut Loose (50% HP):** The rope frays from damage and Galgi falls. He is now mobile but slow (max_speed ~80). Same attacks, plus:
- **Trailing rope drag.** The cut rope drags behind him as he moves and applies a brief slow on contact. Read his movement direction to anticipate where the rope sweeps.

**Skill tested:** Movement *under threat of being held still*. The rope-arms reward players who keep moving and punish players who stand still to attack.

**Stats:** HP 1200, speed 0 → 80 in phase 2, base contact damage 12.

**Kenning drop:** **Noose-Breaker** — *"He cut himself down."* +15% movespeed when below 50% HP. (Comeback kenning, build-defining for tank-style play.)

**Visual:** Suspended figure made of three-or-four lashed corpses, head lolling. In phase 2 he shambles forward on multiple legs, dragging the cut rope. Black blood drips from every joint. *Telegraphs:* the gallows beam lifts visibly before pendulum slam; floor-cracks pulse where the rope-arms will emerge.

---

## Boss 3 — The Drowned Crone (Rán of the Reefs)

**Concept:** Rán in Norse myth caught drowning sailors in her net and dragged them to her hall under the sea. The Drowned Crone is one of her acolytes — a sea-witch who never let go of the net even after she herself drowned.

**Location:** The Wreck Shoals (or a flooded saltmarsh shrine). Half the arena is shin-deep water. She stands on the prow of a beached wreck.

**Phase 1 — Net & Hook:**
- **Net cast.** Throws a glowing-rope net in a wide forward arc; if it catches the player, pulls them 200px toward her and roots them for 1s. Dash i-frames break the catch entirely; running sideways at cast time avoids it.
- **Fish-hook scythe sweep.** Wide melee arc when player is in range. Heavy knockback; pushes player back into the water.
- **Wave pulse.** Stomps the wreck prow. A radial water-wave expands; slows the player 40% on contact.

**Phase 2 — The Drowning (40% HP):** Floods more of the arena. Now ~80% water. Slows everyone — including her. Adds:
- **Summon two Drowned Sailors.** Slow, walking draugr in heavy armour. Two-handed sword swings. They are not the threat — they are the *clock pressure* during the net + scythe combo.
- **Drag under.** New finisher: if the net pulls a player to her, the next attack pulls them under the water for 1.5s (damage-over-time, then surface). Punishes greedy net-eaten players brutally. *Telegraph:* she grabs the rope with both hands instead of swinging the scythe.

**Skill tested:** Anti-CC management. Players who don't time dashes around her net casts will get caught and chained. Players who do can fight her safely from outside her hook range.

**Stats:** HP 1400, speed 70 (slow), contact 10, net-pull-then-drag 35.

**Kenning drop:** **Net-Cutter** — immunity to all pull / root effects.

**Visual:** Bent old woman in waterlogged kelp-coloured robes. One eye replaced by a shell. Carries a long rope-net braided with bone. Standing on a half-rotted longship prow that lists with the tide. Phase 2: the prow capsizes and she rises wading from the water.

---

## Boss 4 — Cinder Sovereign *(existing)*

**Location (proposed):** Brann volcano — *far western tip*, near the western arch. Currently positioned correctly in the code.

**Mechanics are excellent as-is.** The four-action cycle (pyre cone / cinder pod / summon / beam in phase 2), the fixed engagement range, the minion-cap-that-skips-summon, the shape-aware telegraphs — this is the cleanest boss in the game's current code. Leave it alone except as noted below.

**Recommended polish:**
- Phase-2 trigger at 40% means the beam shows up about 20 seconds into a 45-second fight. Good.
- The minion-cap-skips-summon is a hidden mechanic; consider a subtle visual cue ("she goes to summon and the gesture *fizzles*" — a small particle puff) so players who notice the cap can learn to delay killing minions strategically.
- The pyre cone (170px) and the engagement range (180px) put the player *just barely* outside the cone's reach at default spacing. This is a deliberately mean tuning that's *correct* — it means standing still gets you nicked, encouraging movement. Document this so a future tweak doesn't accidentally widen the safety gap.

**Kenning drop:** Ash-Walker *(already in game)* — fire immunity.

---

## Boss 5 — Sindri's Apprentice

**Concept:** Sindri was one of the great dwarven smiths of Norse myth (he forged Gullinbursti, Draupnir, and Mjölnir's haft with his brother Brokkr). The Apprentice never finished his masterwork. He stayed at the forge after death and hammers on, taking up arms against anyone who interrupts the rhythm.

**Location:** An abandoned dwarven forge in the western mountain range, just past Brann. Lava trough along one wall. Anvil at center. Bellows in the back.

**Phase 1 — Smith-at-Work:**
- **Hammer slam.** Heavy melee. Slow windup, large hitbox, big knockback. Easy to dodge once. Hits like a truck if it lands.
- **Forge-thrown sparks.** Hurls red-hot scrap in a tight forward cone. Applies burn.
- **Summon two Lesser Smiths.** From the back doorway, two corrupted apprentices walk in carrying hot blades. They are minion-tier (~80 HP, kobold-equivalent damage) but tend to flank.

**Phase 2 — The Quench (50% HP):** He stops fighting. Walks slowly to the lava trough. Stands at the edge for 4 seconds. *This is the interrupt window.*
- If the player **does enough damage** during the quench (a hard threshold — about 25% of his max HP, ~425 dmg in 4s), he is *interrupted* and skips to phase 3 weakened.
- If they don't, he **plunges into the lava and emerges fully re-armoured.** His HP refills to 100%, he gains 25% damage and 25% knockback resistance, and his hammer is white-hot (now applies burn on hit).

This is the boss's gate: a player who learned the rhythm of phase 1 (i.e. they have rune charges saved and timing-perfect parries available) clears the interrupt; a flailing player gets a second full healthbar.

**Phase 3 — Mjöllnir Toss (post-quench):**
- **Hot-hammer throw.** Throws his hammer in a straight line; it travels ~600px, then **returns to him** (like Mjölnir). The hammer is a hitbox in both directions. The player must either dodge twice or position so the return path doesn't cross them.
- **Two-handed slam.** Massive AoE around him. Stagger-able during the windup.
- **Anvil call.** Anvils fall from the ceiling at telegraphed marks (~3 marks per cast). Late-fight area denial.

**Skill tested:** Interrupt-window damage burst. This is the boss that rewards saving runes for one big moment.

**Stats:** HP 1700 phase 1+2 (with the heal-on-quench-failure being effectively +425), 1200 phase 3 if interrupted, contact 14 hammer 22.

**Kenning drop:** **Forge-Bitten** — +1 stagger gain per hit on bosses. (Makes the parry-three-for-a-big-punish loop faster on every later boss.)

**Visual:** Squat, broad-shouldered, helmed. Glowing seams through armour where the metal has cracked. Phase 2: armour falls off in pieces, body underneath is *fresh fire*. Phase 3: re-armoured in glowing-hot plates that radiate heat.

---

## Boss 6 — Gymir of the Hollow Mountain

**Concept:** Gymir was a frost-jötunn in Norse myth, father of Gerðr. Frost giants are hollow inside — their substance is cold and stillness, not flesh. This Gymir was buried beneath the mountain in life, hammered into stone by Odin, and woke up after the king broke the cycle.

**Location:** A massive carved hall inside the NW mountain peak (the stone peak on the map). Roof so high it disappears into darkness. Stalagmite columns the player can use as cover.

**Phase 1 — The Mountain Awakens:**
- **Boulder throw.** Long telegraph (~1.2s), high arc, lands ~800px away. The slow telegraph teaches the player to *read where it'll land*. Each boulder shatters on impact into 4 stone-shard projectiles spreading outward.
- **Slam.** Close-range. Shakes the camera, applies knockback, *cracks the floor at the slam point.* Cracked floor takes 1 second to fully appear; standing on it during that second deals damage and applies a slow.
- **Roar.** AoE radial knockback (no damage). Resets player spacing — meant to push them out of melee range so the boulder/slam cycle resumes.

**Phase 2 — The Hollow (40% HP):** Gymir's chest cracks open and is *visibly empty inside*. He starts ripping smaller chunks from himself to throw as faster, less-telegraphed mini-meteors.
- **Self-shard hurl.** Same arc as boulder, faster windup (~0.5s), smaller AoE on impact. Three per cycle, spread over 2 seconds.
- **Floor-shatter.** All the cracked floor patches from phase 1 *collapse into a ring of damage* simultaneously. Long telegraph (cracks pulse white). Player must reach uncracked ground.

**Skill tested:** Long-range projectile reading and spatial memory. Players who track *which patches of floor are cracked* survive phase 2. Players who don't get caught by the shatter.

**Stats:** HP 1800, speed 35 (very slow), contact 18, projectile 25, slam 30.

**Kenning drop:** **Stone-Sided** — -15% damage taken from all melee hits.

**Visual:** Twice the player's height. Made of cracked grey stone with glowing pale-blue cracks. In phase 2 the body is visibly empty — the player can *see through the chest cavity to the wall behind him.* The hollow is what gives the boss its name on the map.

---

## Boss 7 — Skadi the Hoarfrost

**Concept:** In Norse myth, Skadi is a giantess and a goddess — Njörðr's wife, briefly, before she returned to her father's mountains because she missed the wolves' howling. Hunting goddess, associated with skis and bows. *This* Skadi is *not* the goddess herself (the gods are off the island). She is the goddess's reflection on Jörmund — a soul named Skadi by parents who hoped she'd grow into the name, who died on a hunt at sixteen and arrived here young. She has spent two hundred years becoming the name.

**Location:** A frozen peak near the North arch. Open arena with ice patches scattered across the floor. Standing on ice slides the player; cannot dash on ice for 0.3s after stepping onto it.

**Phase 1 — Bow:**
- **Aimed shot.** Single arrow, very high speed, low spread. Telegraphed by a thin red line from her bow to the player's current position (~0.5s before fire). Player must move *off the line* in that window.
- **Three-arrow spread.** Wider angle, slower. Sets a *freeze zone* on the floor where each arrow lands. Freeze zones last 8 seconds and slow movement 50%.
- **Skis.** Periodically she dashes to a new edge of the arena. Repositions the engagement entirely.

Phase 1 is a *kiting* fight from her side. She wants distance; the player wants to close. Cover (stalagmites or rocks) helps. The floor accumulates freeze zones over time.

**Phase 2 — Lance (45% HP):** She throws her bow aside. Pulls a frozen lance from the ice. Now she *closes the distance herself.* Same arena now has eight or nine freeze zones on it — and both characters are slowed in them.
- **Lance thrust.** Forward melee, long reach. Strong knockback.
- **Spinning sweep.** Wide arc around her body. Tests parry timing.
- **Ice-stake.** Slams the lance into the ground; an ice spike erupts at the player's current position with a 0.6s telegraph. Force-moves the player.

**Skill tested:** Floor-hazard navigation, *then* a complete style shift to melee in a degraded arena.

**Stats:** HP 1900, speed 90 phase 1 / 110 phase 2, arrow 14, lance 22, ice-stake 28.

**Kenning drop:** **Hoarfrost-Tracked** — runs +20% faster on ice and water tiles. Niche but powerful in three later fights.

**Visual:** Tall, pale, wearing wolfskin furs. Long black hair, half-frozen. Phase 2 she binds the hair up and the lance is taller than she is.

---

## Boss 8 — Hrímfaxi's Get (The Wolf-Mother)

**Concept:** Hrímfaxi means "frost-mane" — the horse of Night in Norse myth. Wolves are her get, her offspring. This is the dam of every wolf the player has fought through the northern woods. She raised them on the corpses of pilgrims to the North arch.

**Location:** A snowy forest clearing under the moon. North of Nasus. Cover-rich (trees) but with sight-lines.

**Phase 1 — The Pack (mother + 2 pups):**
- The **mother** is slow (max_speed 90), tough, hits like a freight train. **Pups** are fast (max_speed 160), thin, do the harassing damage.
- Mother attacks: **lunging bite** (uses the existing `user_lunge_distance` for the wolf archetype). **Backhand swipe.** Both telegraphed.
- Pup attacks: **dart and bite** (very short windup, very low damage but constant pressure).

Phase 1 is a three-vector problem. The player can't focus solely on the mother — the pups will chip them out. Can't focus on the pups — the mother one-shots them when ignored. The right play is *spacing*: position so the pups can't flank, force the mother to lunge from the front, parry the lunge, punish.

**Phase 2 — Hunt (50% mother HP):** The mother howls. Pups become **briefly invisible and invulnerable** for 5 seconds (they're now hunting). The mother gains a new attack:
- **Leap.** Mother leaps to the player's position, lands with an AoE. Less telegraphed than the standard lunge.

The pups reappear after 5s wherever they hunted to — usually flanking. Cycle: kill the mother under howl pressure, knowing the pups will re-emerge somewhere bad.

**Skill tested:** Multi-target awareness, and *managing absence* (the briefly-invisible pups). Players who track sound cues or smell-zones in the existing detection system get an advantage.

**Stats:** Mother 1400 HP, pups 200 each, speed as listed, mother bite 28 lunge 35, pup bite 8.

**Kenning drop:** **Wolf-Eyed** — see enemies through walls within 200px. (Synergises with the multi-room dungeons going forward.)

**Visual:** The mother is huge — twice the size of the existing wolf scenes. Tattered white-grey fur, scarred face, one milky eye. Pups are smaller and lighter, almost ghost-pale. All three trail soft snow particles.

---

## Boss 9 — The Ash-Sprout (Yggdrasil's Burned Bough)

**Concept:** The Yggdrasil-seedling on the western island is alive but dying. One of its branches has gone wrong: corrupted by the king's hoarding, it sprouted *here*, in the north caldera, far from its mother-tree. It is angry and lonely and the seed in its chest still remembers what it was meant to grow into.

**Location:** A burned grove at the bottom of the north caldera. Stationary boss — a single great trunk in the centre. The fight is around the trunk.

**Phase 1 — Roots & Seeds:**
- **Root strike.** Tentacle-roots emerge from the ground at three telegraphed positions per cycle. Spike up, strike, retract. 0.8s windup per root.
- **Seed-pod.** Hurls a heavy slow seed-projectile (~9 base damage, big AoE on impact). 1s windup, player can run past it.
- **Branch sweep.** Mid-range AoE around the trunk. Forces the player to keep moderate distance — too close gets swept.

Damage is dealt to the trunk anywhere.

**Phase 2 — The Heart Opens (50% HP):** The trunk cracks vertically. A *glowing core* is exposed inside — the seed. Damage to the trunk now does **15%** of normal; damage to the core does **150%**. The core is a small target (~40px wide) and rotates around the trunk's circumference *while the trunk is rotating to face the player*. Hitting it is a positioning problem.
- Root strikes become more frequent (4 per cycle instead of 3).
- New attack: **seed-rain.** Five small seed-projectiles fired in a high arc around the boss. Hit the ground at random within 400px.

**Skill tested:** *Sustained DPS on a moving small target while dodging area attacks.* This is the game's "are you actually good at positioning" check.

**Stats:** HP 2000 (effective). Trunk reduced damage in phase 2 is the actual gate.

**Kenning drop:** **Sap-Stained** — heal 5% max HP every 60s out of combat. Pairs with the explorable areas between bosses.

**Visual:** A twisted, blackened tree, twice the height of any other entity. Roots emerge from the *whole arena floor* during attacks, not just near the trunk. Phase 2: the vertical crack glows golden-green; you can see the seed pulsing inside.

---

## Boss 10 — Eir of Broken Wings (The Fallen Valkyrie)

**Concept:** Eir is a Valkyrie name — also a goddess of healing. Valkyries chose the slain and carried them to Valhalla. This one was on the wrong battlefield when Jörmund's cycle broke; she carried souls to a hall that had no door. She has been waiting for centuries, growing bitter. Her wings are broken because she tried to fly off the island and the gods, who could not enter, could not catch her.

**Location:** The NE stone fortress (visible on the map). High ceiling, balconies, a stone floor with a pillar pattern. There is a *throne* at the back wall (where Heimdall's Echo will sit in the next fight — foreshadowing).

**Phase 1 — Wing (full health → 50%):** She hovers ~60px above the ground.
- **Spear-volley from above.** Throws three spears in a tight forward cone. Easy to read but each spear leaves a brief shock zone on landing.
- **Swoop.** Dives forward to a player-targeted spot; AoE on landing; takes 0.5s to return to hover. *Swoop is her vulnerability window.*
- She cannot be reached by melee in hover unless the player is on the balconies (a movement puzzle the arena teaches early).

**Phase 2 — Falling (50% → 0%):** Her good wing snaps. She crashes to the floor. Now grounded, fast (speed 130), and *enraged.*
- **Spear-flurry.** Three quick stabs forward.
- **Wing-shield.** Brief defensive stance that reflects ranged damage back.
- **Whirlwind.** Long spinning attack with wide hitbox. Hard parry timing.

**Phase 3 — The Revive:** When she "dies," she does not die. She **rises again at 0 HP with a 3-second invincibility window** and full Valkyrie wrath — wings whole again. *(This is the only revive boss in the game; it must be telegraphed by name on the boss bar: "Eir of Broken Wings → Eir Restored.")*
- **All-attack chaos.** All phase 1 *and* phase 2 attacks, used in unpredictable order.
- **Soul-spear.** New attack: a single tracking spear that follows the player slowly for 3s. Cannot be parried, only outrun.

The revive is the heart of the fight. The player thinks they've won. Then the boss bar refills. *That moment* is the kenning earning itself.

**Skill tested:** Endurance. Resource management across what is effectively two boss fights. Rune timing — many players will burn their best rune on phase 2 and have nothing for phase 3.

**Stats:** HP 1500 (phases 1+2) + 1200 (phase 3) = 2700 total. Phase 1 speed 0 (hover), phase 2 speed 130, phase 3 speed 110 but with the tracking soul-spear.

**Kenning drop:** **Valkyrie-Marked** — revives the player once per dungeon at 30% HP. *The* best meta-progression reward in the game and the natural unlock from a boss who revives herself.

**Visual:** Tall, silver-feathered, in dented golden armour. Phase 1: hovers, wings outstretched, one wing visibly bandaged. Phase 2: wing snapped, blood streaks down armour, hair loose. Phase 3: wings *whole again* — somehow — and the armour glows faintly gold. Reverence in the silhouette: this is what a Valkyrie was meant to look like.

---

## Boss 11 — Heimdall's Echo

**Concept:** Heimdall guarded the rainbow bridge Bifröst in Norse myth, watching for the giants who would come at Ragnarök. This is not Heimdall — gods are off the island — but the *echo* of his image, taken on by the king's most loyal champion. Whoever this man was in life, in death he saw the king and gave himself a god-name and a horn and called himself the bridge's keeper.

**Location:** A stone causeway bridging the mainland to the king's central island. Long, narrow arena — limited lateral movement. *Boss fights you on the bridge before you can reach the tower.*

**Phase 1 — Sword and Horn:**
- **Heavy sword swings.** Three-attack combo, very telegraphed; each swing is a parry opportunity. *The combat language of this fight is pure parry.* He will not stop swinging.
- **Horn-blast.** Brings a great horn to his lips. ~1.0s windup. AoE radial knockback. Pushes the player toward the bridge edge. (No insta-death from falling — the arena has rails — but the knockback resets all spacing and interrupts any combo.)
- **Shield bash.** Cancels into the horn from a parry; punish window is shorter than for the sword.

The fight is a clean classical sword-and-shield duel. No floor hazards, no minions, no projectiles. Just timing.

**Phase 2 — Twin Sword (40% HP):** Drops the shield. Draws a second sword. *Faster, but no longer parries his own.*
- **Cross-strike.** Two swords swing simultaneously from opposite sides. Cannot be dodged sideways — must be dodged backward.
- **Spinning advance.** Walks forward spinning both swords. Constant pressure.
- **Calls in two corrupted knights** every 30 seconds. They walk in from the bridge ends. Mini-mob pressure; player must clear them or be flanked.

**Skill tested:** Pure parry mastery and *clutch resource use* (rune timing on the spinning-advance). This is the cleanest pure-melee boss in the game — a calibration test before the king.

**Stats:** HP 2400, speed 100 phase 1 / 130 phase 2, sword 22, horn-blast 0 damage but knockback heavy, dual-sword 18 each.

**Kenning drop:** **Bridge-Keeper** — +20% damage on the *first hit* of every fight. Encourages the player to open with their best.

**Visual:** Tall, broad, full plate, surcoat in king's colours. Carries a black-and-gold sword and a horn slung over the shoulder. Phase 2 the surcoat is torn open and the second sword is *bare bone* — he took it from one of his minions during a previous duel.

---

## Boss 12 — THE TYRANT KING → NíÐHÖGGR

**Location:** The stone tower on the lake's central island. Throne room at the top, lake water encroaching.

### Phase 1 — Hjarrandi the Hoarder (1000 HP)

The king on his throne. He stands as the player enters. He is *tall* and *too long* and the silk hides something that moves wrong. He fights with a hand-and-a-half sword. Looks like the player's first-ever opponent — a man with a sword in a hall.

- **Sword combo (3-hit).** Heavy, clean, parry-able.
- **Calls shield-bearers.** Two minions in plate emerge from side doors. They walk in front of him, soaking damage. He fights from behind them.
- **Royal command.** Shouts an order. All shield-bearers gain damage reduction for 5s. (Forces the player to wait out the buff, deal with whoever's in front, or break through to him.)

Skill: filter through cover to reach the king.

### Phase 2 — The Hoarder Drops the Mask (1000 HP)

He drops the sword. Speaks one line, quiet: *"I would not be a fisherman's child."* The arena cracks open. He pulls a soul out of the floor — a *real soul*, glowing green-white — and hurls it. *He has been hoarding eternity, and the eternity is here.*

- **Soul-throw.** Single high-damage projectile. ~30 dmg. Slow but tracks the player for 2 seconds before its arc locks.
- **Soul-burst.** Ring of 12 soul-projectiles, low damage each (~6) but the *ring is unbroken*. Player must dash through.
- **Soul-puppet.** Possesses a recently-killed shield-bearer corpse from phase 1. It rises and walks toward the player. Killing it again expels a soul-projectile in the player's direction.
- His own movement is jerky, half-transformed — neck too long, shoulders wrong.

Skill: dodge through a soul-bullet-hell of his own hoarded eternity.

### Phase 3 — Níðhöggr (1500 HP)

He runs to the Pool. The Pool *rejects him*. The water erupts and what comes up is enormous, scaled, two-headed (one head still resembles his face, the other is pure serpent). The throne room arena shatters; the player is now on a ring of broken stone in the water. The wyrm Níðhöggr fights from the lake itself.

- **Head-snap (king-face).** The king's head still speaks. Strikes forward in a long lunge. The player can parry this — it is the only attack on the wyrm that can be staggered. It is also the only attack that opens the body for damage.
- **Tail-lash.** Submerged tail emerges and sweeps a 270° arc around the arena. Telegraphed by water bulge. Must be jumped (dash) or moved out of arc.
- **Bite (serpent-face).** Pure beast head bites at the player. Heavy damage. Easier to dodge but no parry available.
- **Soul-vent.** Vomits stored souls in a forward stream — same projectile as phase 2 but as a *beam*. Long telegraph; this is the player's damage window.
- **Submerge.** Periodically dives. The arena goes still. Surface ripples mark where it will breach. Player must read ripples to anticipate breach point.

Final beat: at ~10% HP, the wyrm wraps itself around the arena ring. The player is inside its coils. Last 200 HP must be done on the *only exposed point*: the king's face, still half-human, half-snake. Cinematic finish.

**Stats summary:** 3500 total HP, ~90s fight clean run, three phases of utterly different design language.

**Reward:** *King-Slayer.* Game completion. Story epilogue.

---

# OPTIONAL — THE EASTERN BRANCH

The east is for the player who has finished the main path or is grinding for kennings. Off-route, lethal, *not* required.

## E1 — Gullveig Thrice-Burned

**Concept:** Gullveig in the Eddas was a witch the gods tried to kill three times by burning her. She returned each time. The Norse poets thought she was Freyja in disguise. *This* Gullveig is one of the four most ancient souls on Jörmund — older than Hjarrandi by a thousand years.

**Location:** An ash-strewn plateau in the eastern desert.

**Structure:** Three sequential rounds. Each round is its own complete boss arena. Between rounds the player gets a 5-second recovery and a single full rune refill — but **no HP heal**. Round-end music sting. New round, same arena, fresh boss visual.

- **Round 1: The Witch.** Fire-bolts and a cone-AoE pyre. ~800 HP.
- **Round 2: The Ash.** She is *thinner*, faster. Now dashes and leaves flame-trails behind her. ~800 HP, max_speed 130.
- **Round 3: The Phoenix.** She is *radiant* — golden, levitating, beautiful. Slower again but every attack carries a longer-duration burn. ~800 HP. Win condition: kill her completely; she does not revive a fourth time.

**Skill tested:** Resource conservation across three rounds. A player who used all their potions in round 1 dies in round 3.

**Kenning drop:** **Thrice-Burned** — +25% damage when below 25% HP. (Last-stand kenning. Pairs with Valkyrie-Marked for a clutch build.)

---

## E2 — The Howling Hollow (Garmr's Cousin)

**Concept:** Garmr was the great hound who guarded Hel's gate in Norse myth, prophesied to kill Tyr at Ragnarök. This is a smaller, *cousin* dog — not the canon Garmr, but its kin. It has a hollow chest cavity. The howl that comes out is the wind blowing through it.

**Location:** A cliff-cave on the east coast.

**Mechanic:** The signature attack is a **howl** that applies a status effect named **Unmoored** to the player. While Unmoored:
- The player's weapon temporarily falls from their hand (drops to the floor; can be picked back up).
- *Or* (designer's choice depending on what feels worst-best) movement controls invert for 2 seconds.
- *Or* the rune cooldown is doubled for 5 seconds.

Pick one. The point is: the howl punishes complacency.

**Other attacks:** Lunge bite (existing wolf lunge mechanic, scaled up), claw swipe (close-range AoE), tracker mode (when below 30% HP it goes into a single-track aggression where every attack is a lunge bite — desperate hound).

**Skill tested:** Reaction to CC effects on the player character. Players who panic when their controls misbehave die. Players who keep moving and recover their weapon survive.

**Stats:** HP 2200, speed 130, bite 30, howl 0 damage but applies Unmoored.

**Kenning drop:** **Hollow-Tongued** — immunity to all silence/disarm/disorient effects.

---

## E3 — The Sea-Mire (Spawn of Jörmungandr)

**Concept:** Jörmungandr is the World Serpent — Loki's son, encircles Midgard, kills Thor at Ragnarök, also dies of poisoning in the same exchange. This is not him. This is *a spawn*, a child-serpent that fell to Jörmund when the cycle broke and has been growing in the eastern shallows ever since.

**Location:** The blue glowing arch on the eastern peninsula. Half-flooded arena.

**Structure:** Cycles between two phases on a timer (not HP-gated). Each cycle is ~12 seconds. The player must learn the rhythm.

**Cycle A — Surface (~7s):** Body coiled visibly on the surface. Body is the hitbox; the head is the weak point (2× damage). Attacks:
- **Head strike** (forward lunge from the head, telegraphed by a hiss).
- **Body-roll** (the whole body rolls in one direction; player must reposition).
- **Spit** (poison projectile, applies the existing poison status).

**Cycle B — Submerged (~5s):** Body invisible underwater. Only splash-telegraphs reveal where it will breach. Two or three telegraphs per submersion. Player can do *no damage* during the submerge — they can only survive.

**Skill tested:** Pattern memorization with a *rhythmic* time pressure. The serpent doesn't change behaviour based on player HP — it just runs its loop, and the player must do enough damage in the surface windows.

**Stats:** HP 2500, surface phase contact 18, head strike 32, spit 12 + poison, body-roll knockback heavy.

**Kenning drop:** **Serpent-Read** — sees attack telegraphs 25% longer (the yellow phase before red is extended). Build-defining for parry-heavy play.

---

# Quick design-feel summary

If a player plays the full main path and only the main path, they fight: a king, a hanged corpse-knot, a sea-witch, a fire-queen, a dwarven smith, a frost-giant, an ice-huntress, a wolf-mother and pups, a corrupted tree, a fallen Valkyrie, a bridge-knight, and a king who becomes a wyrm. Twelve fights, eleven *kinds* of fight — no two bosses test the same thing. The optional eastern trio adds an endurance gauntlet (Gullveig), a controls-CC test (Howling Hollow), and a rhythmic pattern boss (Sea-Mire).

The arc tonally: Acts I–II are *the world breaking under you*. Act III is *the world having broken long ago*. Act IV is *meeting the man who broke it*. Each region introduces a new climate, a new enemy archetype family, and one new mechanical verb.
