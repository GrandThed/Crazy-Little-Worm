#!/usr/bin/env node
// Local kanban view of BOARD.md. Zero dependencies, read-only.
//
//   node tools/board-viewer/serve.mjs [--port 4321] [--open] [--board <path>]
//
// Serves the viewer at http://127.0.0.1:<port> and pushes a reload over SSE
// whenever BOARD.md changes on disk, so the board updates as you edit it.

import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { watch } from "node:fs";
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseBoard } from "./parse.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..", "..");

const argv = process.argv.slice(2);
const flag = (name, fallback = null) => {
  const i = argv.indexOf(name);
  return i === -1 ? fallback : argv[i + 1];
};

const port = Number(flag("--port", process.env.BOARD_PORT ?? 4321));
const boardPath = path.resolve(repoRoot, flag("--board", "BOARD.md"));
const shouldOpen = argv.includes("--open");

const clients = new Set();

async function boardJson() {
  const markdown = await readFile(boardPath, "utf8");
  const board = parseBoard(markdown);
  board.source = { path: boardPath, relative: path.relative(repoRoot, boardPath).replaceAll("\\", "/") };
  board.readAt = new Date().toISOString();
  return board;
}

const send = (res, status, type, body) => {
  res.writeHead(status, { "content-type": type, "cache-control": "no-store" });
  res.end(body);
};

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  try {
    if (url.pathname === "/" || url.pathname === "/index.html") {
      return send(res, 200, "text/html; charset=utf-8", await readFile(path.join(here, "index.html")));
    }
    if (url.pathname === "/api/board") {
      return send(res, 200, "application/json; charset=utf-8", JSON.stringify(await boardJson()));
    }
    if (url.pathname === "/api/events") {
      res.writeHead(200, {
        "content-type": "text/event-stream",
        "cache-control": "no-store",
        connection: "keep-alive",
      });
      res.write("retry: 1000\n\n");
      clients.add(res);
      const ping = setInterval(() => res.write(": ping\n\n"), 25000);
      req.on("close", () => {
        clearInterval(ping);
        clients.delete(res);
      });
      return;
    }
    return send(res, 404, "text/plain; charset=utf-8", "not found");
  } catch (err) {
    return send(res, 500, "text/plain; charset=utf-8", String(err?.stack ?? err));
  }
});

// Watch the containing directory, not the file: editors replace BOARD.md on
// save (write-to-temp + rename), which kills a single-file watcher on Windows.
let debounce = null;
watch(path.dirname(boardPath), (_event, filename) => {
  if (filename && path.basename(filename) !== path.basename(boardPath)) return;
  clearTimeout(debounce);
  debounce = setTimeout(() => {
    for (const res of clients) res.write(`event: board\ndata: ${Date.now()}\n\n`);
  }, 120);
});

server.listen(port, "127.0.0.1", () => {
  const url = `http://127.0.0.1:${port}`;
  console.log(`Board viewer  ${url}`);
  console.log(`Watching      ${path.relative(repoRoot, boardPath).replaceAll("\\", "/")}`);
  console.log(`In VS Code:   Ctrl+Shift+P → "Simple Browser: Show" → ${url}`);
  if (shouldOpen) {
    const cmd = process.platform === "win32" ? ["cmd", ["/c", "start", "", url]]
      : process.platform === "darwin" ? ["open", [url]]
      : ["xdg-open", [url]];
    spawn(cmd[0], cmd[1], { stdio: "ignore", detached: true }).unref();
  }
});

server.on("error", (err) => {
  if (err.code === "EADDRINUSE") {
    console.error(`Port ${port} is busy — the viewer may already be running at http://127.0.0.1:${port}`);
    process.exit(1);
  }
  throw err;
});
