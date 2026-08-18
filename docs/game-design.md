# Crazy Little Worm — Systems Design v0

All numbers are **tunable placeholders** — the shapes of the formulas are the decisions, the constants are knobs. Server-authoritative everything (see `server-architecture` skill).

## 1. Guest AI — minimal-state needs system (RCT-style)

Guests are lightweight server-side agents. Four needs, each 0–100 (100 = satisfied), decaying over time:

| Need    | Decay      | Refilled by            | Notes                                   |
|---------|-----------|------------------------|-----------------------------------------|
| Fun     | −0.2/s    | Riding attractions     | Primary driver of ride-seeking          |
| Hunger  | −0.1/s    | Food stalls (pays)     | Shop revenue source                     |
| Bladder | −0.08/s   | Bathrooms              | Bathrooms are also the cult ritual site |
| Fear    | +events   | Decays −0.5/s passively| Raised by witnessing incidents/zombies  |

**States**: `GateQueue → AtGate → Wander → RideQueue → Riding → UsingFacility → Leaving` plus anomaly-driven `Fleeing`, `Zombified`. Decision rule (every ~5s or on state end): pick target with highest `urgency = (100 − need) × weight`, go to nearest provider. `Fear > 70` → `Fleeing` → leaves park as a *scared exit*.

**Exit happiness** (feeds satisfaction): `H = 0.4·Fun + 0.2·Hunger + 0.15·Bladder + 0.25·(100 − Fear)`.

**Money**: entry fee on admission (fixed price v0) + food purchases. Revenue scales with admissions and dwell time — no per-ride fees (v0 simplicity).

**Performance**: simulated guest cap ≈ **120** on-map. Arrivals beyond capacity and queue tails beyond the front ~8 per stand are abstract counters, not characters. Guest visuals/animations are client-side dressing over minimal replicated state.

## 2. Attraction Index (the hard math lives here)

Scale 0–1000 (RCT park-rating homage). The single coupling variable between all systems.

```
RideAppeal_r  = BaseAppeal(type) × (1 + 0.25·(tier − 1)) × condition    -- broken ride = 0
ParkAppeal    = 6 × (Σ RideAppeal_r)^0.9                                 -- diminishing returns
Satisfaction  = EMA of exit happiness, α = 0.1 per exit  (0–1)
IncidentP     = Σ incident severities, decays ×0.5 per day
AttractionIdx = clamp( ParkAppeal × (0.5 + 0.5·Satisfaction) − IncidentP, 50, 1000 )
```

**Inflow**: `arrivalsPerMinute = 2 + AttractionIdx / 50` (≈4/min at floor, 22/min maxed).

The **floor of 50** is the anti-soft-lock guarantee: a wrecked park still trickles guests and income. See §7 for the loan backstop.

**Difficulty scaling (anti-snowball)**: daily anomaly slots `= 1 + floor(AttractionIdx / 250)` (1–5), and higher index unlocks subtler anomaly types (§4). Growing the park voluntarily raises the difficulty.

## 3. Gate / ticket management

**Stands**: 1–4 entry stands, buildable. Each processes one guest at a time. Player-manned = skill-based inspection. NPC clerk = automatic: throughput ~6 guests/min, detection accuracy by staff tier (50/65/80%), ~5% false-positive rate.

**Queue patience**: each queued guest has `patience` 100, −1/s while waiting. At 0 → walkaway: lost revenue + satisfaction penalty (counts as an unhappy exit). Multiple stands split the arrival stream.

**Ticket card (v0 — deliberately simple, 4 fields)**: Name · Serial (letter + 4 digits) · Type (Adult / Child / VIP) · Date. Inspection UI shows the card plus the guest model; Approve / Deny buttons.

**The three-way penalty rule** (no degenerate strategy may win):
- *Wave everyone through* → anomaly incidents (IncidentP).
- *Scrutinize forever* → patience walkaways hit Satisfaction, which hits AttractionIdx (not just today's cash).
- *Deny on any doubt* → a denied guest simply pays nothing. No fine, no complaint — the cost of over-denying is starved revenue and stalled progression. (Watch in playtests whether this is enough pressure; a fine can be added later if deny-all emerges as a strategy.)

**Ambiguity principle**: every anomaly tell has an innocent lookalike in the normal guest population (legit businessmen with briefcases, tall guests, guests with jewelry), so pattern-matching, not reflex-denial, is the skill.

**Detection upgrades** shift work, never remove it: scanners flag *suspicion* with false positives — the player still decides.

## 4. Anomalies

**Lifecycle**: `Infiltrate (gate) → Dormant (blends as guest) → Activate (timer/trigger) → Incident → Contained | Escalates`. The anomaly truth flag is server-only; clients receive only cosmetic tell data (see skill).

Each anomaly attacks a different system:

| Anomaly | Attacks | Gate tell (physical) | Gate tell (ticket) | Inside behavior | Counter | Severity |
|---|---|---|---|---|---|---|
| **Infected** | Anomaly response | Pale/green tint, cough loop | Stained/smudged ticket | Incubates 90s → zombie; chases guests, tag converts in 20s → exponential spread; Fear AoE | Security engages; player capture tool; infirmary cures if detected while dormant | 8 + 2 per conversion |
| **Corporate spy** | Park economy | Suit + briefcase (innocent lookalikes exist) | Wrong/fake date | Targets highest-appeal ride, 15s tamper → condition −40% (<30% = breakdown); up to 3 rides | Cameras reveal tamper; security/player catches in the act | 6 per ride broken |
| **Shapeshifter** | Staff / trust | Ordinary guest | **Name field matches a staff member** | After 120s replaces an isolated staff NPC and does nothing: clerk-mimic auto-approves everyone (infiltration floodgate), mechanic-mimic never repairs, security-mimic ignores incidents | Idle-stance tell; manager clipboard tool inspects staff | 10 on reveal + lost staff + multiplier on other anomalies |
| **Aliens in a coat** | Single ride | Double-height, wobbly walk | **Child ticket** despite being 9ft tall | Goes to fastest ride, 60s tamper → ride speed visibly ramps → launches into space: ride destroyed, big Fear spike | E-stop the ride from its control panel (resets + exposes them); catch while tampering | 12 if launched |
| **The cult** | Gate pattern-recognition | Shared amulet accessory | **Consecutive serial numbers**, same date | Individually harmless. At ≥4 inside → converge on a bathroom, light candles, kidnap any guests inside; **180s ritual** with a particle plume visible from outside the bathroom; on completion the kidnapped guests **disappear** | **Throw salt** at cultists → they evaporate in a puff; rescued guests give a thumbs-up and resume their day | **Police-bribe fine at Summary per disappeared guest** (e.g., 200 ea.) |

**Tier gating by AttractionIdx**: <200 pool = {infected, aliens} (loud tells); ≥200 +spy; ≥400 +cult; ≥600 +shapeshifter (subtlest). Anomalies are inserted at random times into the day's guest stream; cult inserts members across the whole day.

**Design intent per anomaly**: infected = drop-everything co-op moment · spy = quiet economic bleed · shapeshifter = "can you trust your own systems" · aliens = park-management interaction under pressure · cult = tracking patterns *across* guests, not per-guest inspection.

**Counter-item principle (the game's tone rule)**: every anomaly counter is a simple physical item interaction — throw salt, pull the e-stop, swing the net — with instant comedic resolution: anomalies evaporate in a puff, rescued guests give a **thumbs-up and carry on as if nothing happened**. No trauma states, no lingering debuffs on rescued guests, no gore. This is the template for most interactions in the game: it keeps guest state minimal and the tone light. Salt is the signature counter-item.

## 5. Day cycle

`Prep → Gates Open (~12 min) → Closing (~2 min) → Summary`

- **Prep** (untimed): build, repair, hire, buy tools; read the **daily bulletin** — Papers-Please-style rule delta + forecast. Examples: "Serials starting with Z are counterfeit today" · "No VIP passes accepted" · "Infection outbreak reported nearby — expect infected" · "Health inspector visits today."
- **Gates Open**: the game. Guests flow, anomalies embedded.
- **Closing**: gates shut, park drains; unresolved anomalies charge a cleanup cost or carry into tomorrow (shapeshifter persists!).
- **Summary**: two pages, then autosave.
  - **Statistics page**: income/expenses breakdown, admissions, walkaways, anomalies caught/missed, wages, fines (police bribes).
  - **Review page** (Google-reviews style): the park's star rating is the diegetic face of the Satisfaction stat, plus a handful of comical guest reviews *generated from the day's actual events* — "★★★★★ saw a man launch into space", "★☆☆☆☆ waited 40 minutes, wife joined a cult". Reviews are flavor text picked from templates keyed to event log entries; cheap to author, high charm.

Daily rules are the content treadmill: cheap to author (data), refresh the inspection minigame without new systems.

## 6. Staff (and the solo-player bridge)

Staff NPCs are **player substitutes** so 1 player and 6 players play the same game at different quality: Ticket Clerk (mans a stand, worse than a human), Mechanic (repairs condition over time), Security (patrols, auto-engages incidents slowly). Players outperform NPCs at every role; more friends = more roles held to human standard. Wages daily at Summary. Manager clipboard (player tool) inspects staff — the shapeshifter check.

## 7. Economy

**In**: entry fees, food stalls. **Out**: rides/stands/facilities, upgrades, tools/buildings (cameras, infirmary, bathroom locks, capture gear), wages, repairs, cleanup costs.

**Anti-soft-lock floor**: AttractionIdx floor of 50 guarantees trickle income; cash cannot go negative — unpaid wages make staff quit instead; **loan** button: +2000 cash, auto-repay 10%/day. A park can always crawl back.

## 8. Starting position & first week

**Plot-based building**: the park map is a fixed, hand-built level with predefined **snap plots** — ride plots, stall plots, facility plots, and stand slots at the gate. Buying a ride/building means choosing a plot and picking from the catalog; it spawns there. No freeform placement (v0). This keeps the guest navigation graph static (huge pathfinding simplification), makes build UX trivial on all devices, and fits the `.rbxm`-asset level workflow. Freeform placement is a possible post-v0 evolution.

**Day 1 kit** (new save slot):
- 1 gate with 1 built-in ticket stand (player-manned — no clerk yet)
- 1 carousel (BaseAppeal 40), 1 bathroom, 1 path loop connecting them
- Cash: **500** — enough for exactly one meaningful choice on day 1 (food stall ~300 vs. saving toward a second ride ~600)
- No staff, no tools; salt bucket and other tools appear in the shop as their anomalies unlock

**Derived day-1 numbers** (sanity check of the formulas): ParkAppeal ≈ 166 → AttractionIdx ≈ 130 → ~4.5 arrivals/min → **~55 guests** over a 12-min day → at entry fee 10, ~450–550 income. One anomaly slot, drawn from the loud pool. A solo player at one stand (≈8 inspections/min) can comfortably handle 4.5 arrivals/min — early queue pressure is low by design.

**Day 1 is the only guaranteed-safe day**: zero anomalies, low arrivals, bulletin teaches ticket basics. The calm before everything.

**Day 2 onward — anomalies are procedural and random**, never scheduled:
- Daily slots `= 1 + floor(AttractionIdx/250)` is the **maximum**; each slot fills with probability ~0.7. Quiet days happen and can't be predicted — false calm is part of the genre.
- Each filled slot draws a type from the AttractionIdx-unlocked pool (§4 tier gating still applies), spawn time random within the day; cult members trickle in across the whole day.
- **First-appearance hint**: the first time a type is ever drawn in a save, that morning's bulletin carries its themed warning ("outbreak reported nearby" / "keep an eye on ride speeds"). The tutorial rides along with the randomness instead of being scheduled — players get the hint the day the threat actually debuts.

**Non-anomaly teaching is state-triggered, not day-scheduled**: a scripted carousel breakdown on day 2 teaches repair/hiring; the bulletin suggests a clerk/second stand the first day arrivals exceed one stand's comfortable throughput; hunger complaints surface in reviews if no food stall exists by day 3. Ticket-rule days start appearing randomly from day 3 (~40% of days thereafter).

**Seeds**: Satisfaction EMA starts at 0.6; IncidentP at 0. Multiplayer note: onboarding state (first-appearance flags, scripted breakdown) belongs to the *save slot* (host's park), not the player — a veteran joining a friend's fresh park experiences day 1 with them.

## 9. Tool & building catalog

All prices are placeholders scaled to the income curve (§8 sanity check: ~500/day at start, ~2,500–3,500/day near max index). Shop is browsed during **Prep**; new stock is announced by the bulletin ("new in shop!") when its unlock tier is reached — counter-tools always arrive with or slightly before their anomaly.

**Rides** (each upgradeable tier 1→3; upgrade = 50% of base cost, +25% appeal per formula; `speed` attribute drives alien targeting):

| Ride | BaseAppeal | Speed | Cost | Unlock |
|---|---|---|---|---|
| Carousel (starter) | 40 | low | 600 (extra) | start |
| Bumper Cars | 55 | low | 900 | start |
| Ferris Wheel | 70 | low | 1,400 | idx 150 |
| Haunted House | 85 | mid | 2,200 | idx 300 |
| Drop Tower | 100 | high | 3,500 | idx 450 |
| Roller Coaster | 120 | high | 5,000 | idx 600 |

**Facilities**:

| Item | Effect | Cost | Unlock |
|---|---|---|---|
| Snack Cart | Refills Hunger, small revenue | 300 | start (the day-1 choice) |
| Food Court | Faster refill, bigger revenue | 1,200 | idx 250 |
| Bathroom (extra) | Refills Bladder | 400 | start — more bathrooms = shorter guest walks *but more rooms for the cult to pick* |
| Queue Busker | Patience decay ×0.5 in gate radius | 800 | idx 200 |

**Gate infrastructure**:

| Item | Effect | Cost | Unlock |
|---|---|---|---|
| Extra ticket stand (2nd–4th) | Splits the queue; player- or clerk-manned | 750 | start |
| Ticket Scanner (per stand) | Flags suspicious tickets, ~75% accuracy, ~10% false positives — player still decides | 1,500 | idx 250 |
| Heartbeat Arch (per stand) | Reveals bio-tells: two heartbeats (aliens), no heartbeat?… flags infected | 2,500 | idx 300 |

**Handheld tools** — live on **wall racks** in the park (proximity-prompt grab, DOORS-style), not in inventories. Co-op: anyone can grab; solo: running to the rack under pressure *is* the tension:

| Tool | Effect | Cost | Unlock |
|---|---|---|---|
| Capture Net | Generic humanoid-anomaly catch (zombie, spy in the act, exposed aliens, revealed shapeshifter) | 500 | day 2 |
| Salt Bucket | Thrown: cultists evaporate in a puff | 350 | idx 400 (with cult) |
| Manager Clipboard | Inspect a staff member → reveals shapeshifter | 600 | idx 600 (with shapeshifter) |

**Anomaly buildings**:

| Building | Effect | Cost | Unlock |
|---|---|---|---|
| Security Camera | Alert ping when tampering/anomalous behavior occurs in radius | 900 | idx 200 (with spy) |
| Infirmary | Escort a suspicious coughing guest → cured (if infected) or thumbs-up (if not) | 1,800 | day 2 |
| Bathroom Lock | Cult must pick it: +60s ritual delay | 250/bathroom | idx 400 |
| Security Office | Unlocks Security staff hires | 2,000 | idx 300 |

**Staff wages** (paid at Summary; hire instantly from Prep menu): Clerk 100/150/220 per tier (50/65/80% accuracy) · Mechanic 120 · Security 150. No hire fee — wages *are* the cost, so hiring is reversible experimentation.

## 10. Engagement loops (Roblox + game-design perspective)

Four nested loops, each with its own reward beat:

| Loop | Timescale | Beat | Reward |
|---|---|---|---|
| Inspection | ~5–10 s | approve/deny one guest | stamp thunk + coin chime; the money counter ticks up *per admitted guest* |
| Tension wave | ~2–4 min | anomaly spikes → scramble → contained | resolution puff + thumbs-up guests; relief is the reward |
| Day | ~15 min | prep → open → close → summary | stats page + comic reviews + **tomorrow's forecast** |
| Park (meta) | hours–weeks | index tiers unlock rides, tools, threats | new content + park star-rating milestones |

**The gate is the slot machine.** Every guest is a small decision with instant feedback, and random anomalies make it a variable-ratio schedule — the psychologically strongest one. This only works if inspection feedback is *juicy*: physical stamp animation, distinct approve/deny sounds, coins that visibly fly to the counter. Budget real polish time here; this interaction is 60% of play.

**"One more day" hook**: the Summary's last element is tomorrow's bulletin teaser ("health inspector visit · outbreak rumors nearby"). Cliffhanger before the natural stopping point — the single most important retention mechanic, borrowed from every one-more-turn game.

**Losing is content.** A disaster day generates the funniest reviews ("★☆☆☆☆ my husband is a zombie now. no refund??"). Failure produces laughter and a screenshot, not a rage-quit — critical for the young Roblox audience and for organic sharing. Ride launches and zombie waves are deliberately streamable moments.

**Novelty cadence**: index tiers (150/200/250/300/400/450/600) each deliver something — a ride, a tool, or a threat — so a new thing arrives roughly every 1–2 hours of play. Upcoming unlocks show as silhouettes ("at 600: ???") — teasing unknown *threats* drives curiosity better than teasing rewards.

**Co-op is the growth loop**: friends replace wages and hold roles at human quality, so inviting is mechanically rewarded. When queue pressure exceeds staffed capacity, surface a SocialService invite prompt ("Stand 2 is drowning — invite a friend"). Roblox growth is social-graph growth.

**Progression display is diegetic**: the park's Google-review star rating (= index / 200) *is* the progression bar, with named milestones per half-star ("Roadside Attraction" → … → "World Wonder"), each paying a small cash bonus.

**Session shape**: day boundary = autosave = guilt-free exit; target session 1–3 days (15–45 min), mobile-friendly. Time-to-first-inspection on a new save: under 60 seconds.

**Deliberate non-patterns** (things we will NOT do): no offline/appointment timers — the park only runs while played, so there's no FOMO pressure; no paid detection or anomaly-power — monetization (later) is cosmetic only. Compulsion comes from the loop, not from dark patterns.

## 11. Open questions

- Player-set entry price vs. fixed (v0: fixed).
- Tool/building catalog beyond: cameras, infirmary, salt bucket, capture net, manager clipboard.
- Weather / special-event days layered on the daily bulletin.
- Whether unresolved shapeshifters carrying across days is fun or frustrating — playtest.
- Review-template catalog size for launch (~30–50 templates keyed to event types?).
- Post-v0: freeform building; cult ritual escalation beyond disappearances.
