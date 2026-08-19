# Crazy Little Worm — Kanban Board

## Board rules (the good practices — read before touching cards)

1. **Pull, don't push.** Work is *pulled* into In Progress when you have capacity, never assigned ahead of time. Finish before starting: when free, look right-to-left — first help finish Review, then In Progress, only then pull from Ready.
2. **WIP limit: 2 per person** (including Claude sessions). Hitting the limit means finish something, not widen the limit.
3. **Cards are vertical slices**, sized to fit one working session (S ≤ 2h, M ≤ half day, L = must be split before entering Ready). A card delivers something observable in Studio, not "a system's internals."
4. **Card format** — every feature card carries its full bill of materials:
   `**ID** (size) Title · code: <modules touched> · assets: <models/anims/sfx needed> · ✔ acceptance criteria`
5. **Column entry policies**:
   - **Ready**: acceptance criteria written, code+assets lines filled, no unresolved dependency, sized S or M.
   - **In Progress**: actively worked *today*.
   - **Review**: code complete; needs Studio testing (solo + 2-player where relevant) or a design look-over.
   - **Done**: meets the Definition of Done.
6. **Definition of Done**: runs in Studio without errors · StyLua-formatted, Selene-clean · committed (code in `src/`, assets as `.rbxm` in `game/assets/`, Blender sources in `art/blender/`) · card's acceptance criteria demonstrably met · doesn't break anything already Done.
7. **Blocked cards stay in place** with a `⛔ blocked: <reason>` note — blockers must be loud, not parked in a column.
8. **Backlog is ordered** (top = next) and grouped by epic. Groom on milestone completion; split L cards before they reach Ready.
9. **One milestone at a time.** Cards enter Ready only from the active milestone. Current: **M0 Foundation → M1 Playable gate loop**.

## Feature flow — every feature card moves through these stages

```
Spec ──► Grey-box assets ──► Code ──► Wire-up ──► Studio test ──► (final art, later)
```

1. **Spec** — the card cites its design-doc section; numbers and tells come from [docs/game-design.md](docs/game-design.md), never invented at the keyboard.
2. **Grey-box assets** — placeholder model with the *correct tag + Attributes*, committed as `.rbxm`. **Code never waits for final art.**
3. **Code** — Luau in `src/`; behavior binds to the asset via CollectionService tag (component system, F-4). Server-authoritative per the `server-architecture` skill.
4. **Wire-up** — tag + attributes set on the asset; the component binds; feature works end-to-end with grey-box visuals.
5. **Studio test** — acceptance criteria checked solo (+ 2-player if co-op-relevant) → card to Review.
6. **Final art** — Blender/Studio art replaces the grey-box `.rbxm`. Same tag + attributes ⇒ **zero code change**. Final art is its own card and may lag several features behind; the game must always be fully playable grey-box.

The component system is what makes stage 6 free — that's why F-4 is in the first milestone.

**Debuggability rule (F-5):** every card that adds tunable or stateful behavior also wires its knobs into the Debug panel as part of Wire-up — a dispatch entry in `DebugService` (server) + a button/readout in `DebugPanel` (client). Testing a feature must never require command-bar incantations.

---

## 📋 Backlog

### Epic F — Foundation (M0)

### Epic G — Gate loop (M1) — spec: design doc §1, §3, §4 (infected)

### Epic P — Park sim (M2) — spec: §1, §2, §5, §6, §9
*(entire epic pulled as a batch 2026-08-18 at Benjamin's request — P-1 split into needs-decay/decisions + exit-happiness halves, delivered inside the batch)*

### Epic A — Full anomaly set (M3) — spec: §4, §5, §9
- **A-1** (M) Anomaly scheduler · code: daily slots by index, 0.7 fill roll, pool gating, random spawn times · assets: none
- **A-2** (S) Daily bulletin + first-appearance hints · code: bulletin UI in Prep, hint flags on save · assets: newspaper-style bulletin UI art
- **A-3** (M) Corporate spy · code: tamper-target AI, camera alert building component · assets: briefcase + suit variants (innocent lookalikes too!), camera model, tamper anim
- **A-4** (M) Aliens in a coat · code: ride overclock, e-stop panel interact, launch sequence · assets: trench-coat wobble rig (double height), e-stop panel, launch particles + sky sequence
- **A-5** (L→split) The cult · code: serial-sequence ticket gen, trickle scheduler, bathroom convergence, ritual channel + kidnap, salt counter, police-bribe fine at Summary · assets: amulet accessory, candle set, bathroom plume particle, salt bucket + throw anim
- **A-6** (M) Shapeshifter · code: staff replacement, do-nothing mimic behaviors (clerk floodgate!), clipboard inspect · assets: idle-stance tell anim, clipboard model + inspect UI
- **A-7** (S) Ticket-rule days · code: rule generator, validity checker, bulletin announcement · assets: none
- **A-8** (S) Remaining tools/buildings · code: component each · assets: scanner, heartbeat arch, infirmary, bathroom lock, queue busker grey-boxes

### Epic S — Persistence (M4) — spec: server-architecture skill
- **S-1** (M) ProfileStore integration · code: save shape v1, load at boot, autosave, BindToClose · assets: none
- **S-2** (S) 3-slot layout + metadata (park name, day, index, last played) · code only
- **S-3** (M) Park state serialization: plots → save → rebuild on load · code only
- **S-4** (S) Per-player personal stats profile (visitors save to own profile) · code only

### Epic R — Co-op rooms (M5) — spec: server-architecture skill
- **R-1** (M) Lobby place + slot picker UI · code: slot UI, slot metadata read · assets: lobby blockout
- **R-2** (M) RoomService (MemoryStore): create/list/heartbeat/resolve, TTL · code only
- **R-3** (M) Park boot identity: PrivateServerId lookup → load host slot · code only
- **R-4** (S) Server browser UI + join flow · code: browser UI · assets: browser UI art
- **R-5** (S) SocialService invites + friends-only flag · code only

### Epic Q — Polish & retention (M6) — spec: §10
- **Q-1** (S) Tomorrow-forecast cliffhanger on Summary · code only
- **Q-2** (S) Star-rating milestones, named ranks, cash bonuses · code only
- **Q-3** (S) Unlock silhouettes ("at 600: ???") · code: shop UI addition · assets: silhouette icons
- **Q-4** (M) Mobile UI pass: inspection card, build menu, tool grab · code only
- **Q-5** (S) Invite prompt when queue exceeds staffed capacity · code only
- **Q-6** (M) Review template catalog to ~40 entries · writing only
- **Q-7** (M) Sound & music pass · assets: park ambience loop, per-anomaly stingers, ritual drone

---

## 🔜 Ready (max ~5 cards; criteria + code/assets lines required)

*(empty — groom from Backlog)*

---

## 🔨 In Progress (WIP ≤ 2 per person)

*(empty — pull from Ready)*

---

## 👀 Review

**Epic P batch (all M2 feature cards) — consolidated Studio test, ~20 min with debug speed:**

1. **P-2 plots/build**: Prep → Build menu → carousel + bathroom pre-built; buy a Snack Cart ($300) on a facility plot, cash drops; Bumper Cars needs $900 (loan if short); locked rides show 🔒 idx
2. **P-3 rides**: Open gates (×5 speed), approve guests — they walk to rides, board seats, ride runs, they leave and pick a new target
3. **P-4 facilities**: guests visit snack cart (cash ticks +$5) and bathroom
4. **P-1 needs**: guests alternate rides/food/bathroom on their own; during an outbreak, guests near zombies flee to the exit (scared exits in summary satisfaction)
5. **P-5 index**: debug panel `index` rises as you build (idx 130 → ~200+ with bumper cars); arrivals/min visibly increases
6. **P-6 breakdowns**: on day 2 the carousel breaks (sparks) shortly after opening; hire a Mechanic (Staff menu) → orange NPC walks over, repairs, sparks stop
7. **P-7 clerk**: hire Clerk T1, walk away from the stand — clerk processes the queue alone (~6/min); walk close — clerk defers to you
8. **P-8 summary**: Summary shows stars + stats breakdown (entry/food/wages/loan/net) + Reviews tab with event-matched reviews
9. **P-9 floor**: spend to near zero, end day with staff — unpayable staff quits; Take Loan button (+$2000) appears in Prep, repays 10%/day; index never below 50

---

---

## ✅ Done

**🏁 M1 Playable gate loop complete (2026-08-18) — current milestone: M2 Park sim**

- **G-9** (M) **Fun-check playtest** · ✔ 3 days played, verdict **GO** (game-design.md §11); outbreak-at-real-speed retest confirmed after dwell fix

**🏁 M0 Foundation complete (2026-08-18)**

- **G-7** (S) Capture net + tool rack · ✔ Studio-tested 2026-08-18: solo containment of a 3-zombie outbreak; puff + thumbs-up resolution
- **G-6** (M) Infected end-to-end · ✔ Studio-tested 2026-08-18: tells at gate, incubation, chase + tag cascade past 3 zombies
- **G-8** (S) Economy v0 · ✔ Studio-tested 2026-08-18: $500 start, +$10 per approve, deny pays nothing
- **G-3** (S) Inspection juice · ✔ Studio-tested 2026-08-18: stamp/slide/SFX/coin-fly loop feels good at speed
- **G-4** (M) Queue patience · ✔ Studio-tested 2026-08-18: queue + counter decay, emotes at thresholds, walkaways drain an unmanned stand (after counter-guest fix)
- **G-2** (M) Ticket inspection UI · ✔ Studio-tested 2026-08-18: instant optimistic decisions, authoritative server log, close-button fix verified; 2-player check deferred to next co-op session
- **F-5** (M) Debug panel · ✔ Studio-tested 2026-08-18: speed/skip/spawn/drain + live stats all working from the panel
- **G-5** (M) Day cycle skeleton · ✔ Studio-tested 2026-08-18: full Prep → Open → Closing → Summary → Day 2 loop; arrivals only while Open; park drains at Summary
- **G-1** (M) Guest stream generator · ✔ Studio-tested 2026-08-18: guests spawn at day-1 rate, queue at the stand, overflow counts abstractly (after CFrame-vs-Position asset fix)
- **F-4** (M) Tagged-component system · ✔ Studio-tested 2026-08-18: TestRide logged attributes on spawn + detach on despawn
- **F-3** (S) CI pipeline · ✔ verified 2026-08-18: green run on main; deliberately bad push got a red X (scratch branch, since deleted)
- **F-2** (M) Toolchain skeleton · ✔ Studio-tested 2026-08-18: `rojo serve` synced into `park.rbxl`, server + client prints in Output
- **F-1** (S) Git init + `.gitignore` + first commit of docs · ✔ `git log` shows docs committed
- **D-1** Game design doc: three systems, formulas, 5 anomalies, day cycle, catalog, engagement loops (docs/game-design.md)
- **D-2** Server architecture: pure DataStore/MemoryStore, rooms flow, optimistic networking (server-architecture skill)
- **D-3** Art direction locked (docs/art-direction.md)
- **D-4** Project docs: CLAUDE.md + this board
