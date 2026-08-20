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
*(entire epic pulled as a batch 2026-08-19, Epic P precedent — A-5 split into infiltration + ritual halves during grooming; A-8 resized S→M honestly: it's five components plus a purchase flow. Code complete same day → consolidated checklist in Review)*
- **A-3** (M) Corporate spy · code: `anomalies/Spy`, `anomalies/NetTargets` registry (net targets beyond zombies), `Buildings` camera component, `Building` catalog kind through PlotService/BuildMenu, businessman lookalikes in guest gen · assets: SecurityCamera grey-box `.model.json`; suit + briefcase as code-attached grey-box parts · ✔ spy enters with briefcase + wrong-date ticket while innocent businessmen also exist; each tamper drops a ride's condition 40% (breakdown under 30%, severity 6); a camera in radius pings and reveals the tamper; the net catches a spy in the act
- **A-4** (M) Aliens in a coat · code: `anomalies/Aliens`, wobble walk, e-stop prompt per ride, overclock + launch sequence, plot freed on ride destruction · assets: e-stop panel + launch effects as code-side grey-box · ✔ a double-height wobbling guest holds a Child ticket; inside, it targets the fastest ride and overclocks it for 60s with a visible ramp; e-stop resets the ride and exposes the alien (nettable); unchecked, the ride launches into space — destroyed, Fear spike, severity 12, plot reusable
- **A-5a** (M) The cult — infiltration (split from A-5 L) · code: `anomalies/Cult` member gen + across-the-day trickle, consecutive-serial same-date tickets · assets: amulet grey-box part · ✔ on a cult day, 4–6 members trickle in spread across the whole day wearing matching amulets and carrying consecutive serials; individually harmless inside
- **A-5b** (M) The cult — ritual + salt (split from A-5 L) · code: bathroom convergence at ≥4 admitted, kidnap occupants, 180s ritual channel (+60s locked bathroom), plume, disappearances + police-bribe fine at Summary, salt counter, tool-rack generalization (buy-once racks) · assets: SaltBucket `.model.json`; candles + plume as code-side effects · ✔ at 4 admitted cultists they converge on a bathroom, kidnap its occupants, and channel under a plume visible from outside; salting them below 4 aborts the ritual and rescued guests thumbs-up and carry on; a completed ritual disappears the kidnapped — 200 police-bribe fine each on the Summary stats page
- **A-6** (M) Shapeshifter · code: `anomalies/Shapeshifter`, staff person-names + nameplates + idle-bob tell, mimic behaviors (clerk floodgate approves everyone, mechanic never repairs), clipboard inspect · assets: Clipboard `.model.json` · ✔ its ticket Name matches a rostered staff member; 120s after admission it replaces an isolated staff NPC; the mimic never does its idle bob; clipboard inspect reveals it (severity 10, staff lost, nettable) or gives real staff a thumbs-up
- **A-7** (S) Ticket-rule days · code: `TicketRules` roll from day 3 (~40% of days), violator ticket gen, clerk validity check, counterfeit fines at Summary, bulletin rule line · assets: none · ✔ on a rule day the bulletin announces the rule, violating tickets appear in the guest stream, and every admitted violator lands a fine line on the Summary stats page
- **A-8** (M) Remaining tools/buildings · code: gate-upgrade purchase flow (Ticket Scanner + Heartbeat Arch per stand, Bathroom Lock per bathroom), Infirmary + Queue Busker buildings, infirmary escort prompt, buy-once tool racks · assets: Infirmary + QueueBusker grey-box `.model.json`; scanner/arch/padlock as code-side parts · ✔ scanner flags suspicion (~75% accuracy, ~10% false positives) and arch reads heartbeats on the inspection card — player still decides; infirmary escort cures a dormant infected (thumbs-up otherwise); a locked bathroom delays the ritual; busker halves patience decay in its radius

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
- **Q-8** (M) Ride tier upgrades · code: upgrade flow in PlotService + BuildMenu (§9: tier 1→3, upgrade = 50% of base cost, +25% appeal per tier — IndexStore already reads the Tier attr) · assets: per-tier grey-box accent (e.g. topper color) · ✔ upgrading a built ride visibly raises its appeal and the attraction index
- **Q-9** (M) Inspection refinement pass · from G-9 finding: ticket loop is playable but needs texture to carry the game — revisit AFTER A-7 rule days + subtler anomalies exist · code: TBD from a focused playtest (candidate knobs: ticket field variety, inspection tools UX, stamp pacing) · assets: TBD · ✔ playtest verdict flips to "inspection carries the game"

---

## 🔜 Ready (max ~5 cards; criteria + code/assets lines required)

*(empty — Epic A pulled as a batch)*

---

## 🔨 In Progress (WIP ≤ 2 per person)

*(empty — pull from Ready)*

---

## 👀 Review

- **Epic A batch** (A-1, A-2, A-3, A-4, A-5a, A-5b, A-6, A-7, A-8) — code complete 2026-08-19, per-card commits `b325781…d21c13c` (+ debug index-boost knob). Card details in the Backlog Epic A section. Groomed A-1/A-2 absorbed from Ready:
  - *Review fix 2026-08-20* (report: "can't buy anything from the tool rack"): the net rack is day-2-gated and locked racks rendered no prompt, so day 1 looked broken. Design call after a visible-🔒-label detour (`1c75039`): **rack prompts appear only once their tool is unlocked** — locked racks stay invisible, the bulletin/shop tiers do the teasing; a failed buy flashes "Need $N!" on the visible prompt. Retest under checklist item 11 (note: net rack shows nothing until day 2 — intended).
  - **A-1** (M) Anomaly scheduler · ✔ debug readout shows rolled slots/types each day; only unlocked types ever spawn
  - **A-2** (S) Daily bulletin + first-appearance hints · ✔ the morning an anomaly type debuts, its themed warning appears in the bulletin

  **Studio setup first (map edits in `places/park.rbxl`, one-time):**
  - Add two rack parts tagged `ToolRack` with attribute `Tool = "SaltBucket"` and `Tool = "Clipboard"` (the existing rack defaults to `CaptureNet`). Racks are now buy-once: first grab pays (§9 prices), then free grabs — retest the net rack accordingly.
  - Optional but recommended: a few pads tagged `Plot` with `PlotKind = "Building"` near rides (cameras need coverage); Building items also accept free Facility pads.

  **Consolidated Studio test checklist** (debug panel: day speed ×20, "Index boost cycle 📈" reaches idx-gated unlocks; every anomaly has a spawn button so scheduler gating never blocks a test):
  1. **A-1 scheduler** — day 1 plan reads "safe" in the debug panel; from day 2 the plan line shows slots/types with times; with boost 0 only Infected/Aliens are ever drawn; cycle boost to +400/+600 across a few days and see spy/cult/shapeshifter enter the pool (shapeshifter only once staff exist). Quiet days (empty slots) happen.
  2. **A-2 bulletin** — the Worm Daily auto-opens each Prep with a turnout forecast; the morning a type is first drawn, its themed warning appears (and never appears again after); 📰 button reopens it.
  3. **A-7 rule day** — "Force rule day 📜" during Prep: the bulletin gains a TODAY'S RULE line; violating tickets appear in the stream (~15%); approving violators puts a fines line on the Summary stats page; a clerk denies some violators too.
  4. **A-3 spy** — "Spawn spy 🕵️": suit + briefcase, ticket date is wrong; innocent suits with briefcases also exist (~7% of adults — deny-all-suits must feel wrong). Admitted, it walks to the best ride and sparks for 15s → condition −40 (watch ride attributes / a second tamper breaks it, index dips). With a camera covering the ride: ❗ ping + red highlight — net it mid-tamper. It leaves after 3 rides if unbothered.
  5. **A-4 aliens** — "Spawn aliens 👽": double-height wobbler, Child ticket (arch reads ♥♥ if bought). Admitted, it heads to the fastest ride; hum/shake/particles ramp for 60s; e-stop prompt on the ride resets it and drops the coat (green, nettable, flees). Let one finish once: liftoff, ride destroyed, plot frees for rebuild next Prep, guests scatter, index takes −12.
  6. **A-8 sensors** — with boost: buy Ticket Scanner and Heartbeat Arch from the Build menu Upgrades rows (Prep) → suspicion strip / heartbeat line on the inspection card, including occasional false positives on honest guests (player still decides).
  7. **A-8 infirmary + busker + lock** — build Infirmary: escort prompt on admitted guests; escorting a dormant cougher cures (Cured stat), a healthy guest gets a thumbs-up. Queue Busker near the gate: sap patience and compare emote decay rates inside/outside its radius. Bathroom Lock: padlock visual + Locked attr.
  8. **A-5a cult** — "Spawn cultists 🕯": amulets on chests, consecutive same-letter serials on the same date, otherwise ordinary guests.
  9. **A-5b ritual** — admit 4: they converge on a bathroom, candles + purple plume visible across the park, occupants kidnapped (😱). Salt (buy at idx 400 boost) one cultist below 4 → ritual collapses, rescued thumbs-up and resume. Run it again and let it complete (180s; locked bathroom +60s): kidnapped vanish, Summary shows 200/guest police bribe + a cult review.
  10. **A-6 shapeshifter** — hire a clerk + mechanic: person names on nameplates and in the Staff menu roster; idle staff visibly bob. "Spawn shapeshifter 🎭": ticket Name matches a rostered staffer. Admit and walk far away: after ~120s a shimmer — the mimic never bobs, the clerk-mimic approves EVERYONE (watch anomalies pour in), the mechanic-mimic ignores a breakdown. Clipboard (idx 600 boost) on real staff → ✓; on the mimic → reveal: severity 10, staff line gone from roster, grey imposter sprints for the exit — nettable.
  11. **Regression** — infected loop still works end-to-end (tells, incubation, cascade, net, infirmary cure); capture net now costs $500 once (day 2+) then free grabs; Summary numbers still reconcile (entry + food − wages − loan − fines = net); 2-player co-op check deferred to next co-op session; CI green.

---

---

## ✅ Done

**🏁 M2 Park sim complete (2026-08-18) — current milestone: M3 Full anomaly set**

- **Epic P batch** (P-1…P-9) · ✔ Studio-tested 2026-08-18 via consolidated 9-point checklist: plots/build, ride cycles, facilities, needs AI, live index driving arrivals, day-2 breakdown + mechanic, clerk, summary v1 with reviews, loan/staff-quit floor (after WorldPivot placement fix)

**🏁 M1 Playable gate loop complete (2026-08-18)**

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
