# Place files

- `park.rbxl` — the park place. Open in Studio, then run `rojo serve game/default.project.json` and connect the Rojo plugin to sync code.
- `park-bootstrap.project.json` — one-time generator for the place shell (baseplate + spawn + current code). Regenerate with:

  ```
  rojo build places/park-bootstrap.project.json -o places/park.rbxl
  ```

Day-to-day code sync always goes through `game/default.project.json` (code only — map geometry is built in Studio and saved into the place / committed as `.rbxm`, never synced through Rojo).
