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

---

## 📋 Backlog

### Epic F — Foundation (M0)
- **F-3** (S) CI pipeline · code: GitHub Actions workflow (StyLua check + Selene) · assets: none · ✔ red X on a badly formatted push · ⛔ blocked: no GitHub remote yet (repo is local-only)

### Epic G — Gate loop (M1) — spec: design doc §1, §3, §4 (infected)
- **G-1** (M) Guest stream generator · code: `server/GuestSpawner`, `shared/GuestIdentity` (name/appearance/ticket gen) · assets: grey-box guest rig (chunky proportions, head ≥1.6 studs — art-direction constraint), gate + 1 stand blockout `.rbxm` · ✔ guests visibly queue at one stand
- **G-2** (M) Ticket inspection UI · code: `client/InspectionUI`, `server/GateService`, optimistic ack remote (request-id pattern) · assets: ticket card UI layout (placeholder styling fine) · ✔ decision feels instant; server logs authoritative result
- **G-3** (S) Inspection juice · code: tween/sound hooks in InspectionUI · assets: stamp model + 2 stamp SFX, coin SFX, coin-fly particle · ✔ still satisfying after 20 stamps in a row
- **G-4** (M) Queue patience · code: patience decay + walkaway in GuestSpawner/QueueService · assets: anger emote billboard icons (😐😠🤬) · ✔ an ignored queue visibly drains itself
- **G-5** (M) Day cycle skeleton · code: `server/DayCycle` state machine, Summary UI v0 (income + admissions) · assets: none · ✔ Prep → Open (12 min) → Closing → Summary loops
- **G-6** (M) Infected end-to-end · code: `server/anomalies/AnomalyBase` + `Infected` component (incubation, chase, convert, Fear AoE) · assets: pale/green skin params on guest rig, cough anim, zombie chase anim · ✔ a missed infected visibly cascades to 3+ zombies
- **G-7** (S) Capture net + tool rack · code: `shared/ToolRack`, net tool component · assets: net + wall-rack grey-box, evaporation puff particle, thumbs-up emote · ✔ solo player contains a 3-zombie outbreak
- **G-8** (S) Economy v0 · code: `server/EconomyStore` (replicated), cash HUD · assets: none · ✔ day income = admissions × fee; deny pays nothing
- **G-9** (M) **Fun-check playtest** · code: none · assets: none · ✔ 3 full solo days played; go/no-go findings written into docs/game-design.md

### Epic P — Park sim (M2) — spec: §1, §2, §5, §6, §9
- **P-1** (L→split) Guest needs AI · code: needs decay, urgency decisions, state machine, exit happiness · assets: none (uses guest rig)
- **P-2** (M) Plot system + build menu · code: plot component, catalog data module, build UI · assets: plot marker model, park map blockout with plots `.rbxm`
- **P-3** (M) Rides as components · code: ride base (capacity, ride loop, Fun refill, condition attr) · assets: carousel + bumper cars grey-box with seat parts
- **P-4** (S) Facilities · code: refill components · assets: snack cart + bathroom grey-box
- **P-5** (M) Attraction index live · code: index calc + arrivals formula wired to real park state · assets: none
- **P-6** (M) Breakdowns + Mechanic · code: condition decay, breakdown events, mechanic NPC AI, scripted day-2 breakdown · assets: mechanic uniform variant, wrench, spark particle
- **P-7** (M) Ticket Clerk NPC · code: clerk AI (throughput, accuracy by tier), wages at Summary · assets: clerk uniform variant
- **P-8** (M) Summary v1 · code: statistics page, review page, event-log → review-template picker · assets: review page UI art (Google-reviews pastiche), ~15 seed templates (writing)
- **P-9** (S) Anti-soft-lock floor · code: index clamp, loan button, staff-quit on zero cash · assets: none

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

- **F-4** (M) Tagged-component system · code: `shared/Component.lua` binder (CollectionService attach/detach + Attributes read) · assets: none · ✔ test model tagged `Ride` logs its attributes on spawn/despawn

---

## 🔨 In Progress (WIP ≤ 2 per person)

*(empty — pull from Ready)*

---

## 👀 Review

*(empty)*

---

## ✅ Done

- **F-2** (M) Toolchain skeleton · ✔ Studio-tested 2026-08-18: `rojo serve` synced into `park.rbxl`, server + client prints in Output
- **F-1** (S) Git init + `.gitignore` + first commit of docs · ✔ `git log` shows docs committed
- **D-1** Game design doc: three systems, formulas, 5 anomalies, day cycle, catalog, engagement loops (docs/game-design.md)
- **D-2** Server architecture: pure DataStore/MemoryStore, rooms flow, optimistic networking (server-architecture skill)
- **D-3** Art direction locked (docs/art-direction.md)
- **D-4** Project docs: CLAUDE.md + this board
