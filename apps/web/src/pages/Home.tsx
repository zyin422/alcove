import { Link } from "react-router-dom";

export function Home() {
  return (
    <div className="grid">
      <h1>Chief of Staff, not hall monitor.</h1>
      <p className="lede">
        Code Ada 2026 · Off the Clock. Most accountability tools nag or punish.
        Accountabilibrosis pre-stages the workspace, tracks proof-of-work, and
        posts a neutral public record. The Mirror (mid-session interrogation)
        waits until Launchpad and Ledger ship.
      </p>
      <div className="cards two">
        <div className="card">
          <h3>Team Launchpad</h3>
          <p className="muted">Morning staging, sidecar, demo-safe focus mode.</p>
          <Link to="/launch">Open Launchpad →</Link>
        </div>
        <div className="card">
          <h3>Team Ledger</h3>
          <p className="muted">Ingest, progress, artifacts, public Pass/Fail.</p>
          <Link to="/progress">Open progress →</Link>
        </div>
      </div>
      <p className="muted">
        Demo path: seed or ingest three priorities → Launch → attach an artifact
        → close the day → read the ledger.
      </p>
    </div>
  );
}
