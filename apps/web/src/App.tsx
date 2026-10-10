import { NavLink, Route, Routes } from "react-router-dom";
import { Home } from "./pages/Home";
import { Launch } from "./pages/Launch";
import { LaunchSidecar } from "./pages/LaunchSidecar";
import { Ledger } from "./pages/Ledger";
import { Progress } from "./pages/Progress";

function Nav() {
  return (
    <nav className="nav">
      <NavLink to="/" className="brand" end>
        Accountabili<span>brosis</span>
      </NavLink>
      <NavLink to="/launch" className={({ isActive }) => (isActive ? "active" : "")}>
        Launchpad
      </NavLink>
      <NavLink to="/progress" className={({ isActive }) => (isActive ? "active" : "")}>
        Progress
      </NavLink>
      <NavLink to="/ledger" className={({ isActive }) => (isActive ? "active" : "")}>
        Ledger
      </NavLink>
    </nav>
  );
}

export function App() {
  return (
    <div className="shell">
      <Nav />
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/launch" element={<Launch />} />
        <Route path="/launch/sidecar" element={<LaunchSidecar />} />
        <Route path="/progress" element={<Progress />} />
        <Route path="/ledger" element={<Ledger />} />
      </Routes>
    </div>
  );
}
