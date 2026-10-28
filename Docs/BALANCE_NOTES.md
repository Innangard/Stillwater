# Jörmund — Balance & Feel Critique

A game-critic pass on the current build, focused on numbers that look wrong, mechanics whose visual language isn't matching their function, and small fixes that will pay off later. Boss-roster proposals live in `BOSS_ROSTER.md`; this file is everything else.

---

## 1. Player weapon DPS table (current values)

Sorted by raw DPS (damage / cooldown), with my critic notes on outliers.

| Weapon | DMG | CD | DPS | Notes |
|---|---|---|---|---|
| Emberspear | 17 | 0.42 | **40.5** | Spear tier is strictly the best tier on paper. |
| Frostbite Spear | 17 | 0.42 | **40.5** | |
| Thunderstrike Spear | 17 | 0.42 | **40.5** | |
| Venomfang Spear | 17 | 0.42 | **40.5** | |
| Rimeblade | 15 | 0.42 | 35.7 | |
| Sparkblade | 15 | 0.42 | 35.7 | |
| Vilethorn | 15 | 0.42 | 35.7 | |
| Rusted Dagger | 7 | 0.20 | 35.0 | Starter dagger out-DPSing every greatsword is suspect (see below). |
| Briar Fang | 8 | 0.24 | 33.3 | |
| Blightcrusher | 19 | 0.58 | 32.8 | |
| Cinder Maul | 19 | 0.58 | 32.8 | |
| Permafrost Maul | 19 | 0.58 | 32.8 | |
| Stormhammer | 19 | 0.58 | 32.8 | |
| Shadowfang | 9 | 0.28 | 32.1 | |
| Worn Blade | 11 | 0.35 | 31.4 | First weapon. Reasonable baseline. |
| Hearthbrand | 14 | 0.45 | 31.1 | Tier-1 upgrade of Worn Blade. |
| Pilgrim's Mace | 16 | 0.55 | 29.1 | |
| Bare Hands | 4 | 0.20 | **20.0** | Floor. Good — punishes losing your weapon but doesn't trivialise. |
| Emberlance Bow | 16 | 0.90 | 17.8 | Ranged tier (correctly lower than melee, see below). |
| Glacial Arc | 16 | 0.90 | 17.8 | |
| Stormpierce Bow | 16 | 0.90 | 17.8 | |
| Venomfall Bow | 16 | 0.90 | 17.8 | |
| Longbow | 15 | 0.85 | 17.6 | |
| Cindershot Bow | 9 | 0.60 | 15.0 | |
| Froststring Bow | 9 | 0.60 | 15.0 | |
| Voltbow | 9 | 0.60 | 15.0 | |
| Crooked Bow | 8 | 0.55 | 14.5 | Starter bow baseline. |
| Bone Crossbow | 23 | 1.70 | 13.5 | |
| Chipped Greatsword | 13 | 1.00 | 13.0 | **Problem.** |
| Verdigris Sting | 4 | 0.50 | **8.0** | **Problem.** |
| Splinter Volley | 5 | 1.80 | **2.8** | **Problem.** |
| Pilgrim's Spear | 13 | (missing) | ? | **Bug.** Cooldown field is empty. |

### 1a. The cooldown bug on Pilgrim's Spear

`weapons/instances/player_weapons/pilgrim_spear.tres` has no `cooldown` value. In Godot a missing field defaults to 0, which means the weapon fires every frame. Either it's unusable (because something else throws) or it's the strongest weapon in the game by an enormous margin. Set it to **0.45** to match the other spear-tier weapons but slightly slower (since it's a pilgrim's tool, not a war weapon).

### 1b. Splinter Volley at 2.78 DPS is a trap weapon

If a player picks this up they will feel like the game is broken. **Either** the weapon needs to fire multiple projectiles per attack (which the name implies — "volley") and the DPS field above doesn't reflect that, **or** the numbers are simply wrong. Check whether `projectile_count` is greater than 1. If it is, the DPS in the table is per-projectile-line and the effective DPS is higher. If it isn't, the weapon shouldn't exist at these numbers — either raise damage to ~12 (making it a slow-but-punchy ranged option, ~6.7 DPS still low but at least *thematically* a heavy thrown weapon) **or** give it a unique mechanic like piercing through 3 enemies (so it shines vs hallway crowds).

### 1c. Verdigris Sting at 8 DPS

This is in the same boat as Splinter Volley — a weapon whose effective damage doesn't justify its slot. Verdigris is patina-on-copper, the name implies a slow corrosion weapon. The fix isn't to raise the base damage; it's to make the *poison status chance* on it very high (e.g. 100% poison stack per hit). Then the low base damage becomes a feature: it's a status-applicator that ramps damage over time. Document the design intent in the resource file's `description` so the player knows.

### 1d. Chipped Greatsword

13 damage on a 1.0s cooldown is a 13 DPS weapon, which puts it under the basic bow. A "greatsword" in this game should feel **big** — bigger swing arc, bigger knockback, bigger single-hit number, slow cadence. I'd retune to **24 damage, 1.1s cooldown** (21.8 DPS — still below mainline melee, but each swing feels meaningful) and give it a wider swing arc so it catches multiple enemies. The greatsword's identity should be *crowd control through swing radius*, not raw DPS.

### 1e. Rusted Dagger is too good for a starter

7 damage on 0.20s cooldown is 35 DPS — above the basic Worn Blade (31.4) and tied with several mid-tier upgrades. A starter weapon shouldn't beat the upgrade path. Either drop the dagger to **5 damage / 0.22 cooldown (22.7 DPS)** or — better — make the dagger a *dedicated backstab weapon*: hits from behind deal 3× damage. Now it's a positioning skill weapon that rewards play instead of just being numerically dominant.

### 1f. Melee vs ranged spread is healthy

Best melee ~40 DPS, best ranged ~18 DPS. That 2× factor is well-tuned for a game where melee puts you in danger. Don't compress it. The current ranged weapons are correctly under-DPSing the melee tier; what they offer is *safety*, and that's the right trade.

---

## 2. Boss HP scaling

You confirmed Cinder Sovereign is at 1600 HP currently. That fits the curve I proposed in the roster (1000 → 1200 → 1400 → 1600 → up from there) cleanly at the 4th slot — its placement on the south → west → north → NE → center route. Keep that HP value as the curve fills in around it.

**Sanity check on a mid-tier fight time:**
- Mid-game player DPS: weapon ~35 + 1 rune per room averaged over a fight (~30 damage / 30s averaged = +1 DPS… so basically 35 DPS over a long fight).
- Sovereign at 1600 HP → ~46 seconds to kill at constant DPS.
- Real fights are not constant DPS — there's dodging, recover frames, missed swings. Real time-to-kill is probably 60–70 seconds. That's right in the sweet spot for a mid-tier boss.

If you find players are clearing the Sovereign in under 30 seconds during playtests, the issue is more likely *rune strategy* than HP — a player who has six Kenaz Runebones (55 damage each × 4 conduits stockpiled) can dump 220+ damage in their first room. The one-rune-per-room rule prevents the worst of this but doesn't prevent saving runes specifically for the boss room. That's correct design — players who *prepare* should be rewarded.

---

## 3. Difficulty multipliers — sanity check

Reviewing `globals/difficulty_settings.gd` numbers:

| Knob | Easy | Normal | Hard |
|---|---|---|---|
| Enemy HP | 0.7× | 1.0× | 1.3× |
| Enemy damage | 0.7× | 1.0× | 1.3× |
| Enemy movement | 0.8× | 1.0× | 1.2× |
| Enemy projectiles | 0.8× | 1.0× | 1.2× |
| Player regen | 2/s up to 50% | — | — |

These are good and your design notes defend them well. One nit: **Hard mode at 1.3× damage means the Sovereign Pyre (5 base damage, ticks at 0.2s) deals 6.5 per tick, or ~32 damage per second of cone exposure.** That's ~half the player's HP per second on Hard. Combined with the burn it applies, a single greedy approach to the Sovereign on Hard can be fatal. This is probably fine — it teaches players to respect the cone — but be aware of it during playtesting.

The bigger risk on Hard is the **stacked persistent attacks** in tight rooms. The Skeleton King's bone-burst (12 projectiles in a 330° spread) at 1.3× damage hits for ~9 each after the rebalance (was ~16 pre-rebalance — see section 11). On a small arena with the four phase-2 pillars, the player can be pinned. The rebalanced values make this survivable but still punishing, which is the right feel for Hard mode.

---

## 4. Phase transition timing

Both existing bosses phase at the same moment relative to their fight time: ~40% HP. That's fine for variety until the player has fought ten bosses and every single one phases at the same beat — at which point it'll feel mechanical. **Suggestion:** vary phase triggers across the boss roster so the player can't predict the moment.

| Boss | Phase trigger | Why |
|---|---|---|
| Skeleton King | 30% HP | *(existing)* Late phase = brutal pillar-spawn turning point. |
| Galgi the Bound | 50% HP | A "halfway" snap fits the rope-cutting beat. |
| Drowned Crone | 40% HP | Flood floods more of the arena. |
| Cinder Sovereign | 40% HP | *(existing)* Beam appears, learn it before death. |
| Sindri's Apprentice | 50% HP | The quench beat is exactly the midpoint. |
| Gymir | 40% HP | Hollow reveal mid-fight. |
| Skadi | 45% HP | Bow → lance shift slightly past halfway. |
| Hrímfaxi's Get | 50% mother HP | Mother's howl beat. |
| Ash-Sprout | 50% HP | Heart opens at midpoint. |
| Eir | 50% HP (snap) + 0% HP (revive) | Two phase shifts. |
| Heimdall's Echo | 40% HP | Drops the shield. |
| Tyrant King | 1000/1000/1500 staged | HP bar is per-phase, not split. |

---

## 5. Visual polish observations

### 5a. Both existing bosses are circles with crowns

The Skeleton King and the Cinder Sovereign are visually distinguished by tint (pale → red) and crown shape (3-point → flame-tongue). That's clean *placeholder* design. As art comes in, every boss in the roster needs a distinct silhouette. The current `_draw()` functions for placeholders should keep the variety going even in placeholder land:

| Boss | Placeholder silhouette idea |
|---|---|
| Galgi the Bound | Tall vertical capsule with a *visible noose* polygon above the body |
| Drowned Crone | Wide-base triangle (stooped), with a net pattern overlaid |
| Sindri's Apprentice | Squat square body, glowing seams |
| Gymir | Tallest body radius in the game (32px), grey, with a chest crack |
| Skadi | Tall thin rectangle, bow silhouette in phase 1 / lance in phase 2 |
| Ash-Sprout | Stationary, irregular polygon (not a circle), brown |
| Eir | Triangular wing silhouette behind a circle body |
| Heimdall's Echo | Standard knight silhouette + visible horn polygon |

The point: even without art, no two bosses should be the same shape on the screen.

### 5b. Telegraph palette consistency

The yellow-warning → red-strike palette is used everywhere (mooks, both bosses) and that's correct — it's the game's combat language. **Don't ever break that contract.** If a future boss needs a new attack type with no parry option (e.g. Eir's tracking soul-spear), telegraph it in a *third* colour (purple? white?) so the player learns "this colour cannot be parried." Don't let a red-flash telegraph turn out to be unparryable; that breaks the entire game's combat language.

### 5c. The boss death FX

Looking at `boss_death_fx.gd` — the hit-stop + shake + ash burst + fade-out + bonus drops is a strong sequence. **Make sure each boss's ash burst is tinted to its `body_tint`** (the existing code passes it in, looks correct). The Cinder Sovereign should burst in fire-orange, Gymir in pale-blue, Skadi in white, Ash-Sprout in green-gold. This is free polish and makes each kill feel distinct.

### 5d. Phase-2 visual cue is currently subtle

Both existing bosses tint slightly in phase 2 (Skeleton King purple, Sovereign red). On a screen full of effects this is easy to miss. Consider one of:
- A **screen flash** on phase transition (white, 0.15s).
- A **boss bar colour change** on the HUD (current → phase-2 tint).
- A **camera shake** burst (0.4s, light).

The phase change is a meaningful narrative beat in every fight. It should be *unmissable*.

### 5e. The crown is the only "this is a boss" affordance

The crown polygon both existing bosses draw is what makes them read as bosses at a glance. As you add bosses, *not all of them should have crowns* — that's a king-and-queen marker. Galgi (a hanged corpse-knot) should not have a crown. Hrímfaxi (a wolf-mother) should not. Reserve the crown silhouette for *royalty* — Skeleton King, Cinder Sovereign (sovereign = royal), and the Tyrant King himself. Maybe Heimdall's Echo (gold half-circle halo above head). The rest should have other affordances: huge body, glowing eyes, distinct particle trail, *something* that says "this is the boss" without crowning every monster on the island.

---

## 6. Small numerical issues I spotted

| File | Issue | Suggestion |
|---|---|---|
| `worn_blade.tres` | name field is `"Chipped Greadsword"` (typo: Greadsword) in `chipped_greatsword.tres` | Fix typo. |
| `pilgrim_spear.tres` | Missing cooldown | Set to 0.45 |
| `splinter_volley.tres` | 2.78 DPS | Add projectile_count or rework |
| `verdigris_sting.tres` | 8.0 DPS, no clear identity | High poison stack, low base, document as DoT weapon |
| `chipped_greatsword.tres` | 13 DPS, under bow tier | Damage 24 / CD 1.1s, wider arc |
| `rusted_dagger.tres` | 35 DPS starter weapon | Either lower DPS or add backstab multiplier |

Each of these is a 30-second edit in the inspector.

---

## 7. Rune economy sanity

96 runestones (24 runes × 4 conduits) is *a lot*. The one-per-room rule is the right constraint. A small concern: the Bone Tablet conduit is the offensive tier and the player will, in practice, only ever stockpile bone tablets. The Runeslate (utility), Living Wood (helpful — future content), and Deep Gold (amplified — future content) conduits will be underused if their effects don't *meaningfully* differ from Bone Tablet damage.

**Recommendation when designing the unfinished conduits:**
- **Runeslate** must feel as good as Bone Tablet in its niche. A utility rune that grants a 10-second berserker buff should be *clearly* better than a single 55-damage hit in fights longer than 15 seconds. Make the math support the choice.
- **Living Wood** (healing) needs to compete with potions. If a Living Wood Algiz heals 30 HP and a potion heals 30 HP, the rune is strictly worse (uses a slot, has one-per-room limit). Living Wood runes should heal *more* than potions (e.g. 50–60 HP) or grant *temporary max HP* on top of healing.
- **Deep Gold** (amplified) is meant to be endgame. The natural design is "Kenaz Runebone for 55 damage, Kenaz Runegold for 110 damage and a 2-second armour buff." Make them feel like *splurges* — much rarer drops, higher reagent costs.

---

## 8. The smell + noise systems

I dug into this enough to understand them — noise (transient) and smell (persistent) drive enemy detection. This is a beautiful system that's currently a bit under-used because the existing enemies have such different sensitivities (kobolds 0–4, wolves 11 smell, crab 10 noise) but the player has no in-game way to *see* their own noise/smell numbers relative to enemy thresholds. The HUD shows the player's noise and smell bars — but those are absolute values, not "how close to being detected by what's in the next room."

**Suggestion:** Add a faint glow effect on the *enemy itself* when the player is approaching their detection threshold. Subtle. Half-transparent. Pre-aggression. Lets the player feel like a hunter rather than a person walking blindly into a fight.

---

## 9. The "world is dying" should be visible

The story bible covers this; the implementation note here is: **the Yggdrasil-seedling on the western island is the perfect visual barometer of the game's stakes.** First time the player visits, it has green leaves and lights in the branches. After they activate the West arch (= after defeating Sovereign), some branches are bare. After defeating the Ash-Sprout (= the seedling's corrupted offspring), more of the tree is dead. By the final act, the seedling is a black skeleton.

Mechanically this is just three or four scene variants of the same region triggered by story flags. Visually it does enormous work: the player can *see* the world failing, in a way that bare dialogue alone cannot achieve.

---

## 10. Things to definitely not do

A few traps that look tempting on a project this complex:

- **Don't add a stamina bar.** The dash with i-frames is the player's main defensive tool. Putting it on a stamina budget changes the game from action to action-resource-management, which is a different genre.
- **Don't add boss-only weapon resistances.** The kennings already give the player elemental modifiers; let the player's *build* counter resistances. A boss that resists everything is anti-build.
- **Don't make any boss respawn-able for grinding.** The boss kills are story flags. Grinding makes the second kill mean nothing.
- **Don't add timed bosses.** A boss that wipes if you don't kill it in 60 seconds breaks the game's pacing. The closest acceptable version is Sindri's Apprentice's quench-interrupt window — a *single* DPS-check moment inside a longer fight, not a fight-wide clock.
- **Don't reuse the parry-window red-flash for an unparryable attack.** This is the single most important UI contract in the game.
