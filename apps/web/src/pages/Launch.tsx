import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import type { LaunchPlan, Session } from "@accountabilibrosis/shared";
import { api } from "../api";

export function Launch() {
  const [session, setSession] = useState<Session | null>(null);
  const [plan, setPlan] = useState<LaunchPlan | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    api
      .session()
      .then((r) => setSession(r.session))
      .catch((e) => setError(String(e)));
  }, []);

  async function launch() {
    setBusy(true);
    setError(null);
    try {
      const r = await api.launch(session?.date);
      setSession(r.session);
      setPlan(r.launchPlan);
      window.open(r.launchPlan.sidecarUrl, "sidecar");
      window.open(r.launchPlan.focusUrl, "focus");
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="grid">
      <h1>Launchpad</h1>
      <p className="lede">
        Environment is the first decision. Launch opens the focus surface and a
        Zone B sidecar so starting is editing, not creating.
      </p>
      {error && <p className="error">{error}</p>}
      <div className="row">
        <button className="btn" disabled={busy} onClick={launch}>
          {busy ? "Staging…" : "Launch workspace"}
        </button>
        <Link className="btn secondary" to="/launch/sidecar">
          Open sidecar here
        </Link>
      </div>
      <div className="cards">
        {(session?.priorities ?? []).map((p) => (
          <div className="card priority" key={p.id}>
            <span className="chip">{p.status}</span>
            <h3>{p.title}</h3>
            <p className="muted">{p.verification_criteria}</p>
            <ul>
              {p.prep_actions.map((a) => (
                <li key={a}>{a}</li>
              ))}
            </ul>
          </div>
        ))}
        {!session?.priorities.length && (
          <p className="muted">
            No priorities yet. Add them on <Link to="/progress">Progress</Link>.
          </p>
        )}
      </div>
      {plan && (
        <div className="card">
          <h3>Launch plan</h3>
          <p>
            Focus: <a href={plan.focusUrl}>{plan.focusUrl}</a>
          </p>
          <p className="muted">
            Minimize (never Discord / Chrome / Cursor): {plan.appsToMinimize.join(", ")}
            {plan.hardKill ? " · hard kill ON" : " · hard kill off"}
          </p>
          <p className="muted">If popups are blocked, run:</p>
          <pre className="pre">{plan.command}</pre>
          <pre className="pre">{plan.preDraftMarkdown}</pre>
        </div>
      )}
    </div>
  );
}
