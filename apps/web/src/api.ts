import type { Artifact, LaunchPlan, LedgerEntry, Session, User } from "@accountabilibrosis/shared";

export type SessionPayload = { user: User; session: Session };
export type LaunchPayload = SessionPayload & { launchPlan: LaunchPlan };
export type LedgerPayload = { user: User; entries: LedgerEntry[] };

async function req<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || res.statusText);
  }
  return res.json() as Promise<T>;
}

export const api = {
  health: () => req<{ ok: boolean }>("/health"),
  session: (date?: string) =>
    req<SessionPayload>(`/api/session${date ? `?date=${date}` : ""}`),
  putSession: (date: string, priorities: Session["priorities"]) =>
    req<SessionPayload>("/api/session", {
      method: "PUT",
      body: JSON.stringify({ date, priorities }),
    }),
  ingest: (transcript: string, targetDate?: string) =>
    req<SessionPayload>("/api/ingest", {
      method: "POST",
      body: JSON.stringify({ transcript, targetDate }),
    }),
  launch: (date?: string) =>
    req<LaunchPayload>("/api/launch", {
      method: "POST",
      body: JSON.stringify({ date }),
    }),
  patchPriority: (
    id: string,
    body: { date?: string; status?: string; notes?: string; blocked?: boolean },
  ) =>
    req<SessionPayload>(`/api/priorities/${id}`, {
      method: "PATCH",
      body: JSON.stringify(body),
    }),
  addArtifact: (body: {
    date?: string;
    priorityId: string;
    type: Artifact["type"];
    value: string;
    caption?: string;
  }) =>
    req<SessionPayload & { artifact: Artifact }>("/api/artifacts", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  close: (body: { date?: string; nextTranscript?: string; nextDate?: string }) =>
    req<SessionPayload>("/api/session/close", {
      method: "POST",
      body: JSON.stringify(body),
    }),
  ledger: () => req<LedgerPayload>("/api/ledger"),
  publish: (date?: string) =>
    req<SessionPayload & { publish: { ok: boolean; dryRun: boolean; error?: string } }>(
      "/api/ledger/publish",
      { method: "POST", body: JSON.stringify({ date }) },
    ),
};
