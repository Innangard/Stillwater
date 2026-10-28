# Jörmund

A top-down action RPG with roguelite progression, built solo in Godot 4 and GDScript. It mixes Zelda-style exploration, souls-like combat and a deep layer of Norse myth.

## The premise

Jörmund is the long shore between life and death. Souls wait there for their turn at the Life Pool, where they are unmade and sent back to be born again. A warlord named Hjarrandi refused the water, built a tower in the central lake and talked others into refusing with him. With nobody passing on, nobody is born, and the living world is winding down.

Skuld, the Norn of what shall be, reached across the threshold and pulled you down to the shore. You are the only living soul on an island of the dead: you bleed red where everything else bleeds black ash, and you have no name. On Jörmund names are power. The bosses are souls who held on to who they were so hard it twisted them, and every one you lay to rest leaves you its title.

## What I've built

- A procedurally laid out overworld. A PathManager autoload stitches hand-made rooms into 44 seeded chains across the island, and validates every placement so rooms never overlap or connect diagonally.
- Combat built on one telegraph rule: yellow means the attack is coming and can be parried, red means it is live. Dash with i-frames, shields, parries and elemental status effects (burn, freeze, poison, shock, bindings).
- Enemies that hunt by sense. Noise spikes when you move and fight, and smell builds up because your red blood stands out. Sneaking and certain items keep both down.
- Runes as the per-run build: 24 Elder Futhark letters across 4 conduit tiers make 96 runestones, each giving a stacking passive bonus.
- Kennings as the meta-progression: Norse titles taken from bosses and quests that stay with you through death. You can equip four at a time.
- Crafting run through NPCs. Smiths, merchants and Norns hold their own recipe lists, and the craft button is right in the dialogue box.
- Bosses, each with their own attack cycle, phase changes and minions, from the Skeleton King in the south to Heimdall's Echo at the Crowned Bridge.
- Towns, altars, dungeon entrances and dungeon interiors for four acts, plus a world map, quest log, three save slots and three difficulty settings.

## Current state

Acts I to III have their regions, towns, altars, dungeons and bosses in place. Act II and III content is new and still being balanced and played through. These aren't in yet:

- The final boss, Hjarrandi turning into Níðhöggr in the King's Tower
- Tier 3 equipment and the Act III town recipes that depend on it
- Quest board postings beyond the main story quests
- Optional challenge bosses in the eastern region

## Running it

1. Install Godot 4.6 (standard build, not .NET). The project uses the GL Compatibility renderer.
2. Clone this repo, open Godot and import project.godot.
3. Press F5. The game starts at the title screen, where you can pick a save slot and difficulty.

The first time you open it, Godot rebuilds its .godot cache folder, which takes a minute.

## Controls

- WASD to move, mouse to aim
- Left click for the primary weapon, right click for the secondary (hold to block with a shield)
- Space to dash, hold Shift to sneak
- Q to swap weapon sets, R to open runes
- E to interact
- I for inventory, M or Tab for the map, J for the quest log, K for kennings
- Esc to pause, F11 for fullscreen

## How it's put together

Most content is data. Weapons, items, runestones, recipes, status effects, kennings, quests and dialogue are all Godot Resources (.tres), so adding one doesn't need new code. Entities are built from components (health, hitbox, hurtbox, status effects) and talk through an EventBus autoload instead of holding references to each other. State is split into three tiers: GameState for what survives death, RunState for what is lost on death, and the scene for everything else.

I wrote Python scripts to generate scenes in bulk, such as the room pools, boss rooms, towns and enemy weapon resources. Those scripts aren't part of this repo, but everything they produced is.

## Project layout

```
project.godot        engine settings and autoloads
globals/             EventBus, GameState, RunState, PathManager, saving, difficulty, input
components/          health, hitbox and hurtbox components
player/              player controller
enemies/             enemy and boss scripts and scenes
weapons/             weapon classes and every weapon .tres
projectiles/         standard and returning projectiles
status/              status effect system and effect resources
items/               items, consumables and the 96 runestones
crafting/            recipes, workbenches and the crafting registry
kennings/            kenning resources and KenningManager
quests/              quest resources and QuestManager
npcs/                NPC, Norn, Observer and townsperson
dialogue/            dialogue resources for every NPC
pickups/             world pickups
ui/                  HUD, inventory, crafting, dialogue, map, menus
world/               region root, exits, arches, transitions
world/regions/       every overworld and dungeon scene, one folder per room pool
sprites/             art
Docs/                design documents
```

## Design docs

The detail lives in Docs/ instead of here:

- SYSTEMS_REFERENCE.md covers every gameplay system, the autoloads and file naming conventions
- STORY_BIBLE.md and STORY_BIBLE_EXPANDED.md cover the lore, regions, settlements and tone rules
- BOSS_ROSTER.md has every boss's attacks, phases and HP
- BESTIARY.md has the regular enemies
- BALANCE_NOTES.md and DESIGN_NOTES.md have tuning numbers and the reasons behind design decisions
