import { useEffect, useState } from "react";
import type { Session } from "@accountabilibrosis/shared";
import { api } from "../api";

export function LaunchSidecar() {
  const [session, setSession] = useState<Session | null>(null);
  const [seconds, setSeconds] = useState(50 * 60);

  useEffect(() => {
    api.session().then((r) => setSession(r.session));
  }, []);

  useEffect(() => {
    const t = setInterval(() => setSeconds((s) => Math.max(0, s - 1)), 1000);
    return () => clearInterval(t);
  }, []);

  const mm = String(Math.floor(seconds / 60)).padStart(2, "0");
  const ss = String(seconds % 60).padStart(2, "0");
  const current = session?.priorities.find((p) => p.id === session.currentPriorityId);

  return (
    <div className="grid">
      <h1>Zone B · sidecar</h1>
      <p className="lede">Stay on the commitment. This panel is the agent, not a blocker.</p>
      <div className="card">
        <span className="chip ok">focus block</span>
        <h2 style={{ fontSize: "3rem", margin: "8px 0" }}>
          {mm}:{ss}
        </h2>
        <p className="muted">Session {session?.date ?? "—"} · {session?.status ?? "planned"}</p>
      </div>
      <div className="card">
        <h3>Now</h3>
        <p>{current?.title ?? "No current priority"}</p>
        {current && (
          <ul>
            {current.prep_actions.map((a) => (
              <li key={a}>{a}</li>
            ))}
          </ul>
        )}
      </div>
      <div className="card">
        <h3>Today</h3>
        {(session?.priorities ?? []).map((p) => (
          <p key={p.id}>
            <span className={`chip ${p.status === "done" ? "ok" : ""}`}>{p.status}</span>{" "}
            {p.title}
          </p>
        ))}
      </div>
    </div>
  );
}
