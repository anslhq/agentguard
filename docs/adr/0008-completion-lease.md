# ADR 0008: Completion lease instead of completion-classification

Status: Accepted
Date: 2026-05-20
Revised: 2026-05-20 (post v2 review — taxonomy references corrected to match ADR-0002 amended)

Supersedes nothing. Replaces the "Stop-hook task-complete heuristic" candidates that were never adopted.

## Context

Host `Stop` hooks fire on every turn end, not only on true task completion. To distinguish "turn ended" from "task complete," the natural shape is some kind of **classifier**. Three candidate approaches were on the table:

1. **Deterministic CompletionClassifier** — pattern matching on `last_assistant_message` plus host signals (`background_tasks`, `stop_hook_active`, etc.) plus a ledger check for recent `done` calls. Pure module.
2. **Prompt-hook (LLM-evaluated)** — Claude Code, Cursor, and Codex all support `type: "prompt"` hooks. Use an LLM to classify the message.
3. **Ship both** — deterministic default, prompt-hook opt-in.

All three share a flaw: they ask the **wrong question**. A pattern matcher can detect a completion claim but cannot prove completion. An LLM call adds cost, latency, model dependency, and probabilistic behavior to a gate that should be deterministic. AgentGuard's brand promise is "deterministic where agents are probabilistic" (PRD §5.2); an LLM-evaluated completion gate violates the brand.

The right reframing came from outside: the Stop hook should not decide whether a task is complete. `agentguard done --finalize` should decide that. The Stop hook only enforces that completion *claims* are backed by **fresh evidence**.

This separates two concerns that were tangled:

- **Claim detection** — "did the agent say the task is done?" — language interpretation, pattern matching suffices.
- **Completion proof** — "is the task actually done?" — requires diff hash, attested check results, policy state, bypass absence.

The lease pattern attaches the proof to the ledger and uses the Stop hook only as the enforcement point for the invariant.

## Decision

Adopt the **completion lease** pattern.

### Core invariant

A task-completion claim is allowed to end the turn only when a **valid completion lease** exists for the current repo state.

### Lease lifecycle

The lease is **a record nested inside a `done` event** (per ADR-0002 amended). `agentguard done --finalize --json` is the only writer. The `done` event has `mode: "finalize"` and `leaseDecision: "issued"` when the lease is granted; otherwise `leaseDecision ∈ {none, denied}` and no `lease` field is present.

The lease is granted when, and only when, all of these hold against the current diff hash:

- All required checks are recorded `passed-current` **with attestation acceptable for the current policy mode** (ADR-0010). In `enforce` mode that means `hook-observed` or `ci-observed`; in `observe` mode `manual` also counts.
- No **unresolved completion blockers** from earlier events (see "Completion lease" in CONTEXT.md for the precise resolution semantics — `risk` events with `operationOutcome ∈ {blocked, denied-by-policy}` are resolved; `allowed`/`confirmed` with `error`/`critical` diagnostics are unresolved unless acknowledged).
- No **unresolved `bypassFindings` with `confidence: strong`** since the last verify. (Bypass findings are fields on the next `verify`/`done` event, not their own event type — ADR-0002 amended.)
- No unresolved `POL001` diagnostic since the last verify. (Policy edits are reported via `POL001` diagnostics on `verify` events; the retired alternative is documented in CONTEXT.md "Backward-compatibility note" inside the docs-lint marker block.)

The lease carries: `sessionId`, `issuedAt`, `diffHash`, `expiresAt = issuedAt + 10 min`, and `checksAttested[]` (with each entry's `attestation` field).

### Lease invalidation

A lease becomes invalid when any of the following is true at lookup time:

- Current diff hash differs from `lease.diffHash` (any edit, including untracked-file changes).
- A `verify` event after `issuedAt` carries a `bypassFindings[]` entry with `confidence: strong`.
- A `verify` event after `issuedAt` carries a `POL001` diagnostic.
- A `verify` event after `issuedAt` has any `checkResults[]` with `state: "failed-current"`.
- `now() > expiresAt`.

Leases are not extended. The agent must re-run `done --finalize` to get a fresh one.

### Stop hook behavior

The Stop hook runs `CompletionClassifier` (see Issue 21) and acts on its decision:

```
CompletionDecision ∈ {
  no_claim,                  // turn ends normally
  claim_with_valid_lease,    // turn ends normally
  claim_without_lease,       // BLOCK; reason = nextAgentInstruction
  external_blocker,          // turn ends normally (host signaled in-flight work; optional)
  already_looping,           // turn ends normally + log (AgentGuard loop budget exhausted)
  aborted                    // turn ends normally (host status: aborted | error)
}
```

`task_complete` is deliberately not a return value. The classifier does not infer task completion from prose — only the lease proves it.

**`external_blocker`** is **optional** and only set when the host payload actually carries the signal. Claude Code's documented Stop payload may include `background_tasks[]` and `session_crons[]` in some versions; if those fields are absent or unrecognized, `CompletionClassifier` ignores them and falls through to the standard claim/lease check. Adapters never fail parsing on missing optional fields.

Each Stop hook invocation writes one `classify_stop` event to the ledger (ADR-0002 amended). The event carries `messageClaim: bool`, `leaseState`, `decision`, and `loopBudget` (the field replacing the retired `loop_budget_exhausted` event).

### Host responses for `claim_without_lease`

Same content, host-specific JSON envelopes — all adapters exit `0` with JSON (ADR-0012 corrected):

- **Claude Code Stop**: `{ "decision": "block", "reason": "<nextAgentInstruction>" }`. Claude continues with `reason` as next instruction. Capped by Claude Code's built-in 8-consecutive-block safety.
- **Cursor stop**: `{ "followup_message": "<nextAgentInstruction>" }`. Auto-submits as new user message. Capped by `loop_limit: 3` (lower than Cursor default of 5).
- **Codex Stop**: `{ "decision": "block", "reason": "<nextAgentInstruction>" }`. Codex creates a continuation prompt using `reason` as the prompt text.

`nextAgentInstruction` is always: "Run `agentguard done --finalize --json`. If it fails, follow the diagnostic instructions before claiming completion again."

### AgentGuard-owned loop budget

In addition to host caps, AgentGuard tracks its own loop budget per session (default 3 blocks per diagnostic hash). When exhausted, `CompletionClassifier` returns `already_looping` and the `classify_stop` event records `loopBudget: { state: "exhausted", diagnosticHash: "..." }` — a field, not a separate `loop_budget_exhausted` event.

### Completion-claim detector

Deterministic pattern matcher with negative guards, configurable in `policy.completionClaims`. Default patterns: `done`, `complete(d)?`, `ready for review`, `implemented`, `fixed`, `shipped`, `all set`, `landed`. Negative guards: `not (done|complete)`, `almost (done|complete)`, `partially (done|complete)`, anything inside fenced code blocks.

If Issue 00's spike confirms regex in Zero v0.1.3, the matcher is regex-based; if not, the matcher is the same structured matcher form as command and path rules (literal substrings + word boundaries + named patterns). Either way the **interface** (`(message, policy.completionClaims) → boolean`) is unchanged.

Tunable via `policy.completionClaims.patterns` and `policy.completionClaims.negativeGuards`. The detector is allowed to miss soft claims. It must not falsely block ordinary non-claiming turn endings.

### Codex hooks correction

Earlier ADRs (0005, 0006) treated Codex as having no lifecycle hooks. This was wrong: Codex's hook system supports `SessionStart`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `UserPromptSubmit`, `Stop`. Only `type: "command"` handlers run today. Codex `Stop` supports `decision: "block"` + `reason` — same shape as Claude Code. This ADR uses `Stop` hooks for lease enforcement on Codex (Milestone 2 per ADR-0011).

## Consequences

Positive:

- The Stop hook becomes a thin, deterministic enforcement of a single invariant.
- "Are we done?" is a ledger lookup, not a prose interpretation.
- Same lease logic ships across all three hosts; only the JSON envelope differs.
- The brand promise holds: AgentGuard is deterministic where agents are probabilistic.
- Lease expiry caps the danger window: stale leases cannot vouch for a repo state that has drifted.
- AgentGuard's own loop budget plus diagnostic-hash dedupe prevents host cap behavior from leaking into the product.
- Per ADR-0002 amended, the ledger taxonomy stays clean: lease state, loop budget, bypass findings are **fields** on the canonical events, not separate event types.

Negative:

- One more concept (lease) in the model. Mitigated by the fact that it replaces three muddled alternatives.
- `agentguard done` gains a `--finalize` mode. The default `done` stays planning-only; `--finalize` is the writer.
- The completion-claim detector is policy-tunable, which adds a small configuration surface.

## Alternatives considered

1. **Deterministic classifier returns `task_complete` based on prose.** Rejected — pattern matching cannot prove completion. False positives let stale repos be declared done.
2. **Prompt-hook LLM classification.** Rejected for MVP — violates the deterministic brand and adds model dependency to the most-fired hook event.
3. **Ship both.** Rejected — adds product surface before the invariant is clear.
4. **Lease without expiry.** Rejected — long-lived leases vouch for repo state that has drifted.
5. **Lease without diff-hash binding.** Rejected — any post-lease edit must invalidate the lease, which means the lease must be pinned to a state.

## References

- The fourth-approach insight came from a Pro consultation (this conversation's earlier turn on 2026-05-20).
- ADR-0001 — severity / action / mode.
- ADR-0002 (amended) — **seven event types**: six observation (`session_start`, `risk`, `verify`, `done`, `pack`, `classify_stop`) + one resolution (`resolution`). Lease records, bypass findings, and loop budget are **fields** on observation events; approvals + diagnostic acks + bypass acks are `resolution` events.
- ADR-0004 — verify is plan-only; the lease depends on recorded check results.
- ADR-0006 — three native plugins; same lease logic ships in all three Stop hooks with host-specific JSON envelopes.
- ADR-0010 — check-result attestation. `enforce` mode requires `hook-observed` or `ci-observed`.
- ADR-0012 (corrected) — host adapter exit-code mapping. Adapters exit `0` with JSON.
- `https://developers.openai.com/codex/hooks` — confirms Codex `Stop` hook exists with `decision: "block"` + `reason`.
- `CONTEXT.md` — Completion lease section.
- `.scratch/agentguard/issues/11-done-completion-gate.md`, `13-hooks-claude-code.md`, `14-hooks-codex.md`, `15-hooks-cursor.md`, `21-completion-lease.md` — implementations.
