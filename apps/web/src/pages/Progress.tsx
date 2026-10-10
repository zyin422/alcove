import { useEffect, useState } from "react";
import type { Priority, Session } from "@accountabilibrosis/shared";
import { api } from "../api";

export function Progress() {
  const [session, setSession] = useState<Session | null>(null);
  const [transcript, setTranscript] = useState("");
  const [nextTranscript, setNextTranscript] = useState("");
  const [artifactValue, setArtifactValue] = useState("");
  const [artifactPriority, setArtifactPriority] = useState("");
  const [artifactType, setArtifactType] = useState<Priority["verification_type"]>("url");
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function refresh() {
    const r = await api.session();
    setSession(r.session);
    if (!artifactPriority && r.session.priorities[0]) {
      setArtifactPriority(r.session.priorities[0].id);
    }
  }

  useEffect(() => {
    refresh().catch((e) => setError(String(e)));
  }, []);

  async function ingest() {
    setError(null);
    try {
      const r = await api.ingest(transcript);
      setSession(r.session);
      setMessage(`Ingested ${r.session.priorities.length} priorities.`);
    } catch (e) {
      setError(String(e));
    }
  }

  async function patch(id: string, status: Priority["status"]) {
    const r = await api.patchPriority(id, { status, date: session?.date });
    setSession(r.session);
  }

  async function addArtifact() {
    if (!artifactPriority || !artifactValue) return;
    setError(null);
    try {
      const r = await api.addArtifact({
        date: session?.date,
        priorityId: artifactPriority,
        type: artifactType,
        value: artifactValue,
      });
      setSession(r.session);
      setArtifactValue("");
    } catch (e) {
      setError(String(e));
    }
  }

  async function closeDay() {
    setError(null);
    try {
      const r = await api.close({
        date: session?.date,
        nextTranscript: nextTranscript || undefined,
      });
      setSession(r.session);
      setMessage("Day closed. Check the public ledger.");
    } catch (e) {
      setError(String(e));
    }
  }

  return (
    <div className="grid">
      <h1>Progress tracking</h1>
      <p className="lede">
        Paste a memo if the room is loud. Status is yours to set; close writes a
        neutral ledger row, not a scolding.
      </p>
      {error && <p className="error">{error}</p>}
      {message && <p className="muted">{message}</p>}

      <div className="card">
        <h3>Ingest (textarea is the required path)</h3>
        <textarea
          placeholder={"1. Ship the launchpad demo\n2. Publish a ledger row https://github.com\n3. Draft the five-minute pitch"}
          value={transcript}
          onChange={(e) => setTranscript(e.target.value)}
        />
        <div className="row" style={{ marginTop: 10 }}>
          <button className="btn" onClick={ingest}>
            Parse into priorities
          </button>
        </div>
      </div>

      {(session?.priorities ?? []).map((p) => (
        <div className="card" key={p.id}>
          <span className={`chip ${p.status === "done" ? "ok" : p.status === "forfeited" ? "bad" : ""}`}>
            {p.status}
          </span>
          <h3>{p.title}</h3>
          <p className="muted">{p.verification_criteria}</p>
          <div className="row">
            {(["not_started", "in_progress", "done", "forfeited"] as const).map((s) => (
              <button key={s} className="btn secondary" onClick={() => patch(p.id, s)}>
                {s}
              </button>
            ))}
          </div>
          <div>
            {session?.artifacts
              .filter((a) => a.priorityId === p.id)
              .map((a) => (
                <p key={a.id} className="muted">
                  artifact · {a.type} · {a.value} · {a.verification}
                </p>
              ))}
          </div>
        </div>
      ))}

      <div className="card">
        <h3>Attach proof-of-work</h3>
        <div className="row">
          <select
            value={artifactPriority}
            onChange={(e) => setArtifactPriority(e.target.value)}
            style={{ maxWidth: 280 }}
          >
            {(session?.priorities ?? []).map((p) => (
              <option key={p.id} value={p.id}>
                {p.title}
              </option>
            ))}
          </select>
          <select
            value={artifactType}
            onChange={(e) => setArtifactType(e.target.value as Priority["verification_type"])}
            style={{ maxWidth: 140 }}
          >
            <option value="url">url</option>
            <option value="commit">commit</option>
            <option value="text">text</option>
          </select>
        </div>
        <input
          style={{ marginTop: 8 }}
          placeholder="https://github.com/org/repo/commit/4a9f12"
          value={artifactValue}
          onChange={(e) => setArtifactValue(e.target.value)}
        />
        <div className="row" style={{ marginTop: 10 }}>
          <button className="btn secondary" onClick={addArtifact}>
            Save artifact
          </button>
        </div>
      </div>

      <div className="card">
        <h3>Close the day</h3>
        <p className="muted">Optional memo seeds tomorrow&apos;s Launchpad.</p>
        <textarea
          placeholder="Tomorrow: 1. …"
          value={nextTranscript}
          onChange={(e) => setNextTranscript(e.target.value)}
        />
        <div className="row" style={{ marginTop: 10 }}>
          <button className="btn" onClick={closeDay}>
            Close &amp; write ledger
          </button>
        </div>
      </div>
    </div>
  );
}
