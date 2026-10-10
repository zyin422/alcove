import type { Priority } from "@accountabilibrosis/shared";
import { newId } from "./store.js";

function guessType(text: string): Priority["verification_type"] {
  if (/commit|sha|github\.com\/.+\/commit/i.test(text)) return "commit";
  if (/https?:\/\//i.test(text) || /url|link|slides|doc/i.test(text)) return "url";
  return "text";
}

function extractUrl(text: string): string | undefined {
  return text.match(/https?:\/\/\S+/)?.[0];
}

/** Numbered / bulleted lines, else sentence chunks. Caps at 3 priorities. */
export function prioritiesFromTranscript(transcript: string): Priority[] {
  const cleaned = transcript.replace(/\r/g, "").trim();
  if (!cleaned) return [];

  const listed = cleaned
    .split("\n")
    .map((line) => line.replace(/^\s*(?:[-*]|\d+[.)])\s*/, "").trim())
    .filter((line) => line.length > 8);

  const chunks =
    listed.length >= 1
      ? listed.slice(0, 3)
      : cleaned
          .split(/(?<=[.!?])\s+/)
          .map((s) => s.trim())
          .filter((s) => s.length > 12)
          .slice(0, 3);

  const titles = chunks.length > 0 ? chunks : [cleaned.slice(0, 80)];

  return titles.map((title, i) => {
    const verification_type = guessType(title);
    const url = extractUrl(title);
    return {
      id: newId("task"),
      title: title.replace(/https?:\/\/\S+/g, "").trim().slice(0, 120) || `Priority ${i + 1}`,
      verification_type,
      verification_criteria: url ?? title,
      prep_actions: [
        "Open the related workspace",
        i === 0 ? "Start with the first physical next step" : "Batch after priority 1",
      ],
      status: "not_started",
      notes: "",
      blocked: false,
    };
  });
}
