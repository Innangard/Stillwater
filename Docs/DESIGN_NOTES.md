# Save System + Difficulty + Title Screen — Design Notes

## What's in this changeset

**New systems:**
- Three save slots stored at `user://save_slot_<N>.cfg` as ConfigFile (text format — easy to inspect, easy to migrate later).
- Per-save difficulty: Easy / Normal / Hard, chosen at New Game time, locked for the life of the save.
- Title screen at launch — pick a slot to start a new tale, continue an existing one, or delete a save.
- In-game pause menu (Esc) with Resume / Save / Save & Quit to Title.
- Auto-save on scene transitions, on arch awakening, and on respawn after death.

**Modified systems:**
- `Enemy.gd` / `BossEnemy.gd` — HP and movement speed scale with difficulty.
- `Weapon.gd` — outgoing damage scales with difficulty when the user is an enemy (player damage is untouched, see balance notes).
- `Projectile.gd` — enemy-team projectile speed scales with difficulty.
- `Player.gd` — out-of-combat passive HP regen (Easy only, capped at 50%).
- `GameState.gd` / `RunState.gd` — added `reset_to_defaults()` for clean slot-switching.
- `SceneTransition.gd` / `Arch.gd` / `RegionRoot.gd` — auto-save hooks and load-position handling.

---

## Balance & Feel Critique

### The asymmetric difficulty lever

I deliberately made difficulty change **enemy behavior**, not **player power**. Player damage, weapon cooldowns, dash distance, and stamina costs are identical across all three modes. The reason: if both sides scaled, Easy would be trivial (player hits harder against weaker enemies) and Hard would be a damage race (enemies hit harder against a player who hits less hard). Scaling only the enemy side keeps the **action feel** of the game constant — the same parry timings, the same readable telegraphs, the same combat language. Difficulty becomes "how much margin for error do you get," not "how does the game play."

### The multipliers

| Knob              | Easy | Normal | Hard |
|-------------------|------|--------|------|
| Enemy max HP      | 0.7× | 1.0×   | 1.3× |
| Enemy damage      | 0.7× | 1.0×   | 1.3× |
| Enemy movement    | 0.8× | 1.0×   | 1.2× |
| Enemy projectiles | 0.8× | 1.0×   | 1.2× |
| Player regen rate | 2 HP/s, capped at 50% max HP | — | — |

The 30% / 20% spreads are intentional. 50% on either side (the obvious "double on Hard, halve on Easy" reflex) is too much for an action game with hand-readable telegraphs — Hard becomes a memorization gauntlet where one mistake on certain bosses one-shots you, and Easy becomes too forgiving to ever feel under threat. 30% is roughly "you need to use one fewer dodge per fight" on Easy and "one more dodge per fight" on Hard.

The speed multipliers are gentler (20% spread) because they affect **reaction windows**, not damage budgets. A 30% slowdown on projectiles starts looking goofy — slow-mo dodgeball — and a 30% speedup makes some boss patterns physically un-dodgeable depending on the room.

### The passive regen on Easy

The brief says "slow regaining of health up to 50%." I tuned this to 2 HP/sec at base 100 max HP — about 25 seconds to refill half the bar. Slow enough that:

1. **It can't out-heal active combat.** Combat is detected (the existing `_is_fighting` poll, which I reused — that poll already drives smell buildup during combat), so regen pauses during fights. The Easy player can't just bunny-hop in a boss arena healing through hits.
2. **It can't replace consumables.** Above 50% max HP, only authored heals work (potions, kennings, arch rest). Regen is *just* a comeback tool — "I got chunked exploring, I can walk to the next room without panicking."
3. **It can't trivialize traps.** A trap that does 30% damage still costs real HP because you can only regen back to 50%. The trap deters you from the second pass on the same room.

The hard cap is the key design call. "Slow heal to 50%" would have been an easier read if I'd made the cap a flat "stop at half full," but the framing matters: **regen is a floor, not a ceiling.** The Easy player is never below 50%, but they're not constantly above 50% either. The combat tension stays.

### What gets saved (and what doesn't)

- **Saved:** soul currency, death count, story flags (which includes quest progress, kenning unlocks/equips, arch activations, map reveals), inventory + equipment by resource path, HP, smell, world seed, dungeon seeds, consumed pickups, current scene, player position, difficulty.
- **Not saved:** per-frame combat state (mid-attack animations, status effects, projectiles in flight). The save-on-transition / save-on-arch / save-on-respawn pattern means you can only quit at relatively "safe" gameplay moments. If the player force-quits mid-fight, they'll lose progress back to the last auto-save — which is the right tradeoff. Saving mid-attack would let the player escape danger by quitting.

### The auto-save points

I picked three:

1. **Scene transition** — every time the player walks between regions. Frequent enough to feel safe, infrequent enough that the disk doesn't thrash.
2. **Arch awakening** — these are the explicit "you made progress" beats in the game's existing design. Saving here gives the player an obvious checkpoint affordance.
3. **Death respawn** — the post-respawn state is saved, with the incremented death count. You can't escape death by quitting.

The pause-menu **Save** button is for the "I'm done playing, let me save and walk away" case. Most players will quit via "Save & Quit to Title" which also writes.

### Edge cases I handled

- **Loading after a death:** quest progress on COLLECT/SOUL quests is re-counted against the freshly-loaded inventory (existing QuestManager behavior).
- **Map reveals across load:** `EventBus.run_started` clears them (existing PathManager behavior for fresh runs), so I snapshot and restore them around the emit.
- **PathManager chain regeneration:** new games roll a `world_seed`, then emit `run_started` so chains regenerate before the scene loads.
- **Resource path drift:** if a saved item's `.tres` file has been deleted or renamed since the save was written, the load silently drops it rather than crashing. Better degradation than a broken save.
- **Version mismatch:** saves are versioned (`SAVE_VERSION = 1`). Mismatched saves show as "Corrupted" on the title screen and refuse to load, leaving room for an explicit migration path later.
- **South arch invariant:** the south arch is always pre-activated (per the existing game design). Both `reset_to_defaults` and `load_game` re-set the flag defensively in case a save was written without it.

---

## Visual Critique

### What looks good

- **Title screen palette matches the in-game menus.** Same dark-Norse background, same gold accent, same panel borders, same stylebox treatment on buttons. The title doesn't feel like a different game — it feels like the start of *this* game.
- **Slot summary density is right.** Each slot card shows location, difficulty (color-coded), souls, death count, HP, and relative timestamp. Enough to identify the save without overwhelming the visual.
- **The relative timestamp is a small but nice touch** — "2h 14m ago" reads faster than a full datetime, and falls back to YYYY-MM-DD for saves older than a week.
- **Difficulty colors map to intuition** — green for Easy, yellow for Normal, red for Hard. Color is also redundant with the name, so colorblind players aren't penalized.
- **The pause menu dims rather than blacks out** the world. The player can still see where they are; they're paused, not teleported away.

### What's deliberately minimal

- **No animated title-screen background.** I kept the title flat dark. A particle effect or animated illustration would set a tone, but it'd also be the first thing you'd want to swap out when you have a real key art piece. Better to leave the door open than to commit to filler.
- **No save thumbnails.** A screenshot-thumbnail-per-slot would add visual richness but adds a meaningful chunk of code (capture, scale, write PNG to user://, load and display) and a real performance hit on the title-screen open. The text summary does the disambiguation job at a fraction of the cost.
- **No "Are you sure?" on Continue.** Loading a save isn't destructive — your existing save isn't overwritten until the next auto-save. The only destructive action (Delete) has a confirm step.
- **No fancy slot-selection animations.** Standard hover/press states on each button, no slide-in transitions. Feels snappy. Matches the in-game menus, which are also instant.

### What could be improved later

- **The title font is the engine default.** Once you have a Norse-flavored display font, the title and headings should use it. The body text can stay default.
- **No keyboard navigation.** The slot list is mouse-driven. Keyboard up/down/enter would be nice for accessibility — Godot's Button has built-in focus handling, but the current layout doesn't grab focus on any specific button initially. A two-line change in `_build_slot_list` (`first_button.grab_focus()` at the end) would add it.
- **The pause menu's status ack is small.** "Saved." appears for a moment after pressing Save, then fades. It works, but a brief checkmark icon would read at a glance better than text. Low priority.

---

## Files Changed

**New:**
- `globals/difficulty_settings.gd` — difficulty profiles + getters
- `globals/save_manager.gd` — three-slot save/load orchestration
- `ui/title_screen.tscn` / `title_screen.gd` — slot picker + difficulty picker
- `ui/pause_menu.tscn` / `pause_menu.gd` — in-game Esc menu

**Modified:**
- `project.godot` — autoloads + main scene
- `globals/game_state.gd` — `reset_to_defaults()`, removed old save stub
- `globals/run_state.gd` — `reset_to_defaults()`
- `enemies/enemy.gd` — difficulty scaling on HP + speed
- `enemies/boss_enemy.gd` — difficulty scaling on boss recovery speed
- `weapons/weapon.gd` — difficulty scaling on enemy outgoing damage
- `projectiles/projectile.gd` — difficulty scaling on enemy projectile speed
- `player/player.gd` — passive HP regen tick
- `world/region_root.gd` — honor `SaveManager.pending_load_position`
- `world/scene_transition.gd` — auto-save after transition + respawn
- `world/arch.gd` — auto-save on activation
- `ui/hud.gd` — hide HUD on the title screen
