---
name: server-architecture
description: Server architecture decisions for Crazy Little Worm (Roblox amusement-park anomaly game). Load whenever designing or implementing networking, save/load, rooms/matchmaking, DataStores/MemoryStore, or client-server state flow.
---

# Server Architecture — Crazy Little Worm

Locked-in architecture decisions. Follow these unless the user explicitly changes them.

## Ownership split — pure Roblox, no external backend

**Storage lifetime must match data lifetime:**

- **Durable player state** (must outlive servers by years): saves, items, economy, park layout, stats → DataStores via **ProfileStore**.
- **Ephemeral matchmaking state** (must die with its server): room listings, join codes, server-identity mapping → **MemoryStore** with TTL. Volatility is a feature here — expiring entries are the ghost-room cleanup.
- **Friend invites**: native **SocialService** prompts. No custom invite persistence in v1.

There is **no Express/Postgres backend in v1**. It stays a future option behind `RoomService` only if a web presence is ever needed (web dashboard, Discord integration, invites to offline players persisted for days). Never put game saves in any external backend regardless.

## Places & rooms

- Two places in one experience: **Lobby** and **Park**. Max players: **6** (co-op friend group).
- Nothing outside a game server can join a player to a server. Flow is always in-game:
  1. Host picks a save slot in the lobby → lobby server calls `TeleportService:ReserveServer(parkPlaceId)`.
  2. Lobby server writes to MemoryStore: a room entry in a **SortedMap `rooms`** (join code, room name, privacy, player count; TTL ~60s) and a map entry **`PrivateServerId → { hostUserId, slot, accessCode }`**.
  3. Other players browse rooms via in-game UI reading the SortedMap; joining resolves the access code server-side and teleports them. Friends-only rooms are filtered server-side.
  4. On boot, the park server reads MemoryStore by its own `game.PrivateServerId` to learn `(hostUserId, slot)` and loads that profile. **Never pass slot/host via TeleportData** — it is spoofable via `GetJoinData`.
  5. The park server **heartbeats** its room entry every ~30s (refreshing TTL + player count). A crashed server stops refreshing → entry expires → browser cleans itself.
- All game code talks to a thin **`RoomService`** Luau abstraction (MemoryStore implementation) so the rooms backend could be swapped without touching gameplay code.
- MemoryStore is server-side only; clients never read/write it. Never trust a client-supplied userId — the server knows who's asking. All MemoryStore calls follow the same `pcall` + retry + backoff rule as DataStores.

## Saves

- Up to **3 save slots per player**. One DataStore `"PlayerSaves"`, key = `{userId}_slot{N}`.
- A save slot = a **park owned by the host**. Friends joining a room play in the host's park; park progress (rides, economy, upgrades) belongs to the host's slot. Visitors' personal stats save to their own profile. No co-owned parks (v1).
- Save value: one versioned table per slot:
  ```lua
  {
    version = 1,
    economy = { cash = 0, income = 0 },
    rides = { ... },   -- id, tier, position
    staff = { ... },
    stats = { daysCompleted = 0, breaches = 0 },
  }
  ```
- Use **ProfileStore** (session locking, retries, autosave, BindToClose, reconciliation). Never raw `SetAsync` for saves; raw DataStore API only for OrderedDataStores (leaderboards) and `ListVersionsAsync` (support/restore tooling).
- Load the host's profile once at park-server boot (during teleport transit). Mutate in memory during play. Autosave ~1–2 min + on player leave + `game:BindToClose()`. Never save per-action. Only the server touches data.

## Networking: optimistic, non-blocking

- **No loading waits during gameplay.** Client → Roblox server uses optimistic UI:
  - Single authoritative state store on the server, replicated to clients (Reflex/Rodux-style or ReplicaService-type).
  - Client renders server state + pending optimistic patches tagged with a **request id**. Server confirmation drops the patch into confirmed state; rejection drops it and the UI rolls back.
  - RemoteEvents with async acks — never blocking `RemoteFunction:InvokeServer()` in gameplay paths.
- Optimistic UI ≠ client authority. Server validates every action (funds, placement bounds, cooldowns, permissions); exploiters fire remotes directly.
- Shared 6-player economy means concurrent spends can conflict: server resolves in arrival order, loser rolls back. Rejection UX (ghost dissolves, toast) is a designed state, not an error. Rare heavy actions (big purchases) may show a short pending state instead of full optimism.
- Roblox server → DataStore/MemoryStore is background-only: gameplay code never yields on them. Batch and rate-limit: boot lookup, room-state changes, slow heartbeat — never per-action.
- All DataStore/MemoryStore calls wrapped in `pcall` with retry + backoff.

## Loss design (affects save shape)

**No permadeath.** Gameplay never wipes a save slot; failure = recoverable setbacks (lost income, damaged rides, attraction/reputation hits, staff losses) written into the slot's persistent state. Implementation notes:

- All loss consequences are server-side decisions (evaluated on the park server), never client-triggerable.
- The save shape must support an **anti-soft-lock floor**: a park can always recover (minimum income / bailout mechanism), so no economy state may be unrecoverable.
- Anomaly truth is server-only state: **never replicate "is anomaly" flags to clients** before a legitimate reveal — only cosmetic tell data goes over the wire, or exploiters get free detection.
- DataStore versioning (30 days) covers corrupted-save recovery for support cases.
