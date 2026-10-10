import type { LedgerEntry, Session } from "@accountabilibrosis/shared";
import { DEMO_USER } from "./store.js";

export function formatLedgerBody(entry: Omit<LedgerEntry, "body" | "published">): string {
  const blocks = entry.lines.map((line) =>
    [
      "[Daily Proof-of-Work Record]",
      `User: ${entry.user}`,
      `Commitment: ${line.commitment}`,
      `Status: ${line.status}`,
      `Artifact: ${line.artifact}`,
    ].join("\n"),
  );
  return blocks.join("\n\n");
}

export function buildLedgerEntry(session: Session): LedgerEntry {
  const lines = session.priorities.map((priority) => {
    const artifacts = session.artifacts.filter((a) => a.priorityId === priority.id);
    const best = artifacts.find((a) => a.verification === "verified") ?? artifacts[0];
    let status: LedgerEntry["lines"][number]["status"] = "FAIL";
    if (priority.status === "done" && best?.verification === "verified") status = "VERIFIED";
    else if (priority.status === "done") status = "UNVERIFIED";
    else if (best) status = "UNVERIFIED";
    return {
      commitment: priority.title,
      status,
      artifact: best?.value ?? "(none)",
    };
  });

  const partial = {
    date: session.date,
    user: DEMO_USER.displayName,
    lines,
  };

  return {
    ...partial,
    body: formatLedgerBody(partial),
    published: false,
  };
}

export async function publishLedger(body: string): Promise<{ ok: boolean; dryRun: boolean; error?: string }> {
  const url = process.env.DISCORD_WEBHOOK_URL;
  if (!url) {
    console.log("[ledger dry-run]\n" + body);
    return { ok: true, dryRun: true };
  }
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content: body.slice(0, 1900) }),
    });
    if (!res.ok) {
      const text = await res.text();
      return { ok: false, dryRun: false, error: text };
    }
    return { ok: true, dryRun: false };
  } catch (err) {
    return { ok: false, dryRun: false, error: String(err) };
  }
}

export async function maybeVerify(type: string, value: string): Promise<"verified" | "unverified" | "failed"> {
  if (type === "text") return "unverified";
  if (!/^https?:\/\//i.test(value) && type !== "commit") return "unverified";
  const target =
    type === "commit" && !/^https?:\/\//i.test(value)
      ? `https://github.com/${value}`
      : value;
  if (!/^https?:\/\//i.test(target)) return "unverified";
  try {
    const res = await fetch(target, { method: "HEAD", redirect: "follow" });
    if (res.ok || res.status === 405) return "verified";
    return "unverified";
  } catch {
    return "unverified";
  }
}
