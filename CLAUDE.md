# Crazy Little Worm

Roblox amusement-park management game crossed with anomaly-game mechanics. Players run a park co-op (max 6 per server): check guest tickets Papers-Please-style to spot anomalies, build/upgrade rides, hire staff, and survive shifts.

## Status

Greenfield — architecture decided, nothing scaffolded yet. No git repo initialized yet.

## Design pillars

- **Three interlocking systems**:
  - **Ticket management** — the core accumulation/progression gameplay and the anomaly filter. Balance gate throughput (queue anger, extra entry stands) against how many anomalies slip in. Detection upgrades (scanners, tools) make spotting easier.
  - **Park management** — as documented (build, upgrade, hire). Directly driven by what the gate admits: more guests = more revenue and more work. Feeds the attraction index, which drives guest inflow.
  - **Anomaly management** — handling anomalies inside the park; affected by park state but mostly by gate filtering quality. Players buy tools and buildings to detect/contain them.
  - The **attraction index** is the coupling variable: park quality → guest inflow → queue pressure at the gate → admissions → revenue + infiltration → incidents → back into park quality.
- **No permadeath**: failure is a bad day — lost income, damaged rides, reputation/attraction hits, staff losses. The park always persists. Design must include an anti-soft-lock floor so a park can never death-spiral into unplayability.
- **6-player co-op** friend groups; natural role-splitting (ticket booth, park ops, anomaly response).
- **Saves**: 3 slots per player; a slot = a park owned by the host. Friends play in the host's park; their personal stats save to their own profile.

Full system designs and formulas (guest AI, attraction index, gate rules, the five anomalies, day cycle, economy, tool/building catalog, engagement loops): [docs/game-design.md](docs/game-design.md).

## Tech stack

- **Game**: Luau, Rojo (code-only sync), ProfileStore for saves.
- **No external backend.** Pure Roblox: DataStores (durable: saves, stats) + MemoryStore (ephemeral: rooms/server browser) + SocialService (friend invites). An Express backend remains a future option behind `RoomService` only if a web presence is ever needed.
- **Toolchain (planned)**: Rokit (tool versions), Wally (packages), StyLua + Selene (format/lint), Luau LSP, GitHub Actions CI.

## Architecture

Full decisions live in the `server-architecture` skill (`.claude/skills/server-architecture/SKILL.md`) — load it for any networking, save/load, rooms, backend, or state-flow work. Summary:

- Storage lifetime matches data lifetime: DataStores via ProfileStore for durable player state; MemoryStore for ephemeral matchmaking state (rooms die with their server via TTL).
- Lobby place + Park place. Rooms via `ReserveServer` → MemoryStore (room listing + `PrivateServerId → {hostUserId, slot}` map); park server identifies itself by `game.PrivateServerId` (never TeleportData — spoofable). Rooms code behind a swappable `RoomService` abstraction.
- Optimistic non-blocking networking: authoritative replicated server store, client-side pending patches with request-id acks and rollback; server validates everything. No gameplay code ever yields on HttpService/DataStore.

## Art direction

Locked: **chunky toybox forms, articulated limbs, baked vertex-colour AO, no textures** — one material for the whole game, cheerful sunny park, horror only from the anomalies. Full spec, palette, budgets and rationale: [docs/art-direction.md](docs/art-direction.md).

Two rules that are gameplay constraints rather than taste, and must not be "fixed" for realism:
- **Guest heads stay ≥1.6 studs.** The head is the display surface for the Infected skin tell.
- **Never desaturate the palette.** Tell contrast is the core loop; realism directly attacks it.

Blender sources live in `art/blender/`. The style comparison scene is fully procedural — `style_probe.py` regenerates `style-probe.blend` from a table of constants; renders in `art/blender/renders/`.

## Level / content workflow

- Rojo fully manages **code only** (`src/`). Levels and ride models are built in Studio and committed as `.rbxm` files — never sync map geometry through the Rojo tree.
- Every ride/booth/attraction is a data-driven component: CollectionService tag + Attributes (cost, capacity, tier, anomaly hooks). One component system binds behavior to tagged models at runtime, so builders drop a model, tag it, set attributes — no per-ride scripting.

## Planned repo layout

```
game/                  # Rojo project
  default.project.json
  src/server|client|shared
  assets/              # .rbxm ride/level models
art/blender/           # .blend sources + procedural generators + renders
places/                # lobby.rbxl, park.rbxl
```

## Workflow

Task tracking lives in [BOARD.md](BOARD.md) (kanban) — view it as a board with `node tools/board-viewer/serve.mjs` (VS Code task: *Board: viewer (live)*); see [tools/board-viewer/README.md](tools/board-viewer/README.md). Rules that bind Claude sessions too: pull from Ready right-to-left, WIP ≤ 2, every feature card carries `code:` and `assets:` lines, and every feature follows the board's grey-box-first feature flow (code never waits for final art; assets bind via tag + attributes so art swaps are zero-code). Move cards as work starts/finishes and keep acceptance criteria honest.

## Build order

1. Rojo + toolchain skeleton, empty park place, git init.
2. Ticket-check / anomaly prototype (core loop).
3. Tycoon layer with tagged-component rides.
4. Rooms/browser last — MemoryStore behind `RoomService`.

## Conventions

- Server-authoritative everything; clients never touch data or make trust decisions.
- All DataStore/MemoryStore calls: `pcall` + retry with backoff, batched, background-only.
- Studio API access hits live data — never test against production DataStore keys carelessly.
