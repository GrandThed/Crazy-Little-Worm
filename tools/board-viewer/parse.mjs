// BOARD.md -> structured board data.
//
// The board's own card format is the contract (BOARD.md rule 4):
//   **ID** (size) Title · code: <modules> · assets: <models> · ✔ criteria
// Anything that doesn't match is passed through as a note so the viewer never
// silently drops a card the parser didn't understand.

const COLUMNS = [
  { key: "backlog", match: /backlog/i, name: "Backlog", icon: "📋" },
  { key: "ready", match: /ready/i, name: "Ready", icon: "🔜" },
  { key: "inprogress", match: /in progress/i, name: "In Progress", icon: "🔨" },
  { key: "review", match: /review/i, name: "Review", icon: "👀" },
  { key: "done", match: /done/i, name: "Done", icon: "✅" },
];

// Fixed slot order (dataviz categorical theme). Assigned by first appearance in
// the document so a new epic takes the next free slot rather than re-coloring
// the existing ones.
const SLOTS = 8;

const CARD_RE = /^-\s+\*\*([A-Z]+-\d+)\*\*\s*(.*)$/;
const EPIC_RE = /^###\s+Epic\s+([A-Z])\s*[—-]\s*(.+)$/;
const SECTION_RE = /^##\s+(.+)$/;

const stripEmphasis = (s) => s.replace(/\*\*/g, "").trim();

function parseCard(id, rest, line) {
  const parts = rest
    .split("·")
    .map((p) => p.trim())
    .filter(Boolean);

  const card = {
    id,
    epic: id.split("-")[0],
    num: Number(id.split("-")[1]),
    size: null,
    title: "",
    code: null,
    assets: null,
    criteria: null,
    blocked: null,
    notes: [],
    line,
  };

  const head = parts.shift() ?? "";
  const sized = head.match(/^\((.+?)\)\s*(.*)$/);
  if (sized) {
    card.size = sized[1];
    card.title = stripEmphasis(sized[2]);
  } else {
    card.title = stripEmphasis(head);
  }

  for (const part of parts) {
    if (/^code\s*:/i.test(part)) card.code = part.replace(/^code\s*:/i, "").trim();
    else if (/^assets\s*:/i.test(part)) card.assets = part.replace(/^assets\s*:/i, "").trim();
    else if (part.startsWith("✔")) card.criteria = part.slice(1).trim();
    else if (part.startsWith("⛔")) card.blocked = part.replace(/^⛔\s*blocked\s*:?/i, "").trim();
    else card.notes.push(stripEmphasis(part));
  }

  // A card is only board-legal in Ready with criteria + code/assets lines; the
  // viewer surfaces the gap rather than the parser guessing intent.
  card.needsSplit = /split/i.test(card.size ?? "");
  return card;
}

export function parseBoard(markdown) {
  const lines = markdown.split(/\r?\n/);

  const board = {
    title: "Board",
    milestone: null,
    wipLimit: null,
    columns: COLUMNS.map((c) => ({ ...c, match: undefined, groups: [], count: 0 })),
    epics: [],
    unparsed: [],
  };

  const epicIndex = new Map();
  const columnByKey = new Map(board.columns.map((c) => [c.key, c]));

  const epicFor = (letter, headingName, milestone, spec) => {
    if (!epicIndex.has(letter)) {
      epicIndex.set(letter, {
        letter,
        name: headingName ?? `Epic ${letter}`,
        milestone: milestone ?? null,
        spec: spec ?? null,
        slot: (epicIndex.size % SLOTS) + 1,
        total: 0,
        done: 0,
      });
      board.epics.push(epicIndex.get(letter));
    }
    const epic = epicIndex.get(letter);
    if (headingName) {
      epic.name = headingName;
      epic.milestone = milestone ?? epic.milestone;
      epic.spec = spec ?? epic.spec;
    }
    return epic;
  };

  let column = null;
  let group = null;

  lines.forEach((raw, i) => {
    const lineNo = i + 1;

    if (/^#\s+/.test(raw)) {
      board.title = raw.replace(/^#\s+/, "").trim();
      return;
    }

    const current = raw.match(/Current:\s*\*\*(.+?)\*\*/);
    if (current) board.milestone = current[1];

    const section = raw.match(SECTION_RE);
    if (section) {
      const heading = section[1];
      const wip = heading.match(/WIP\s*[≤<=]+\s*(\d+)/i);
      const found = COLUMNS.find((c) => c.match.test(heading));
      column = found ? columnByKey.get(found.key) : null;
      group = null;
      if (column && wip) {
        column.wipLimit = Number(wip[1]);
        board.wipLimit = Number(wip[1]);
      }
      return;
    }

    if (!column) return;

    const epicHeading = raw.match(EPIC_RE);
    if (epicHeading) {
      const [, letter, tail] = epicHeading;
      const milestone = tail.match(/\((M\d+)\)/)?.[1] ?? null;
      const spec = tail.match(/spec:\s*(.+)$/i)?.[1]?.trim() ?? null;
      const name = tail
        .replace(/\(M\d+\)/, "")
        .replace(/[—-]\s*spec:.*$/i, "")
        .replace(/[—-]\s*$/, "")
        .trim();
      const epic = epicFor(letter, name, milestone, spec);
      group = { epic: letter, name: epic.name, milestone: epic.milestone, spec: epic.spec, cards: [] };
      column.groups.push(group);
      return;
    }

    const card = raw.match(CARD_RE);
    if (card) {
      const parsed = parseCard(card[1], card[2], lineNo);
      parsed.column = column.key;
      const epic = epicFor(parsed.epic);
      epic.total += 1;
      if (column.key === "done") epic.done += 1;

      if (!group || group.epic !== parsed.epic) {
        group = column.groups.find((g) => g.epic === parsed.epic && g.loose);
        if (!group) {
          group = { epic: parsed.epic, name: epic.name, milestone: epic.milestone, loose: true, cards: [] };
          column.groups.push(group);
        }
      }
      group.cards.push(parsed);
      column.count += 1;
      return;
    }

    // A bullet inside a column that isn't a card — worth showing, not dropping.
    if (/^-\s+\S/.test(raw)) board.unparsed.push({ line: lineNo, text: raw.trim(), column: column.key });
  });

  board.epics.sort((a, b) => a.slot - b.slot);
  return board;
}
