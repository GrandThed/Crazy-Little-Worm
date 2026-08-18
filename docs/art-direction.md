# Crazy Little Worm — Art Direction v0

**Status: direction locked, numbers provisional.** The shapes of the rules below are the
decisions; individual constants are knobs, same convention as
[game-design.md](game-design.md).

Everything here was chosen by building it, not by arguing about it. The comparison scene
lives at [../art/blender/style-probe.blend](../art/blender/style-probe.blend), regenerates
from [../art/blender/style_probe.py](../art/blender/style_probe.py), and its renders are in
[../art/blender/renders/](../art/blender/renders/).

---

## 1. The direction

**Chunky toybox forms, articulated limbs, baked-in depth, no textures.**

A bright, saturated, injection-moulded-toy park. Oversized heads, confident fat shapes,
candy colours. Depth comes from ambient occlusion baked into **vertex colours** — not from
texture atlases. One material for the entire game.

**Baseline mood is cheerful.** The park is sunny and charming at all times. Every bit of
unease comes from the anomalies themselves. This is a deliberate contrast play: a 9-foot
alien in a trenchcoat is funnier in a happy park, and the star-rating review page
(game-design.md §5) lands harder when the park *looks* like it deserves five stars.

We do **not** do sun-bleached liminal-space horror. It would fight the tone rule in
game-design.md §4 — salt puffs, thumbs-up, no gore.

---

## 2. Why this and not the alternatives

Four candidate directions were built as full bays — each with its own proportions, part
count, and shape vocabulary, not just its own shader. Findings:

| | Parts/bay | Verdict |
|---|---|---|
| **A** Chunky Toybox | 139 | Best tell contrast. Stubby arms limit expression. |
| **B** Hand-Painted | 216 | Best-looking. Smaller head weakens the skin tell; real version needs texture atlases. |
| **C** Vector Flat | 105 | Boldest colour read, cheapest — **disqualified**, see below. |
| **D** Semi-Real | 238 | **Disqualified** — actively damages the core loop. |

Three findings drove the decision:

**Head size is a gameplay variable.** The Infected's tell is *skin tint*. On a big-headed
toybox guest the head is a large pale-green block you catch in peripheral vision; on a
realistically-proportioned guest it shrinks to a postage stamp. Compare
[21_tells_Atoybox.png](../art/blender/renders/21_tells_Atoybox.png) against
[24_tells_Dpbr.png](../art/blender/renders/24_tells_Dpbr.png).

**Desaturation halves tell contrast.** D's muted palette is generated from the *same* source
colours by a `mute()` function, so it is a fair test of the treatment. Realism and
legibility are in direct conflict here, and legibility is the game.

**Armless styles can't do the signature beat.** C's card-slab guests read beautifully, but
game-design.md §4 makes "rescued guests give a thumbs-up and carry on" the tone rule for the
whole game. No arms, no thumbs-up. Disqualified by our own design pillar rather than by
taste.

So: **A's proportions carrying B's articulation.**

---

## 3. Scale and units

- **1 Blender unit = 1 Roblox stud.** Model at stud scale so silhouettes are judged at true
  in-game size from the first block.
- A guest is **~5 studs** tall, matching an R15 character.
- Reference heights: gate booth 6 (9.6 to the sign top) · carousel 16.8 · Alien-in-a-coat
  **11.2** (deliberately more than double a guest — the tell must survive a crowd).
- `+Y` is "behind the counter"; guests queue along `+X`. Assets face `-Y`.

> **Calibrate once before authoring the catalogue.** Roblox's mesh importer has its own
> scale handling, so export one 1×1×1-stud test cube, import it, and confirm it lands at
> exactly 1 stud. Adjust the FBX export scale once and record it here. Do not assume.

---

## 4. Guest specification

The locked guest is **12 blocks**, merged into a single MeshPart on export.

| Part | Size (studs) | Placement |
|---|---|---|
| Head | 1.70 cube | on top, centre |
| Hair | 1.80 × 1.80 × 0.51 | capping the head |
| Torso | 2.30 × 1.20 × 1.90 | |
| Collar | 1.66 × 1.27 × 0.26 | at the shoulder line |
| Arm ×2 | 0.72 × 0.82 × 1.62 | at x ± 1.58 |
| Hand ×2 | 0.78 × 0.89 × 0.40 | below each arm |
| Leg ×2 | 0.88 × 0.92 × 1.45 | at x ± 0.56 |
| Shoe ×2 | 0.97 × 1.24 × 0.30 | under each leg |

**Head-to-body ratio is a hard rule, not a style preference.** The head must stay at or
above ~1.6 studs. It is the primary display surface for the Infected tell and the largest
readable area on a guest at gate distance. Shrinking it for "better proportions" is a
gameplay regression.

### Anomaly tell budget

Every anomaly tell must be legible at **~25 studs** (roughly the gate-queue read distance,
which is what `CAM_*_TELL` frames). Tells fall into two classes:

- **Silhouette tells** — Alien-in-a-coat. Read at any distance, survive crowding and
  occlusion. Use these for the loud, early-game anomalies.
- **Colour-patch tells** — Infected skin tint. Need a large, unbroken, well-lit surface,
  which is exactly why the head is oversized.
- **Accessory tells** — the cult amulet. Smallest and most fragile; must sit on the chest
  facing `-Y`, in a colour with high contrast against every shirt colour in the palette.
  Gold on the candy palette clears this; verify against any new shirt colour added later.

Per game-design.md §3, every tell needs an innocent lookalike in the normal guest
population. Budget palette slots accordingly — do not let a tell colour become unique to
anomalies, or pattern-matching collapses into colour-spotting.

---

## 5. Palette

Semantic slots, not raw colours. Assets reference the slot; retinting the game means
editing this table once.

### Park furniture
| Slot | Hex | Use |
|---|---|---|
| `BOOTH_BODY` | `#FFF3E0` | cream structure walls |
| `BOOTH_TRIM` / `ROOF_A` | `#FF6B6B` | coral roofs, awning stripe A |
| `ROOF_B` | `#FFF5E1` | awning stripe B |
| `COUNTER` | `#C89666` | wood counters, planters |
| `SIGN` | `#4ECDC4` | mint signage |
| `DARK` | `#2D3142` | navy outline/base/shadow accent |
| `GROUND` | `#7BC950` | grass |
| `PATH` | `#E8DCC8` | paths and ride decks |

### Guests
| Slot | Hex | Use |
|---|---|---|
| `SKIN` | `#F2C49B` | ordinary skin |
| `SHIRT_A` | `#5AA9E6` | |
| `SHIRT_B` | `#FF9FF3` | |
| `PANTS` | `#3D5A80` | |

### Anomaly tells — reserved, never use for ordinary guests
| Slot | Hex | Anomaly |
|---|---|---|
| `INFECT_SKIN` | `#A8C686` | Infected |
| `INFECT_SHIRT` | `#6B8F3D` | Infected |
| `ALIEN_COAT` | `#3D405B` | Aliens in a coat |
| `GOLD` | `#FFC857` | cult amulet (also ride trim) |

### Rides
| Slot | Hex |
|---|---|
| `RIDE_A` | `#FF6B6B` |
| `RIDE_B` | `#FFE66D` |
| `RIDE_POLE` | `#E6E6E6` |
| `HORSE` | `#FFF5E1` |

---

## 6. Baked vertex-colour AO — the load-bearing technique

This is what lets the locked style look like the hand-painted bay while costing like the
toybox bay. Instead of a texture atlas, an occlusion term is written into a per-vertex
colour layer named `AO` and multiplied into the flat base colour.

Two terms, multiplied:

1. **World height** — the park floor is dark, shoulders are lit. Ramps from `0.62` at ground
   to `1.0` at 5.5 studs.
2. **Per-block height** — every block darkens at its own underside. Ramps `0.80 → 1.0` across
   each block's own bounds. *This* is the term that separates an arm from the torso behind
   it, and it is why the technique works at all.

Constants live at the top of `style_probe.py` (`AO_WORLD_TOP`, `AO_WORLD_FLOOR`,
`AO_LOCAL_FLOOR`) and `bake_vertex_ao()` is the reference implementation.

**Consequences:** no UV unwrapping, no texture memory, no atlas coordination between
artists, one material across the whole game, and a builder can drop in a new asset without
touching a texture.

> **Verify before committing the pipeline.** Roblox MeshParts are expected to carry vertex
> colours through FBX import, but this has **not** been tested in this project. Export one
> AO-baked guest, import it, and confirm the gradient survives. If it does not, the fallback
> is a single tiny shared gradient atlas — more setup, same look — so the art direction
> survives either way, but the workflow changes and this doc must be updated.

---

## 7. Geometry rules

**Guests: no bevel.** At 120 on-map and a few dozen pixels tall each, bevel geometry is
wasted — the vertex AO already provides the form separation that bevels would have given.

**Buildings and rides: bevel 0.13, 2 segments, 35° angle limit.** These are large on screen
and static; the bevel highlight is what sells the moulded-plastic read.

**Cylinders: 16 sides.** Below 12 the faceting reads as an error rather than a style; above
20 is invisible at gameplay distance.

**Large flat faces need a trim piece.** A bare 8×6 booth wall reads cheap. The locked booth
adds a window frame, a sill, a gold sign edge, and a planter for exactly this reason — the
minimum decoration that keeps a big surface alive.

### Budgets (targets, to be validated on device)

| Asset | Triangles | Notes |
|---|---|---|
| Guest | ≤ 250 | single MeshPart, one material, no bevel |
| Small prop | ≤ 500 | |
| Building / booth | ≤ 2000 | |
| Ride | ≤ 3000 | |

Roblox's hard ceiling is 10,000 triangles per MeshPart; these targets sit far below it
because the constraint is 120 simultaneous guests on mobile, not the per-mesh limit.

---

## 8. Lighting

- Sun elevation ~52°, azimuth ~38°, energy ~4.2, warm white `(1.0, 0.96, 0.89)`, soft
  angular diameter (~3°) for gentle park shadows.
- Sky `#8FC7F5` at ~0.85 strength, doubling as fill.

These are the Blender look-dev values, which is what the renders were judged under. They
are a *target* for the Roblox Lighting/Atmosphere setup, not a direct transfer — Roblox's
lighting model differs and will need its own pass.

Time-of-day variation across the day cycle (Prep dawn → Gates Open bright → Closing amber →
Summary dusk) is **deferred**, not rejected. It would get free drama out of the existing day
cycle, but at a 12-minute day the transitions need care. Revisit after the core loop is
playable.

---

## 9. Workflow

The comparison scene is fully procedural — no hand-modelling. Palette, proportions, part
counts, bevel widths, and budgets are all constants at the top of `style_probe.py`. Changing
the art direction means editing a table and re-running, which is what made a five-way
comparison affordable at all.

Regenerate from inside Blender:

```python
exec(open(r"<repo>/art/blender/style_probe.py").read())
```

The scene carries an orthographic overview camera (all bays at identical scale, so the
comparison is not skewed by perspective) plus four cameras per bay: whole bay, tell
close-up, palette board, and carousel.

Per the level workflow in CLAUDE.md, Rojo syncs **code only**. Blender sources live in
`art/blender/`; exported ride and level models are committed as `.rbxm` under
`game/assets/`.

---

## 10. Open questions

- Vertex-colour survival through Roblox FBX import (§6) — blocks nothing until asset export
  begins, but must be answered before the catalogue is authored.
- Stud-scale export calibration (§3).
- Tells not yet probed: corporate spy (suit + briefcase, with innocent lookalikes) and
  shapeshifter (whose tell is an *idle stance*, i.e. animation, not geometry — the one tell
  this static probe cannot evaluate).
- Ride tier-upgrade visual ladder (tier 1/2/3) and the broken/damaged ride state — both are
  in game-design.md §2 but have no visual language yet.
- Whether 120 guests drawn from 4 shirt colours reads as a crowd or as clones. Probe with a
  30-guest render at true gameplay camera distance.
- Roblox lighting pass to match §8.
