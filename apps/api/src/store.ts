import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { Priority, Session, Store } from "@accountabilibrosis/shared";

const root = join(fileURLToPath(new URL(".", import.meta.url)), "../../..");
export const dataDir = join(root, "data");
export const storePath = join(dataDir, "store.json");

export const DEMO_USER = { id: "user_alex", displayName: "Alex" };

export function todayISO(date = new Date()): string {
  return date.toISOString().slice(0, 10);
}

export function addDays(dateISO: string, days: number): string {
  const d = new Date(`${dateISO}T12:00:00`);
  d.setDate(d.getDate() + days);
  return todayISO(d);
}

function seedPriorities(_date: string): Priority[] {
  return [
    {
      id: "task_1",
      title: "Ship Code Ada Launchpad demo",
      verification_type: "url",
      verification_criteria: "https://github.com with a public repo URL",
      prep_actions: [
        "Open the repo README",
        "Confirm /launch and sidecar routes load",
      ],
      status: "not_started",
      notes: "",
      blocked: false,
    },
    {
      id: "task_2",
      title: "Record a public ledger row",
      verification_type: "commit",
      verification_criteria: "Commit SHA or compare URL on GitHub",
      prep_actions: [
        "Open /progress",
        "Attach an artifact to this priority",
      ],
      status: "not_started",
      notes: "",
      blocked: false,
    },
    {
      id: "task_3",
      title: "Draft Sunday 5-minute pitch",
      verification_type: "text",
      verification_criteria: "Outline covering problem, demo, Cursor usage, Mirror next step",
      prep_actions: [
        "Open docs/PRESENTATION.md",
        "Pre-fill speaker beats in the sidecar",
      ],
      status: "not_started",
      notes: "",
      blocked: false,
    },
  ];
}

export function emptySession(date: string): Session {
  return {
    date,
    status: "planned",
    currentPriorityId: null,
    priorities: [],
    artifacts: [],
    events: [],
    ledgerEntry: null,
    voiceMemo: null,
  };
}

export function seedStore(): Store {
  const date = todayISO();
  const priorities = seedPriorities(date);
  return {
    user: DEMO_USER,
    sessions: [
      {
        ...emptySession(date),
        currentPriorityId: priorities[0]?.id ?? null,
        priorities,
      },
    ],
  };
}

export function loadStore(): Store {
  try {
    const raw = readFileSync(storePath, "utf8");
    return JSON.parse(raw) as Store;
  } catch {
    const seeded = seedStore();
    saveStore(seeded);
    return seeded;
  }
}

export function saveStore(store: Store): void {
  mkdirSync(dirname(storePath), { recursive: true });
  writeFileSync(storePath, JSON.stringify(store, null, 2));
}

export function getSession(store: Store, date: string): Session {
  const found = store.sessions.find((s) => s.date === date);
  if (found) return found;
  const created = emptySession(date);
  store.sessions.push(created);
  saveStore(store);
  return created;
}

export function replaceSession(store: Store, session: Session): Session {
  const idx = store.sessions.findIndex((s) => s.date === session.date);
  if (idx === -1) store.sessions.push(session);
  else store.sessions[idx] = session;
  saveStore(store);
  return session;
}

export function newId(prefix: string): string {
  return `${prefix}_${Math.random().toString(36).slice(2, 8)}`;
}
