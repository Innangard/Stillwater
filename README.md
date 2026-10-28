# Jörmund

A 2D top-down RPG / roguelite hybrid in Godot 4.

> Setting (working): Jörmund is the long shore between life and death. Souls wait their turn at the Life Pool at the island's heart, to be unmade and returned to the living world to be born again — but a tyrant king refused the water, and convinced others to refuse with him. The dead cannot pass on; the living cannot be born. With nothing left to weave, the Norn of what shall be reached across the threshold and pulled the player down — a living soul, awake, with red blood in their veins on an island where the dead bleed only black ash. The gods cannot enter Jörmund themselves. There is only the player, and the road to the tower at the centre.

## Slices built so far

1. **Foundation** — autoloads, three persistence tiers, components, player controller with dash, dummy enemy, test arena.
2. **Weapon Resource system** — flexible slots (primary/secondary for any melee/ranged, two spell slots), generic projectile, swing hitboxes, elements.
3. **Status effects** — burn / poison / freeze / shock as Resources, weapon-applied with chance.
4. **Items, pickups, inventory** — Item Resource hierarchy, generic Pickup, slot-based stacking inventory, autoloaded inventory UI.
5. **Crafting** — Recipe Resources, Workbench world objects, autoloaded crafting UI.
6. **HUD** — health bar, currency display, weapon slots with cooldown overlays, status effect indicators, floating damage numbers.
7. **Equipment overhaul** — Two flexible weapon slots (primary LMB / secondary RMB) accept melee or ranged; two rune slots (Q / F) accept MagicSpell or RunestoneItem; three armor slots (helmet/chest/boots). Armor is an Item subclass that flows through inventory — equip by clicking in the inventory UI, unequip by clicking the equipment slot. Crafting UI detail panel locked to fixed height to stop hover jitter.
8. **Weapons-as-items + drag-and-drop** — `Weapon` extends `Item`; weapons flow through inventory; double-click and drag-and-drop UI.
9. **Crafting + UX polish** — Recipes accept inputs from inventory or equipped slot; toast notifications; always-visible color-coded requirement chips; drag tints clear on cursor exit.
10. **Overworld foundation** — Three connected region scenes (South Cliff → Wickbarrow Path → Wickbarrow Village, oriented south-to-north), SceneTransition autoload with fade, ExitZone + spawn-marker system, NPC + Dialogue Resource + autoloaded DialogueUI. Player starts inside the South Arch (a real archway, not a pillar) on a grassy cliff overlooking the ocean; the Observer NPC delivers the opening lore and points the way north.
11. **Sense-driven detection + extended overworld** — Noise (transient, decays) and smell (persistent, decays slowly, items reduce it) drive enemy detection — enemies start dormant and only engage when the player's signature crosses their threshold. Four new connector scenes between the South Arch and Wickbarrow (Cliffside Path → Old Pilgrim Road → Hollow Glade → Wickbarrow Outskirts) extend the journey. Cinder Salt consumable introduced as a smell-reducer. Dialogue panel made opaque; scene transition fades shortened.
12. **Death + arch respawn, bare hands, persistence split** — On death: HP, inventory, equipment, and smell reset. Currency, story flags, arch activations, and boss kills persist. SceneTransition listens for `player_died` and respawns at the most recently activated arch (south_arch fallback). Bare Hands is a built-in unarmed weapon used when the primary slot is empty — weak melee, always available. Per-slot noise burst IDs so primary + secondary + spells fired together stack additively (was capped at one source's level).
13. **World expansion: merchant, bath house, paths to Nasus + Storsprunga.** Wickbarrow gets three exits (south back to arch, north toward Nasus, west toward Storsprunga), plus Merchant Vel (currency-cost recipes via a new `currency_cost` field on Recipe) and Bath-keeper Aud (smell-block via `RunState.grant_smell_block`). Six new scenes north toward Nasus, four west toward Storsprunga.
14. **Longer paths, busier towns, quest boards.** Wickbarrow→Nasus extended to 12 connector scenes (added Wickbarrow Approach, Sundered Grove, Pyre Ruins, Riven Stair, Northwall Watch). Wickbarrow→Storsprunga extended to 7 (added West Gate, Saltmarsh Path, Wreck Shoals). All three towns rebuilt as larger scenes with internal building footprints, idle Townsperson NPCs drifting around, and a `QuestBoard` interactable with placeholder postings (real quest tracking is a future slice). Bath duration bumped 90s → 300s.
15. **Enemy variety + attack rework.** DummyEnemy generalized into the `Enemy` base class — wields a Weapon Resource the same way the Player does, with a five-state machine (IDLE → CHASE → WIND_UP → ATTACK → RECOVER) and a yellow→red telegraph during wind-up. New `user_lunge_distance` field on MeleeWeapon lets wolves surge forward at strike-time. Nine archetypes authored as scenes: kobolds (green spear / brown shortsword / blue bow — distinct body tints, low sense sensitivity, weakest tier), goblins (spear/sword/bow — same body color, weapon icon distinguishes them, high noise sensitivity, mid tier), wolves (lunge/swipe — fast, high smell sensitivity), giant crab (slow, tough, beach-only, high noise sensitivity). Enemies distributed across all 18 region scenes by biome.
16. **Persistent kills/pickups, spear thrusts, no starter gear.** Spears (kobold + goblin) now use a new `RECTANGLE` hitbox shape on MeleeWeapon — a long thin forward thrust instead of a wide circular sweep, fitting the weapon's identity. Killed enemies and collected authored pickups stay gone for the rest of the run via a new `RunState.consumed_node_paths` set keyed by scene + node path; cleared on death/respawn so the world repopulates fresh per life. Pickups gain a `persistent_per_run` export to opt in. Player now begins barehanded — the Worn Blade is an authored pickup in `cliffside_path` (the first scene past the arch), retrievable once per life. South arch is pre-activated on game start so death always sends the player back to the arch with no ceremony.
17. **Randomized north path + PathManager.** New `PathManager` autoload generates a per-run randomized chain of up to 12 forest scenes (drawn from a pool of 21 `forest_buffer_*` and 10 `forest_cross_*` scenes) between Wickbarrow Approach and Nasus Overlook, using `RunState.world_seed` for determinism. Each candidate buffer is validated at its placement cell *before* being committed: every non-backward exit must lead to either an empty cell with a matching reciprocal clearing available, or an already-placed scene whose own reciprocal exit lines up — otherwise the candidate is rejected and the next is tried. This guarantees the map never draws a connection line over an intervening scene. Cross scenes (4-way intersections, N/S/E/W exits) provide more layout flexibility for the validator; 12 `forest_clearing_*` scenes act as reward side rooms. When a buffer's side exit lands on a neighbor that already exists with a matching reciprocal exit, the two are *wired together* in-game (the exit zone routes back to the existing scene with a "→ a familiar path" label) instead of placing a new clearing — turning the random chain into a small explorable graph. Chain regenerates on death/respawn. `RegionRoot._ready()` calls `PathManager.apply_overrides()` to rewire exit targets at runtime. Static paths (arch→Wickbarrow, Wickbarrow→Storsprunga) unaffected.
18. **Runestone spell system + NPC crafting dialog.** Norse mythology-inspired one-use spell scrolls replace the old Q/F spell slots (now "rune slots"). 24 Elder Futhark runes × 4 conduit types = 96 RunestoneItem resources, crafted via 48 recipes at the Norn. RunestoneItem extends ConsumableItem with projectile, AoE, buff, enemy manipulation, smell, and utility fields — `on_use()` processes all non-zero fields in sequence, then the rune is consumed. **One rune per room per life** (`RunState.rune_used_this_room`, reset on scene transition and death) — runes are a strategic choice, not spammable, so damage values are high (Kenaz Runebone hits for 55, Thurisaz scatters 8×24). Auto-refill from inventory when a rune is consumed. 16 new status effects for buffs (Berserker, Vigor, Warden, etc.). 6 new reagent items. Norn is an NPC (extends NPC, auto-loads recipes from `crafting/instances/runes/`). **NPC dialog reworked Terraria-style**: NPCs can house a crafting station (`station_name` + `recipes` exports); a green craft button appears in the dialog box from line 1, so the player can skip straight to crafting. Clicking anywhere else advances/closes dialog. Closing the CraftingUI also closes dialog. Standalone Workbench nodes still work for stations without an NPC. HUD: status icons moved below the smell bar; rune slots dim when the room's rune is spent.
19. **World map UI + key rebind + section reveal** ← *just added*. New `WorldMap` autoload (`ui/world_map.gd`, layer 40) draws a Rogue Legacy 2-style room map overlay: colored rectangles per scene tinted by section (Start / Storsprunga / Nasus / Chain), strictly cardinal connection lines (the validation rewrite in PathManager guarantees no diagonals or jump-overs), icons for towns / clearings / arches, WASD pan, scroll-wheel zoom, hover tooltips (shows room name when visited, "???" otherwise). Rooms are dim outlines until visited (`PathManager.mark_visited` fires from `RegionRoot._ready`); whole sections stay hidden behind town-arrival flags (entering Wickbarrow unlocks both Storsprunga and Nasus on the map). Tree pauses while the map is open. Inputs reworked: **M** or **Tab** open/close the map; **I** opens inventory; **E** interacts when something is in range and falls through to inventory otherwise (EventBus tracks `interactables_in_range` so the fallback knows when E is "free"). 10 new `forest_cross_*` scenes (4-way N/S/E/W intersections) join the buffer pool for richer chain topology — each has a unique palette, three enemies, and varied quadrant decor. Test branch of nine unused nasus scenes (greenwood_path → northwall_watch) moved into `world/regions/test/`.

## How to open it

1. Open Godot 4.x → import `project.godot`.
2. Press F5. The arena starts you with the **basic** weapons (Worn Blade, Crooked Bow, Pale Spark) and reagents scattered around. The **Smoldering Forge** in the upper-left lets you craft your way up.

**Controls:**
- WASD move · mouse aim
- LMB primary · RMB secondary · Q & F rune slots
- Shift dash with i-frames
- **E** to interact (pickups, NPCs) — or open the inventory when nothing is in range
- **I** inventory · **M** or **Tab** world map · **Esc** close menus

**Try this:** walk over the reagents to collect them, walk up to the forge and press E. You'll see four recipes — three weapon upgrades and one item-combination. Craft "Forge Hearthbrand" to swap your Worn Blade into a fire sword that applies burn. Same idea for the bow → poison and the spark → freeze. Walk up to the Norn and press E for runic crafting — the craft button appears immediately in the dialog. Pick up bone tablets and reagents scattered around the arena, then inscribe runestones. Equip a runestone to Q or F from your inventory (double-click or drag), then press Q/F in combat to use it. Remember: one rune per room!

---

## Architecture overview

### Three persistence tiers

| Tier | What | Lifetime |
|---|---|---|
| Persistent (`GameState`) | Currency, story flags, dungeon clears | Survives death + quit |
| Per-run (`RunState`) | Equipped weapons, inventory, current HP, world seed | Lost on death |
| Per-scene | Entities, world state | Per scene instance |

### Component-based entities

`HealthComponent`, `HurtboxComponent`, `HitboxComponent`, `StatusEffectComponent`. New enemy archetypes = new AI script + components.

### Damage pipeline

```
HitboxComponent → HurtboxComponent → entity intercept → HealthComponent
                                          ↓
                                  StatusEffectComponent (rolls on_hit_effects)
```

Status DoT ticks loop back through the entity intercept so resistances apply uniformly.

---

## Weapon system (recap)

`Weapon` (base) + `MeleeWeapon` / `RangedWeapon` / `MagicSpell` subclasses, all Resources. Player calls `weapon.attack(self, aim)` — the weapon decides what to spawn.

### Rune slots (Q / F)

The Q and F slots accept either a `MagicSpell` (fires continuously like a weapon) or a `RunestoneItem` (one-use consumable, consumed on activation). When a RunestoneItem is used, the slot auto-refills from inventory if the player has more of the same rune. Only **one rune can be activated per room per life** — the `RunState.rune_used_this_room` flag resets on scene transition.

### RunestoneItem

Extends `ConsumableItem`. 96 instances across 24 Elder Futhark runes × 4 conduit types:
- **Bone Tablet** — offensive (projectiles, AoE damage, blood magic)
- **Runeslate** — utility (buffs, enemy manipulation, economy)
- **Living Wood** — helpful (healing, wards, companions) — *future content*
- **Deep Gold** — amplified versions of other conduits — *future content*

Each `.tres` has a menu of effect fields (projectile count/damage/spread, AoE damage, heal, status grants, enemy flee/freeze, smell manipulation, currency gain, etc.). `on_use()` processes every non-zero field in sequence, then the rune is consumed. Max stack 3.

## Status effects (recap)

`StatusEffect` (definition) + `StatusApplication` (effect + chance) + `ActiveEffect` (runtime) + `StatusEffectComponent` (on entities).

## Items, pickups, inventory (recap)

`Item` + `ConsumableItem` Resources. One `Pickup` class adapts to its content (item / weapon / currency). Inventory is `Array` of `{item, count}` slots in `RunState`. Autoloaded inventory UI.

---

## Crafting (the new system)

### `Recipe` Resource

Defines one transformation:
- `inputs: Array[ItemQuantity]` — items consumed
- `requires_weapon: Weapon` *(optional)* — must be currently equipped; gets replaced by output_weapon
- `output_item` + `output_item_count` *(optional)* — produced item
- `output_weapon` *(optional)* — produced weapon, equipped into matching slot

Methods:
- `can_craft()` — true if all inputs present and required weapon (if any) equipped
- `reason_blocked()` — human-readable string for UI; `""` if craftable
- `craft()` — consume inputs, grant outputs, emit signals

### `ItemQuantity` Resource

Tiny pairing of `item` + `count`. Used for recipe inputs so each requirement is a single sub-resource you edit in the inspector instead of fighting parallel arrays.

### Two recipe flavors, one class

- **Weapon transformation:** `requires_weapon` + `inputs` → `output_weapon`. Replaces the weapon in its slot. Forge Hearthbrand, Envenom the Bow, Bind the Hoarfrost.
- **Item combination:** `inputs` only → `output_item`. Distill a Soul Phial.

Both flavors use the same Recipe class because the *behavior* is identical — consume inputs, produce outputs. Subclassing would be unnecessary ceremony.

### `Workbench` world object

`crafting/workbench.gd / .tscn`. Drop one in any scene. Set `station_name` (shows in the UI title) and `recipes: Array[Recipe]` in the inspector. Press E nearby to open.

Each workbench owns its own recipe list. A forge in one town has a different list than an alchemist's table elsewhere. Same UI handles all of them.

Standalone Workbenches are still supported, but the preferred pattern is to house the station inside an NPC (see below).

### NPC-housed crafting stations

NPCs have optional `station_name` and `recipes` exports. When set, the dialogue box shows a green craft button (labeled with the station name) from the very first line — the player can click it immediately without sitting through all the dialogue, or advance the dialogue normally by clicking elsewhere. Closing the CraftingUI also closes the dialogue automatically.

This replaces the old pattern of placing a separate Workbench node next to each NPC.

### `Norn` — runic crafting NPC

`npcs/norn.gd / .tscn`. Extends NPC. Auto-loads every Recipe `.tres` in `crafting/instances/runes/` at `_ready()` and sorts alphabetically. New runestone recipes are picked up without editing any scene file. Has a distinct diamond placeholder visual.

### `CraftingUI`

`ui/crafting_ui.gd`, autoloaded. Can be opened via `CraftingUI.open(workbench)` for standalone Workbenches, or `CraftingUI.open_station(name, recipes)` for NPC-housed stations. Emits `crafting_closed` when the UI closes (used by DialogueUI to auto-close).

### Adding a new recipe = make a `.tres`

1. Right-click `crafting/instances/` → New Resource → `Recipe`
2. Save (e.g., `mix_battle_tonic.tres`) → fill in fields
3. For each input: in the `inputs` array, add a sub-resource → `ItemQuantity` → set `item` and `count`
4. Drag the new recipe into a Workbench's `recipes` array in the scene

No code. Same loop as everything else.

---

## Collision layers

| Layer | Purpose |
|---|---|
| 1 | Walls / world geometry |
| 2 | Player body |
| 3 | Enemy body |
| 4 | Player hurtbox |
| 5 | Player hitbox / player-source projectile hitbox |
| 6 | Enemy hurtbox |
| 7 | Enemy hitbox / enemy-source projectile hitbox |

Pickups and workbenches detect the player via Area2D mask = 2.

---

---

## HUD

`ui/hud.gd / .tscn`, autoloaded — present in every scene, hides while menus are open.

### What it shows

- **Top-left:** health bar with current/max numbers, noise bar, smell bar, status effect icons (below smell bar)
- **Top-right:** soul currency with gold marker
- **Bottom-left:** four weapon slot widgets (primary, secondary, Q rune, F rune), each tinted by element or rune color, with a black cooldown overlay that drains as the cooldown ticks. Rune slots show remaining count (e.g. "Kenaz Runebone ×3") and dim fully when the room's rune has been spent.
- **Floating damage numbers** spawn above any entity that takes damage, colored by element, drift upward and fade

### Architecture

Mostly signal-driven via EventBus:
- `player_health_changed` → HP bar
- `currency_changed` → soul count
- `weapon_equipped` → slot tile refresh
- `player_status_applied` / `player_status_removed` → status indicators (re-emitted by Player from its StatusEffectComponent so the HUD doesn't need a direct reference)
- `damage_dealt_visual` → spawns floating number on target

The exception is **cooldown overlays**, which poll the player every frame. Cooldowns are continuous values, not discrete events — polling is the right tool for genuinely continuous data.

### Damage numbers as a signal

Any entity can take damage. The HUD shouldn't know about all of them. Player and DummyEnemy emit `EventBus.damage_dealt_visual` when hit; the HUD listens once. Adding a new enemy type requires no HUD changes — it just emits the same signal.

### Cooldown overlay trick

A `ColorRect` anchored across the top of the slot. Its `anchor_bottom` updates to the cooldown ratio (1.0 = full, 0.0 = clear). Top-to-bottom drain with zero math beyond the ratio. For a clock-style wedge wipe, you'd swap to a TextureRect with a shader — placeholder rectangles are good enough until art exists.

---

## File map

```
jormund/
├── project.godot                      # autoloads (incl. PathManager, WorldMap, CraftingUI, InventoryUI)
├── globals/                           # input_setup, event_bus, game_state, run_state, path_manager
├── components/                        # health, hitbox, hurtbox
├── status/                            # effect, application, active, component, instances/
│   └── instances/  rune_berserker · rune_vigor · rune_warden · ... (16 rune effects)
├── weapons/                           # base, melee, ranged, magic, swing, instances/
├── items/                             # item, consumable_item, runestone_item, instances/
│   ├── instances/                     # reagent items (bone_tablet, runeslate_tablet, ...)
│   └── runestones/                    # 96 runestone .tres files
├── crafting/                          # recipe, item_quantity, workbench, instances/
│   └── instances/
│       ├── runes/                     # 48 rune crafting recipes
│       └── forge_hearthbrand · envenom_the_bow · buy_*.tres ...
├── npcs/                              # npc, norn, townsperson
├── dialogue/                          # dialogue, dialogue_line, instances/
├── pickups/                           # pickup
├── projectiles/                       # projectile
├── ui/                                # inventory_ui, crafting_ui, dialogue_ui, hud, world_map
├── player/ · enemies/
└── world/
    ├── region_root.gd · exit_zone · scene_transition · arch · bath_house · quest_board
    └── regions/                       # all overworld scenes
        ├── south_cliff · tutorial_1..2 · hollow_glade · wickbarrow_* · forest_path
        ├── forest_edge · saltmarsh_path · beach_dunes · tide_flats · wreck_shoals · storsprunga_town
        ├── wickbarrow_approach · nasus_overlook · nasus_city
        ├── forest_buffer_1..21       # randomized chain pool (2-3 exits each)
        ├── forest_cross_1..10        # 4-way intersections (richer chain topology)
        ├── forest_clearing_1..12     # side-branch reward rooms
        └── test/                     # unused nasus path scenes parked here
```

---

## What comes next

1. **Bullet pattern emitter.** Reusable node for boss/dungeon enemies — spirals, walls, aimed bursts. Required for bosses and bullet-hell dungeon feel.
2. **Living Wood + Deep Gold runestones.** These conduit types need high-level reagents not yet in the game (endgame drops, boss materials). Recipes and effects are defined but ingredients are TBD.
3. **Complex rune effects.** Several runestones have placeholder or approximated effects that need custom implementation: Portable Anvil, Death Ward, Norn's Gamble path reroll, Spirit Companion decoy, Arch Recall teleport, among others.
4. **First procgen dungeon.** Room-based, hand-authored room templates stitched together.
5. **Save/load (real).** Wire up the ConfigFile stub.

---

## Things to keep in mind

- **One Recipe class is correct.** If you find yourself wanting to subclass, ask whether the behavior is actually different. Adding `requires_weapon` as optional was the right move; subclassing into `WeaponRecipe` and `ItemRecipe` would have been duplication.
- **NPCs own their stations.** Hela the Smith doesn't stand next to a forge — she *is* the forge. Set `station_name` and `recipes` on any NPC to give them a craft button in dialog. Standalone Workbench nodes still exist for stations without an NPC (e.g. environmental crafting altars), but the NPC-housed pattern is preferred.
- **Runestones are strategic, not spammable.** One per room per life means each rune is a meaningful decision. Damage values are calibrated for this — a Kenaz Runebone's 55 fire damage is worth more than several weapon swings. Don't lower the damage without also relaxing the one-per-room limit.
- **The Norn auto-discovers recipes.** Drop a new `.tres` in `crafting/instances/runes/` and it appears in the Norn's recipe list. No scene editing required.
- **Recipes can chain.** Soul Phial is craftable AND a possible enemy drop AND an input to other recipes (eventually). The Resource pattern means there's no special "craftable item" vs "drop item" distinction — they're all just Items.
- **Don't gate recipes by code yet.** Story-locked recipes (e.g., "this only appears after meeting the master smith") will become an NPC-level or workbench-level filter that checks GameState flags. Foundation, not feature, until the story system exists.
- **PathManager validates before committing.** `_evaluate_candidate` runs every prospective buffer placement through a full exit-by-exit check: each non-backward exit must land on an empty cell with a matching clearing available, *or* on an existing scene with a reciprocal exit. Any other case rejects the candidate and the next buffer is tried. This is what guarantees the world map never shows a connection line jumping over an intervening scene. Don't add a "best-effort" fallback inside `_build_graph` — if the chain ran out of valid options it should end early (the warning fires in the editor), not draw an incoherent map.
- **The map UI is a renderer, not a planner.** `WorldMap` just reads `PathManager.scene_graph` and draws what's there. All placement decisions live in `PathManager._generate_chain` and `_build_graph`. Adding visual polish (icons, colors, hover) belongs in the map; layout logic belongs in PathManager.
