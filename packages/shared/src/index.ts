import { z } from "zod";

export const verificationTypeSchema = z.enum(["url", "commit", "text"]);
export const priorityStatusSchema = z.enum([
  "not_started",
  "in_progress",
  "done",
  "forfeited",
]);
export const sessionStatusSchema = z.enum([
  "planned",
  "launched",
  "in_progress",
  "closed",
]);
export const artifactVerificationSchema = z.enum([
  "unverified",
  "verified",
  "failed",
]);
export const eventTypeSchema = z.enum(["distraction", "stuck", "break"]);
export const ledgerStatusSchema = z.enum(["VERIFIED", "UNVERIFIED", "FAIL"]);

export const userSchema = z.object({
  id: z.string(),
  displayName: z.string(),
});

export const prioritySchema = z.object({
  id: z.string(),
  title: z.string(),
  verification_type: verificationTypeSchema,
  verification_criteria: z.string(),
  prep_actions: z.array(z.string()),
  status: priorityStatusSchema,
  notes: z.string(),
  blocked: z.boolean(),
});

export const artifactSchema = z.object({
  id: z.string(),
  priorityId: z.string(),
  type: verificationTypeSchema,
  value: z.string(),
  caption: z.string(),
  verification: artifactVerificationSchema,
});

export const sessionEventSchema = z.object({
  id: z.string(),
  type: eventTypeSchema,
  at: z.string(),
  note: z.string().optional(),
});

export const ledgerLineSchema = z.object({
  commitment: z.string(),
  status: ledgerStatusSchema,
  artifact: z.string(),
});

export const ledgerEntrySchema = z.object({
  date: z.string(),
  user: z.string(),
  lines: z.array(ledgerLineSchema),
  body: z.string(),
  published: z.boolean(),
});

export const voiceMemoSchema = z.object({
  transcript: z.string(),
  targetDate: z.string(),
});

export const sessionSchema = z.object({
  date: z.string(),
  status: sessionStatusSchema,
  currentPriorityId: z.string().nullable(),
  priorities: z.array(prioritySchema),
  artifacts: z.array(artifactSchema),
  events: z.array(sessionEventSchema),
  ledgerEntry: ledgerEntrySchema.nullable(),
  voiceMemo: voiceMemoSchema.nullable(),
});

export const storeSchema = z.object({
  user: userSchema,
  sessions: z.array(sessionSchema),
});

export const launchPlanSchema = z.object({
  focusUrl: z.string(),
  referenceUrls: z.array(z.string()),
  sidecarUrl: z.string(),
  appsToMinimize: z.array(z.string()),
  hardKill: z.boolean(),
  preDraftMarkdown: z.string(),
  command: z.string(),
});

export const upsertSessionSchema = z.object({
  date: z.string(),
  priorities: z.array(prioritySchema.partial({ id: true })),
});

export const ingestSchema = z.object({
  transcript: z.string().default(""),
  targetDate: z.string().optional(),
});

export const launchBodySchema = z.object({
  date: z.string().optional(),
});

export const patchPrioritySchema = z.object({
  date: z.string().optional(),
  status: priorityStatusSchema.optional(),
  notes: z.string().optional(),
  blocked: z.boolean().optional(),
});

export const createArtifactSchema = z.object({
  date: z.string().optional(),
  priorityId: z.string(),
  type: verificationTypeSchema,
  value: z.string(),
  caption: z.string().optional(),
});

export const closeSessionSchema = z.object({
  date: z.string().optional(),
  nextTranscript: z.string().optional(),
  nextDate: z.string().optional(),
});

export const publishLedgerSchema = z.object({
  date: z.string().optional(),
});

export const createEventSchema = z.object({
  date: z.string().optional(),
  type: eventTypeSchema,
  note: z.string().optional(),
});

export type User = z.infer<typeof userSchema>;
export type Priority = z.infer<typeof prioritySchema>;
export type Artifact = z.infer<typeof artifactSchema>;
export type SessionEvent = z.infer<typeof sessionEventSchema>;
export type LedgerEntry = z.infer<typeof ledgerEntrySchema>;
export type Session = z.infer<typeof sessionSchema>;
export type Store = z.infer<typeof storeSchema>;
export type LaunchPlan = z.infer<typeof launchPlanSchema>;
