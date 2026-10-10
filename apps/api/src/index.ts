import Fastify from "fastify";
import cors from "@fastify/cors";
import {
  closeSessionSchema,
  createArtifactSchema,
  createEventSchema,
  ingestSchema,
  launchBodySchema,
  patchPrioritySchema,
  publishLedgerSchema,
  upsertSessionSchema,
  type Priority,
} from "@accountabilibrosis/shared";
import { prioritiesFromTranscript } from "./ingest.js";
import { buildLaunchPlan } from "./launch.js";
import { buildLedgerEntry, maybeVerify, publishLedger } from "./ledger.js";
import {
  addDays,
  getSession,
  loadStore,
  newId,
  replaceSession,
  todayISO,
} from "./store.js";

const app = Fastify({ logger: true });

await app.register(cors, {
  origin: process.env.WEB_ORIGIN ?? "http://localhost:5173",
});

app.get("/health", async () => ({ ok: true }));

app.get("/api/session", async (req) => {
  const date = (req.query as { date?: string }).date ?? todayISO();
  const store = loadStore();
  return { user: store.user, session: getSession(store, date) };
});

app.put("/api/session", async (req, reply) => {
  const parsed = upsertSessionSchema.safeParse(req.body);
  if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
  const store = loadStore();
  const session = getSession(store, parsed.data.date);
  session.priorities = parsed.data.priorities.map((p, i) => ({
    id: p.id ?? newId("task"),
    title: p.title ?? `Priority ${i + 1}`,
    verification_type: p.verification_type ?? "text",
    verification_criteria: p.verification_criteria ?? "",
    prep_actions: p.prep_actions ?? [],
    status: p.status ?? "not_started",
    notes: p.notes ?? "",
    blocked: p.blocked ?? false,
  }));
  if (!session.currentPriorityId) {
    session.currentPriorityId = session.priorities[0]?.id ?? null;
  }
  replaceSession(store, session);
  return { user: store.user, session };
});

app.post("/api/ingest", async (req, reply) => {
  const parsed = ingestSchema.safeParse(req.body);
  if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
  const targetDate = parsed.data.targetDate ?? todayISO();
  const store = loadStore();
  const session = getSession(store, targetDate);
  const priorities = prioritiesFromTranscript(parsed.data.transcript);
  session.voiceMemo = { transcript: parsed.data.transcript, targetDate };
  if (priorities.length) {
    session.priorities = priorities;
    session.currentPriorityId = priorities[0]?.id ?? null;
    if (session.status === "closed") session.status = "planned";
  }
  replaceSession(store, session);
  return { user: store.user, session };
});

app.post("/api/launch", async (req, reply) => {
  const parsed = launchBodySchema.safeParse(req.body ?? {});
  if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
  const date = parsed.data.date ?? todayISO();
  const store = loadStore();
  const session = getSession(store, date);
  session.status = session.status === "closed" ? "closed" : "launched";
  if (session.priorities[0]) {
    session.currentPriorityId = session.priorities[0].id;
    session.priorities[0].status =
      session.priorities[0].status === "not_started"
        ? "in_progress"
        : session.priorities[0].status;
  }
  replaceSession(store, session);
  return { user: store.user, session, launchPlan: buildLaunchPlan(session) };
});

app.patch("/api/priorities/:id", async (req, reply) => {
  const { id } = req.params as { id: string };
  const parsed = patchPrioritySchema.safeParse(req.body ?? {});
  if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
  const date = parsed.data.date ?? todayISO();
  const store = loadStore();
  const session = getSession(store, date);
  const priority = session.priorities.find((p) => p.id === id);
  if (!priority) return reply.code(404).send({ error: "priority not found" });
  if (parsed.data.status) priority.status = parsed.data.status;
  if (parsed.data.notes !== undefined) priority.notes = parsed.data.notes;
  if (parsed.data.blocked !== undefined) priority.blocked = parsed.data.blocked;
  if (priority.status === "in_progress") {
    session.currentPriorityId = priority.id;
    if (session.status === "launched" || session.status === "planned") {
      session.status = "in_progress";
    }
  }
  replaceSession(store, session);
  return { user: store.user, session };
});

app.post("/api/artifacts", async (req, reply) => {
  const parsed = createArtifactSchema.safeParse(req.body);
  if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
  const date = parsed.data.date ?? todayISO();
  const store = loadStore();
  const session = getSession(store, date);
  const priority = session.priorities.find((p) => p.id === parsed.data.priorityId);
  if (!priority) return reply.code(404).send({ error: "priority not found" });
  const verification = await maybeVerify(parsed.data.type, parsed.data.value);
  const artifact = {
    id: newId("art"),
    priorityId: parsed.data.priorityId,
    type: parsed.data.type,
    value: parsed.data.value,
    caption: parsed.data.caption ?? "",
    verification,
  };
  session.artifacts.push(artifact);
  replaceSession(store, session);
  return { user: store.user, session, artifact };
});

app.post("/api/session/close", async (req, reply) => {
  const parsed = closeSessionSchema.safeParse(req.body ?? {});
  if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
  const date = parsed.data.date ?? todayISO();
  const store = loadStore();
  const session = getSession(store, date);
  session.status = "closed";
  session.ledgerEntry = buildLedgerEntry(session);
  if (parsed.data.nextTranscript) {
    const nextDate = parsed.data.nextDate ?? addDays(date, 1);
    const tomorrow = getSession(store, nextDate);
    const seeded: Priority[] = prioritiesFromTranscript(parsed.data.nextTranscript);
    tomorrow.voiceMemo = { transcript: parsed.data.nextTranscript, targetDate: nextDate };
    if (seeded.length) {
      tomorrow.priorities = seeded;
      tomorrow.currentPriorityId = seeded[0]?.id ?? null;
      tomorrow.status = "planned";
    }
    replaceSession(store, tomorrow);
  }
  replaceSession(store, session);
  return { user: store.user, session };
});

app.get("/api/ledger", async () => {
  const store = loadStore();
  const entries = store.sessions
    .map((s) => s.ledgerEntry)
    .filter((e): e is NonNullable<typeof e> => Boolean(e))
    .sort((a, b) => b.date.localeCompare(a.date));
  return { user: store.user, entries };
});

app.post("/api/ledger/publish", async (req, reply) => {
  const parsed = publishLedgerSchema.safeParse(req.body ?? {});
  if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
  const date = parsed.data.date ?? todayISO();
  const store = loadStore();
  const session = getSession(store, date);
  if (!session.ledgerEntry) session.ledgerEntry = buildLedgerEntry(session);
  const result = await publishLedger(session.ledgerEntry.body);
  if (result.ok) session.ledgerEntry.published = true;
  replaceSession(store, session);
  return { user: store.user, session, publish: result };
});

app.post("/api/events", async (req, reply) => {
  const parsed = createEventSchema.safeParse(req.body ?? {});
  if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
  const date = parsed.data.date ?? todayISO();
  const store = loadStore();
  const session = getSession(store, date);
  session.events.push({
    id: newId("evt"),
    type: parsed.data.type,
    at: new Date().toISOString(),
    note: parsed.data.note,
  });
  replaceSession(store, session);
  return { user: store.user, session };
});

const port = Number(process.env.PORT ?? 3001);
await app.listen({ port, host: "0.0.0.0" });
console.log(`api on http://localhost:${port}`);
