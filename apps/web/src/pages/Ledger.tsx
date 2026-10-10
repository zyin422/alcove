import { useEffect, useState } from "react";
import type { LedgerEntry } from "@accountabilibrosis/shared";
import { api } from "../api";

export function Ledger() {
  const [entries, setEntries] = useState<LedgerEntry[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);

  async function load() {
    const r = await api.ledger();
    setEntries(r.entries);
  }

  useEffect(() => {
    load().catch((e) => setError(String(e)));
  }, []);

  async function publish(date: string) {
    setError(null);
    try {
      const r = await api.publish(date);
      setNote(
        r.publish.dryRun
          ? "Dry-run: payload logged on the API (set DISCORD_WEBHOOK_URL to post)."
          : r.publish.ok
            ? "Published to webhook."
            : r.publish.error ?? "Publish failed",
      );
      await load();
    } catch (e) {
      setError(String(e));
    }
  }

  return (
    <div className="grid">
      <h1>Public ledger</h1>
      <p className="lede">
        Skin in the game without shaming. Judges can read this page even if
        Discord is down.
      </p>
      {error && <p className="error">{error}</p>}
      {note && <p className="muted">{note}</p>}
      {!entries.length && <p className="muted">No closed days yet. Close a session on Progress.</p>}
      {entries.map((entry) => (
        <div className="card" key={entry.date}>
          <div className="row">
            <span className="chip">{entry.date}</span>
            {entry.published ? <span className="chip ok">published</span> : <span className="chip warn">local</span>}
            <button className="btn secondary" onClick={() => publish(entry.date)}>
              Publish
            </button>
          </div>
          {entry.lines.map((line) => (
            <p key={line.commitment}>
              <span
                className={`chip ${line.status === "VERIFIED" ? "ok" : line.status === "FAIL" ? "bad" : "warn"}`}
              >
                {line.status}
              </span>{" "}
              {line.commitment} · {line.artifact}
            </p>
          ))}
          <pre className="pre">{entry.body}</pre>
        </div>
      ))}
    </div>
  );
}
