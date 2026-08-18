# Board viewer

Read-only kanban view of [BOARD.md](../../BOARD.md), rendered from the markdown itself.
No dependencies, no build step, no state of its own — BOARD.md stays the single source
of truth and the viewer re-reads it on every save.

## Run it

From VS Code: **Ctrl+Shift+P → Tasks: Run Task → `Board: viewer (live)`**, then
**Ctrl+Shift+P → Simple Browser: Show → `http://127.0.0.1:4321`** to keep the board in
an editor tab beside the code.

From a terminal:

```bash
node tools/board-viewer/serve.mjs            # http://127.0.0.1:4321
node tools/board-viewer/serve.mjs --open     # …and open the default browser
node tools/board-viewer/serve.mjs --port 5000 --board BOARD.md
```

## What it shows

- **Five columns** — Backlog / Ready / In Progress / Review / Done, with per-column counts.
  Backlog and Done group by epic.
- **WIP limit** — the In Progress column reads the `WIP ≤ n` from the board heading and
  turns red when the count exceeds it.
- **Epic progress** — done/total per epic. Click an epic to filter the board to it.
- **Card details** — size, `code:`, `assets:` and `✔` acceptance criteria, expanded by
  clicking a card (or `d` for all of them). `⛔ blocked:` notes render as a red banner and
  an `L→split` size badge is flagged red, per the board's own rules.
- **Source links** — each expanded card links to its exact line in BOARD.md via a
  `vscode://` URL.
- **Unparsed bullets** — any list item inside a column that doesn't match the card format
  is listed above the board rather than silently dropped.

Filter with `/`, toggle details with `d`, clear filters with `Esc`.

## How it parses

[parse.mjs](parse.mjs) implements the card contract from BOARD.md rule 4:

```
- **ID** (size) Title · code: <modules> · assets: <models> · ✔ criteria
```

Columns come from the `##` headings, epics from `### Epic X — Name (Mn) — spec: …`.
Change that format in BOARD.md and the parser follows it — or shows the line as unparsed.

Epic colors use the fixed 8-slot categorical palette (validated for colorblind separation
in both light and dark); every colored element also carries its epic letter, so color is
never the only channel.
