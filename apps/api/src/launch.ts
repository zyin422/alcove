import type { LaunchPlan, Session } from "@accountabilibrosis/shared";

const DEFAULT_MINIMIZE = ["Steam", "Messages", "Twitter"];
const NEVER_KILL = new Set(["Discord", "Google Chrome", "Chrome", "Cursor", "Code"]);

function urlsIn(text: string): string[] {
  return text.match(/https?:\/\/[^\s)]+/g) ?? [];
}

export function buildLaunchPlan(session: Session): LaunchPlan {
  const sidecarUrl =
    process.env.SIDECAR_URL ?? "http://localhost:5173/launch/sidecar";
  const hardKill = process.env.HARD_KILL === "true";

  const collected: string[] = [];
  for (const p of session.priorities) {
    collected.push(...urlsIn(p.verification_criteria));
    for (const action of p.prep_actions) collected.push(...urlsIn(action));
  }

  const unique = [...new Set(collected)];
  const focusUrl = unique[0] ?? "https://github.com";
  const referenceUrls = unique.slice(1);

  const first = session.priorities[0];
  const bullets = session.priorities
    .map((p) => {
      const steps = p.prep_actions.map((a) => `  - ${a}`).join("\n");
      return `- **${p.title}**\n${steps}`;
    })
    .join("\n");

  const preDraftMarkdown = first
    ? `# Today's runway\n\nStart on: ${first.title}\n\n${bullets}\n`
    : `# Today's runway\n\nNo priorities yet. Add three on /progress or PUT /api/session.\n`;

  const appsToMinimize = DEFAULT_MINIMIZE.filter((name) => !NEVER_KILL.has(name));
  const killFlag = hardKill ? "1" : "0";
  const command = `./desktop/macos/launch_workspace.sh ${JSON.stringify(focusUrl)} ${JSON.stringify(sidecarUrl)} ${killFlag}`;

  return {
    focusUrl,
    referenceUrls,
    sidecarUrl,
    appsToMinimize,
    hardKill,
    preDraftMarkdown,
    command,
  };
}
