# AgentGuard Domain Glossary

This file is the canonical vocabulary for AgentGuard. Terms here have precise meanings; do not drift to synonyms.

This is a glossary, not a spec. Implementation details belong in PRDs, issues, or ADRs.

<!-- docs-lint:allow-superseded-start -->
Do not use these terms anywhere in the codebase or docs (they were superseded by ADRs): `audit` (as a mode name), `require_confirmation`, `deny` (as an action — use `block`), `risk_check`, `command_allowed`, `command_denied`, `verify_started`, `verify_finished`, `check_failed`, `check_passed`, `completion_blocked`, `completion_allowed`, `policy_changed` (as event name), `file_change_detected`, `context_pack_created`, `lease_issued` (as event name — leases are records inside `done` events per ADR-0002), `loop_budget_exhausted` (as event name — field on `classify_stop`), `bypass_detected` (as event name — `bypassFindings[]` field per ADR-0002), `bypass_acknowledged` (as event name — `resolution` event with `kind: "bypass_ack"` per ADR-0002 amended), `approval_granted` (as event name — `resolution` event with `kind: "approval"`).
<!-- docs-lint:allow-superseded-end -->

## Architecture vocabulary

These are the words AgentGuard uses when talking about its own structure. Do not substitute "component," "service," "API," "boundary."

- **Module** — anything with an interface and an implementation (function, package, slice).
- **Interface** — everything a caller must know to use the module: types, invariants, error modes, ordering, configuration. Not just the type signature.
- **Implementation** — the code inside the module.
- **Depth** — leverage at the interface. A **deep** module has a large amount of behavior behind a small interface. A **shallow** module has an interface nearly as complex as its implementation.
- **Seam** — where an interface lives; a place behavior can be altered without editing in place.
- **Adapter** — a concrete thing satisfying an interface at a seam.
- **Leverage** — what callers get from depth.
- **Locality** — what maintainers get from depth: change and bugs concentrate in one place.

Principles:

- **Deletion test.** If deleting a module makes complexity vanish, the module was a pass-through. If deleting it makes complexity reappear across N callers, it was earning its keep.
- **The interface is the test surface.** Tests cross the same seam as callers.
- **One adapter = hypothetical seam. Two adapters = real seam.** Don't introduce a seam unless something actually varies across it.

## Core terms

### Session

A contiguous span of agent activity in one repo, identified by `sessionId`.

Session-id sourcing, in order of preference:

1. **Host-supplied.** Claude Code's `SessionStart` payload provides a `session_id`; AgentGuard adopts it. Cursor `sessionStart` provides `session_id`; AgentGuard adopts it. Codex's `Stop` and other hooks provide a `turn_id`; AgentGuard derives a stable session id by hashing the host process's parent process group + first-seen-turn timestamp until a richer Codex session signal exists.
2. **Inactivity-timeout.** When no host-supplied id is present (CLI, MCP, ad-hoc), AgentGuard generates a `sessionId` on the first invocation and keeps it alive for **30 minutes of inactivity** (configurable via `policy.session.inactivityMinutes`).
3. **Explicit.** `agentguard session start` and `agentguard session end` override both.

A session spans many turns and may span many tasks. Process-tree derivation is a last resort.

### Turn

One agent response cycle. Host-specific (Claude Code: "turn"; Cursor: "step"; Codex: "turn"). Hook events of family `Stop` fire once per turn.

### Task

The developer-intent unit of work ("add login validation"). One task may span many turns and many sessions. AgentGuard does not natively know task boundaries. Task completion is inferred from explicit `agentguard done --finalize` calls; the Stop hook only enforces that *claims* of completion are backed by a valid lease (see "Completion lease").

### Event

A single record in `.agentguard/ledger.jsonl`. **One event per AgentGuard invocation**, no out-of-band events. Bypass findings observed between invocations are written as fields on the next invocation's event (not as their own event). See "Ledger" below for the seven-event taxonomy.

### Loop

Marketing and architecture term only. Refers to the abstract control flow `propose → classify → verify → instruct → record`. Not a runtime object; do not use "loop" in code or schemas.

## Decision vocabulary

AgentGuard separates *what a rule found* from *what AgentGuard does about it*. Do not collapse these.

### Severity

Intrinsic to a rule. Describes the certainty and seriousness of a finding.

- `info` — observation, no concern.
- `warn` — worth surfacing; ambiguous or low blast radius.
- `error` — definitely a problem; should be fixed before proceeding.
- `critical` — destructive or irreversible; must not happen without explicit approval.

### Action

What AgentGuard does in response. Derived from severity + policy mode (with per-rule overrides allowed).

- `allow` — proceed silently.
- `log` — write to ledger, no user-visible output.
- `notify` — write to ledger + surface diagnostic in the result envelope.
- `confirm` — require explicit human approval (see "Approval" below).
- `block` — refuse the operation (return non-zero, deny the hook).

### Mode

Repo-wide policy posture. Set in `policy.json`. Default for new repos: `observe`.

- `observe` — AgentGuard watches and records, never blocks. Severity → action softens: critical → notify, error → notify, warn → log + notify, info → log.
- `enforce` — AgentGuard gates. Severity → action: critical → block, error → confirm, warn → notify, info → log.

A rule may set `actionOverride` to opt into a stronger action regardless of mode (e.g. ledger tampering should `block` even in `observe`).

`nextAgentInstruction` is generated when `action ∈ {notify, confirm, block}`. Never on `allow` or `log`.

## Approval

`confirm` is durable only when an explicit approval exists. Approvals are written as their own `resolution` ledger event (ADR-0002 amended — seven event types):

```
{
  "event": "resolution",
  "kind": "approval",
  "targetId": "ap_<sha>",
  "decision": "approved" | "denied",
  "approver": "<user identity or 'agent-self' (never honored in enforce)>",
  "scope": { "command": "<verbatim>", "cwd": "<path>" },
  "ttlSeconds": 600,
  "reason": "<free-text>",
  "resolvedAt": "<rfc3339>"
}
```

Lifecycle:

1. `agentguard risk --command "..."` returns `action: "confirm"` with `approvalId: "ap_<sha>"` in the result envelope and as `risk.approvalId` in the ledger.
2. The human runs `agentguard approve <approvalId> [--deny] [--reason "..."] --json`. AgentGuard writes a `resolution` event with `kind: "approval"`.
3. The next `agentguard risk` call with the same `{command, cwd}` looks up `resolution` events with matching `targetId.scope`. If an unexpired `decision: "approved"` is found, the new `risk` event has `operationOutcome: "confirmed"` and `action: "allow"`. If `decision: "denied"`, `operationOutcome: "denied-by-policy"` and `action: "block"`.
4. After `ttlSeconds`, the approval expires. Re-requesting `confirm` requires a fresh approval.

`agent-self` approvals: in `enforce` mode, `done --finalize` denies a lease when any `confirm` operation in the session was satisfied only by `resolution.approver == "agent-self"`. The agent cannot self-approve risky operations and then claim completion.

## Acknowledgments

`agentguard ack <diagnostic-code> --reason "..."` and `agentguard ack-bypass <finding-id> --reason "..."` are also `resolution` events:

- `ack` → `kind: "diagnostic_ack"`, `targetId: "<CODE>"`.
- `ack-bypass` → `kind: "bypass_ack"`, `targetId: "<finding-id>"`.

Acknowledgments resolve unresolved completion blockers (CONTEXT.md "Completion lease"). They are recorded with the human's identity (never `agent-self` for `bypass_ack` in `enforce` mode) and a `reason` string visible in the ledger.

## Workspace terms

### Git root

The directory containing `.git` for the current repository. AgentGuard's default workspace boundary.

### Workspace roots

The set of directories AgentGuard considers in-scope. Defaults to `[git-root]`. Configurable via `policy.workspaceRoots` for multi-repo work. Commands targeting paths outside all workspace roots are **workspace escape** and trigger `CMD003`.

### Focus path

An optional narrower scope within a workspace root, for monorepo work. Set per-session (`agentguard session start --focus packages/web`) or in `policy.focusPath`. Edits and commands targeting paths inside a workspace root but outside the focus path produce **sensitive-out-of-focus** warnings (severity `warn`), not workspace escape.

### Workspace-managed files

Files that package managers or build tools modify on behalf of any subdirectory of a workspace (e.g. the root `pnpm-lock.yaml` in a pnpm workspace). `DiffClassifier` recognizes these and exempts them from focus-path warnings. Detected by `RepoProfile`.

### Diff hash

A deterministic hash that pins repo state for lease validity (see "Completion lease"). Includes:

- `git diff HEAD` (staged + unstaged changes against last commit).
- `git diff --cached HEAD` (staged-only changes).
- `git ls-files --others --exclude-standard` (untracked files) plus a SHA-256 of each untracked file's content. Files larger than `policy.diffHash.maxFileBytes` (default 1 MiB) are recorded as `(path, size, "oversize")` rather than hashed in full.

Concatenated and SHA-256'd with a leading version byte. Implementation detail of `LeaseStore`; the rule for callers is simply "the diff hash represents the full working tree at this moment."

## Feedback terms

### Diagnostic

A single finding produced by a rule or check. The shape mirrors Zero's diagnostic shape field-for-field, plus an AgentGuard `severity`:

- `code` — stable diagnostic code (`CMD002`, `DEP002`, etc.). Versioned, never reused.
- `severity` — `info | warn | error | critical` (AgentGuard-specific extension; see ADR-0003).
- `message` — short human summary.
- `path`, `line`, `column`, `length` — source span (path only when not file-bound).
- `expected`, `actual` — structured mismatch facts when applicable.
- `help` — concise next action (one line, distinct from the result-envelope's `nextAgentInstruction`).
- `fixSafety` — one of `format-only | behavior-preserving | api-changing | target-changing | requires-human-review` (taxonomy inherited from Zero).
- `repair` — optional `{ id, summary, alternatives? }`.
- `related` — extra spans or contextual facts.

Secret values are never present in `expected`, `actual`, or `related`.

### Repair

A concrete action that resolves a diagnostic. Has an `id`, a `summary` (one-line command or instruction), and optional `alternatives` when more than one path is valid.

### Next agent instruction

The text emitted in the result envelope's `nextAgentInstruction` field. Agent-targeted (written *to* the agent, not *about* the agent).

Style rules:
- **Prescriptive when there is one obviously-right path** ("Run `X`. Do not edit unrelated files. Then rerun `agentguard verify --json`.").
- **Goal-oriented when multiple paths are valid** ("Resolve the lockfile drift. Either run `X` or revert the change. Then rerun `agentguard verify --json`.").
- **Always names scope constraints** ("do not edit unrelated files", "fix only the reported errors").
- **Always ends with the next AgentGuard command** so the loop is self-terminating.

Emitted whenever `action ∈ {notify, confirm, block}`. Never on `allow` or `log`.

### Result envelope size cap

Every JSON-emitting command caps its top-level output at 64 KiB. Diagnostics beyond the cap are summarized as `truncated: { droppedCount: N, droppedSeverityBuckets: {...} }`. `nextAgentInstruction` is itself capped at 4 KiB. `additionalContext` returned to host hooks is capped at 8 KiB. The cap is enforced by `OutputCapper`, a pure module that runs last on every result.

## Ledger terms

### Ledger

The append-only JSONL file at `.agentguard/ledger.jsonl`. **One canonical event per AgentGuard invocation.** Out-of-band findings (e.g. a bypass observed between invocations) attach to the **next** invocation's event as a field, not as a separate event type. The only exception is `session_start`, which is written once at session boundary.

Each event carries the full result envelope it produced. The ledger is a faithful, replayable transcript of every AgentGuard interaction in the session.

### Event types

**Exactly seven.** Six observation events (one per AgentGuard observation call) + one resolution event (one per AgentGuard resolution call). Sub-states, lease writes, loop-budget facts, and bypass-detection findings are still **fields** on these events.

#### Observation events

| Event | Written by | Carries (notable fields beyond envelope) |
|---|---|---|
| `session_start` | first AgentGuard call in a new session | session metadata, host id |
| `risk` | `agentguard risk` | `command`, `cwd`, `action`, `operationOutcome` (one of `allowed`, `blocked`, `confirmed`, `denied-by-policy`, `pending-approval`), `approvalId?` (when action is `confirm`) |
| `verify` | `agentguard verify` (any mode) | `changedFiles`, `requiredChecks[]`, `checkResults[]` (each with `attestation`), `diagnostics`, `bypassFindings[]` |
| `done` | `agentguard done` (plan or finalize) | `mode: "plan" \| "finalize"`, `leaseDecision` (one of `none`, `issued`, `denied`, `invalid`), `lease?` (the lease record when `issued`), `blockers[]` |
| `pack` | `agentguard pack` | `budget`, `estimatedTokens`, `redactionReport` (counts only) |
| `classify_stop` | the Stop-hook adapter on any host | `host`, `messageClaim: bool`, `leaseState`, `decision` (one of `no_claim`, `claim_with_valid_lease`, `claim_without_lease`, `external_blocker`, `already_looping`, `aborted`), `loopBudget` |

#### Resolution event

| Event | Written by | Carries (notable fields beyond envelope) |
|---|---|---|
| `resolution` | `agentguard approve <id>`, `agentguard ack <code>`, `agentguard ack-bypass <id>` | `kind: "approval" \| "diagnostic_ack" \| "bypass_ack"`, `targetId` (the approval id, diagnostic code, or bypass-finding id being resolved), `decision: "approved" \| "denied" \| "acknowledged"`, `approver` (the actor — `user`, `agent-self`, or named identity), `reason` (free-text), `scope?` (for approvals: `{command, cwd}`), `ttlSeconds?` (for approvals), `resolvedAt` |

`agent-self` approvals are recorded but never honored in `enforce` mode (CONTEXT.md "Approval").

Notably:

- **No `lease_issued` event.** A lease is a record nested inside the `done` event when `leaseDecision == "issued"`. `LeaseStore` finds the most recent `done` event whose `leaseDecision == "issued"` and validates it.
<!-- docs-lint:allow-superseded-start -->
- **No `loop_budget_exhausted` event.** Loop budget state is a field on each `classify_stop` event.
- **No `bypass_detected` event.** Bypass findings are reported as `bypassFindings[]` on the next `verify` or `done` event. They carry a `confidence` (one of `strong`, `weak`) and a `kind` (see "Bypass findings" below).
- **No `bypass_acknowledged`, no `policy_changed`, no `approval_granted` events.** Approvals, diagnostic acknowledgments, and bypass acknowledgments are all `resolution` events.
<!-- docs-lint:allow-superseded-end -->

This preserves the "one row per AgentGuard call" model: every CLI invocation that writes to the ledger produces exactly one event. Observation calls write to one of the six observation event types; resolution calls (`approve`, `ack`, `ack-bypass`) write to the single `resolution` event type. Seven total.

## Rule vs check vs probe

Three distinct things. Do not conflate.

### Rule

A pattern-matching, pure evaluator defined in `policy.json` (and built-in rule modules). Examines a command, diff, file path, or content; produces a `Diagnostic` with a stable code (`CMD###`, `DEP###`, `CHG###`, `POL###`, `SEC###`, `CTX###`). Fast. Always runs.

Rule matchers are **structured**, not free-form regex (see ADR-0009 amendment). For commands, a rule has `{ firstToken, argsPattern? }` where `argsPattern` is a small declarative DSL (anchored substring, glob, optional captures). For diffs, a rule has `{ pathGlob, plus optional content fingerprint (literal substring or a small named pattern from the built-in set) }`. Built-in patterns include `aws-access-key-id`, `private-key-pem`, `github-token-classic`, `github-token-fine-grained`, and `high-entropy-string`. Pattern fingerprints are versioned with their own ids and updated only via ADR.

If full regex turns out to be needed in MVP, it ships as a Zero-side library or a documented shim (see ADR-0009).

### Check

A configured shell-command execution defined in `checks.json`. Has an `id`, a `command`, and `requiredFor` globs.

The verification planner selects required checks from changed files. AgentGuard does not execute checks (ADR-0004). The agent runs them; AgentGuard records the result via `verify --record-pass` / `--record-fail` with provenance (see "Attestation").

Examples: `typecheck` ↔ `pnpm typecheck`; `unit-tests` ↔ `pnpm test`.

### Probe

An internal health test inside `agentguard doctor`. Tests environment, install, and config integrity. Read-only. Not user-configurable.

### Verify result fields

A `verify` event carries two separate arrays:

- `diagnostics: Diagnostic[]` — findings from **rules**.
- `checkResults: CheckResult[]` — status of planned checks, each with an `attestation` field (see below).

## Attestation

Recorded check results are **only as trustworthy as their source**. Every `CheckResult` carries:

- `state` ∈ `not-run | passed-current | passed-stale | failed-current | failed-stale | unknown`.
- `attestation` ∈
  - `hook-observed` — the hook adapter (Claude Code `PostToolUse` matcher `Bash`, Codex `PostToolUse` matcher `Bash`, Cursor `afterShellExecution`) observed the user-configured check command running and captured its exit code.
  - `ci-observed` — the GitHub Actions workflow ran the check and recorded the result.
  - `manual` — a human or agent called `agentguard verify --record-pass <id>` directly, without an observed run.
  - `unknown` — legacy or unsourced records (migration only).
- `attestationDetails?` — for `hook-observed`/`ci-observed`, includes the command line observed and exit code; for `manual`, includes the actor (`user`, `agent-self`, or named identity).

**Mode-dependent acceptance:**

- In `observe` mode, all attestation kinds count toward a lease.
- In `enforce` mode, **only** `hook-observed` and `ci-observed` count toward a lease. `manual` attestations are recorded but do not enable a lease. This is the answer to the lease-forgery risk (GPT review #9).

`hook-observed` attestation is the default path in any host plugin: the agent runs the user's check command and the adapter intercepts the exit code. Manual recording remains for solo developers who explicitly want it.

## Execution model

AgentGuard never executes user-configured checks (ADR-0004).

- `agentguard verify --json` outputs a **plan**: which checks are required for the current diff and their last-recorded state.
- `agentguard verify --record-pass <check-id> [--source hook-observed|ci-observed|manual]` and `--record-fail <check-id> [--exit-code N] [--source ...]` are the only ways to update check state. `--source` defaults to `manual`; hook adapters pass `--source hook-observed`; CI passes `--source ci-observed`.
- Recorded state lives in `.agentguard/cache/check-state.json`, keyed by `(checkId, diffHash)`. Edits demote `*-current` to `*-stale`.

Probes (`doctor`) and rules (`verify`/`risk`) run inside AgentGuard. Only **checks** are deferred to the agent.

## Completion lease

**Core invariant: a task-completion claim is allowed to end the turn only when there is a valid completion lease.**

The Stop hook does *not* decide whether the task is semantically complete. `agentguard done --finalize --json` decides that. The Stop hook only enforces that completion *claims* are backed by a fresh lease.

### What a lease is

A lease is a **record nested inside a `done` event** when `leaseDecision == "issued"`. Shape:

```
{
  "id": "lease_<sha>",
  "sessionId": "...",
  "issuedAt": "<rfc3339>",
  "diffHash": "<hash, see 'Diff hash'>",
  "expiresAt": "<issuedAt + 10 minutes>",
  "checksAttested": [{ "id": "typecheck", "state": "passed-current", "attestation": "hook-observed" }, ...]
}
```

`LeaseStore` finds the lease by walking the ledger backward to the most recent `done` event with `leaseDecision == "issued"`.

### When `done --finalize` issues a lease

All of these must hold:

- Every required check for the current diff hash is recorded `passed-current` **with an attestation acceptable for the current policy mode** (see "Attestation").
- No **unresolved** completion blockers from earlier events:
  - A blocker is **resolved** if the most recent `risk` event that produced it had `operationOutcome ∈ {blocked, denied-by-policy}` (AgentGuard worked; nothing leaked).
  - A blocker is **unresolved** if the operation actually proceeded (`operationOutcome == "allowed"` or `"confirmed"`) and the diagnostic is `error` or `critical` and has not been explicitly acknowledged via `agentguard ack <diagnostic-code>`.
- No unresolved `bypassFindings` since the last verify (resolved via `agentguard ack-bypass <finding-id>`).
- Policy was not modified since the last verify (no unaddressed `POL001`).

### When a lease is invalid

- New diff (any edit that changes the diff hash).
- New `bypassFindings` with `confidence: strong` since `issuedAt`.
- New `POL001` since `issuedAt`.
- New `failed-current` check result since `issuedAt`.
- `expiresAt` reached.

Leases are not extended. The agent must re-run `done --finalize` to get a fresh one.

### Stop hook behavior

The Stop hook runs `CompletionClassifier` (see Issue 21) and acts on its decision:

```
CompletionDecision ∈ {
  no_claim,                  // turn ends normally
  claim_with_valid_lease,    // turn ends normally
  claim_without_lease,       // BLOCK; reason = nextAgentInstruction
  external_blocker,          // turn ends normally (host signaled in-flight work; optional, Claude only today)
  already_looping,           // turn ends normally + log (AgentGuard loop budget exhausted)
  aborted                    // turn ends normally (host status: aborted | error)
}
```

`task_complete` is deliberately not a return value. The classifier does not infer task completion from prose — only the lease proves it.

**`external_blocker`** is **optional** and only set when the host payload actually carries the signal. Claude Code's documented Stop payload may include `background_tasks[]` and `session_crons[]` in some versions; if those fields are absent or unrecognized, `CompletionClassifier` ignores them and falls through to the standard claim/lease check. Adapters never fail parsing on missing optional fields.

### Completion-claim detector

Deterministic pattern matcher with negative guards, configurable in `policy.completionClaims`. The matcher form (regex or structured) is resolved by Issue 00's Zero spike (ADR-0009 conditional): outcome A enables full regex; outcomes B/C use structured matchers — anchored literal patterns with word boundaries plus a small named-pattern registry. The default patterns below work in either form.

Default patterns (case-insensitive, word-boundary anchored): `done`, `complete(d)?`, `ready for review`, `implemented`, `fixed`, `shipped`, `all set`, `landed`.

Negative guards (suppress the claim if matched in proximity): `not (done|complete)`, `almost (done|complete)`, `partially (done|complete)`, anything inside fenced code blocks.

Tunable via `policy.completionClaims.patterns` and `policy.completionClaims.negativeGuards`. The detector is allowed to miss soft claims. It must not falsely block ordinary non-claiming turn endings.

## Host integration terms

### Host

The tool that invokes AgentGuard. AgentGuard ships **one native plugin per host** — no cross-host fallback. Each host gets its native distribution unit. Hosts ship in two milestones per ADR-0011:

**Milestone 1 (MVP first proof point):**

- **Claude Code** — **Claude Code plugin** (`.claude-plugin/plugin.json`). M1 wires `PreToolUse` (`permissionDecision`, `updatedInput`, `additionalContext`), `PostToolUse` (`additionalContext` to feed verify results back to Claude; Bash matcher for `record-from-bash` pass), `PostToolUseFailure` (Bash matcher for `record-from-bash` fail), `SessionStart`, `Stop` (`decision: "block"` + `reason` to re-prompt with `nextAgentInstruction`), `SubagentStop`. **`UserPromptSubmit` is unwired/no-op in M1** — deferred to M2 with `pack`. `monitors/monitors.json` is also **out of MVP** (the feature is marked experimental in Claude Code's own docs); deferred to Milestone 2.
- **Git** — `pre-commit` and `pre-push` (delegated to Husky / Lefthook when present, plain `.git/hooks/` otherwise). Plan-only; no `--run` flag (ADR-0004).
- **GitHub Actions** — `.github/workflows/agentguard.yml` running in `--ci` mode. CI is the canonical authoritative gate.

**Milestone 2:**

- **Cursor** — Cursor plugin (`.cursor-plugin/plugin.json`) with `beforeShellExecution`, `afterShellExecution`, `beforeReadFile`, `afterFileEdit`, `beforeMCPExecution`, `afterMCPExecution`, `beforeSubmitPrompt`, `sessionStart`, `sessionEnd`, `stop` (`followup_message`), `workspaceOpen`.
- **Codex** — Codex artifacts (skill + `.codex/hooks.json` + `AGENTS.md` snippet). `permissionDecision: "ask"` is **not used** in Codex (unsupported); `confirm` actions map to `deny` with an instruction telling the agent to seek approval before retrying. Codex hook coverage of shell calls is incomplete in current Codex versions, so AgentGuard claims **best-effort** enforcement on Codex, not guaranteed.

Each plugin is a separate top-level directory in the AgentGuard repo (`plugins/claude-code/`, `plugins/cursor/`, `plugins/codex/`). They share nothing at install time. They share only the underlying `agentguard` binary and the core modules behind it.

### Action → host response mapping

Per ADR-0001, with host-specific quirks:

| Action | Claude Code | Cursor | Codex |
|---|---|---|---|
| `allow` / `log` | `permissionDecision: "allow"` | `permission: "allow"` | `permissionDecision: "allow"` |
| `notify` | `permissionDecision: "allow"` + `additionalContext` | `permission: "allow"` + `agent_message` | `permissionDecision: "allow"` + `additionalContext` |
| `confirm` | `permissionDecision: "ask"` + `permissionDecisionReason` | `permission: "ask"` + `user_message` | `permissionDecision: "deny"` + `permissionDecisionReason` (Codex: "ask" is unsupported; deny with retry-after-approval instruction) |
| `block` | `permissionDecision: "deny"` + `permissionDecisionReason` | `permission: "deny"` + `user_message` | `permissionDecision: "deny"` + `permissionDecisionReason` |

### Adapter

Host-specific glue: parses the host's hook payload, calls the AgentGuard core, formats the host-expected response. Each adapter is thin, versioned independently, and lives outside the core modules. `HostPayloadFixtures` (Issue 22) capture real host payloads as committed test inputs.

### Re-prompt loop

All three hosts support a re-prompt loop where the Stop hook refuses to let the agent finish and supplies the next instruction text:

- **Claude Code** `Stop`: `{ "decision": "block", "reason": "<text>" }`. Capped by host's built-in 8-consecutive-block safety.
- **Cursor** `stop`: `{ "followup_message": "<text>" }`. Capped by `loop_limit: 3` (AgentGuard-owned, lower than Cursor's default of 5).
- **Codex** `Stop`: `{ "decision": "block", "reason": "<text>" }`. Codex creates a continuation prompt using `reason` as the prompt text.

AgentGuard also enforces its own loop budget (default 3 blocks per diagnostic-hash per session) regardless of host caps. When exhausted, `CompletionClassifier` returns `already_looping` and the event records `loopBudget: { state: "exhausted", diagnosticHash: "..." }`.

## Bypass findings

A **bypass finding** is a fact attached to the next `verify` or `done` event (no dedicated event type). Schema:

```
{
  "id": "byp_<sha>",
  "kind": "verify_likely_skipped" | "env_bypass_observed" | "policy_edit_in_session" | "hook_config_edit" | "ledger_state_mismatch" | "protected_path_edit",
  "confidence": "strong" | "weak",
  "evidence": { ... },
  "observedAt": "<rfc3339>"
}
```

| Kind | Confidence | Detection |
|---|---|---|
| `env_bypass_observed` | strong | Pre-commit hook ran with `HUSKY=0`, `SKIP=*`, or similar — env is captured by the hook script itself. |
| `policy_edit_in_session` | strong | `.agentguard/policy.json` or `.agentguard/checks.json` modified during an open session. |
| `hook_config_edit` | strong | `.husky/`, `.lefthook.yml`, `.claude/settings.json`, `.cursor/hooks.json`, `.codex/hooks.json`, `.git/hooks/` modified during an open session. |
| `protected_path_edit` | strong | Edit to any path in `policy.protectedPaths`. |
| `ledger_state_mismatch` | strong (tamper-evident, **not** tamper-proof) | `.agentguard/cache/ledger-state.json` SHA disagrees with `.agentguard/ledger.jsonl` rolling hash. |
| `verify_likely_skipped` | weak | A commit landed on HEAD between AgentGuard invocations without a recorded `verify` event in the previous AgentGuard call. Could also be a merge, rebase, CI checkout, manual hook removal, or `--no-verify`. Reported honestly with `confidence: weak`. |

`weak` findings produce `warn` severity by default. `strong` findings produce `error` (in `observe` mode) or `critical`+`block` (in `enforce` mode). Ledger tampering is **tamper-evident**, not tamper-proof — if an attacker edits both `.agentguard/ledger.jsonl` and `.agentguard/cache/ledger-state.json` consistently, AgentGuard cannot detect it. Documented as a known limitation, not a security guarantee.

Acknowledgments are written as `resolution` events with `kind: "bypass_ack"` (per ADR-0002 amended). `LeaseStore` walks the ledger forward from each unresolved finding to find matching `resolution` events.

## Exit-code contract

Every `agentguard` subcommand follows a deterministic exit-code contract:

- `0` — success; the operation completed normally (including `verify` planning with checks not yet run).
- `1` — recoverable error; the operation failed for a reason captured in `diagnostics` (e.g. policy did not validate, repo not detected). Stdout is still valid JSON.
- `2` — blocking finding in `enforce` mode (any `action == "block"` on the result); the agent or host hook should refuse to proceed. Stdout is still valid JSON.
- `3` — confirmation required (`action == "confirm"`); the user should approve via `agentguard approve`. Stdout is still valid JSON.
- `64` — usage error (bad flag, unknown subcommand). Stdout is plain text on stderr; no JSON guarantee.
- `70` — internal error (panic, unwritable ledger, corrupted policy file). Stderr describes the error; stdout JSON may be partial.

**Host hook adapters always exit `0` and rely on host-shaped JSON on stdout to convey their decision** (ADR-0012 corrected). All three hosts process hook JSON only on exit `0`; exit `2`+stderr is reserved as a defensive fallback for internal errors only. The standalone exit-code contract above applies to direct CLI use (Git hooks, CI, terminal); adapters never propagate `2`/`3` to the host.

## Backward-compatibility note

<!-- docs-lint:allow-superseded-start -->
Earlier drafts of the PRD and ADRs used vocabulary now superseded:

- The action axis was `allow | audit | warn | require_confirmation | deny`; it is now severity (`info|warn|error|critical`) × action (`allow|log|notify|confirm|block`) × mode (`observe|enforce`). See ADR-0001.
- The ledger taxonomy had earlier-draft event names including `risk_check`, `command_allowed`, `command_denied`, `verify_started`, `verify_finished`, `check_failed`, `check_passed`, `completion_blocked`, `completion_allowed`, `file_change_detected`, `context_pack_created`. It then collapsed to six in ADR-0002, then collapsed to six observation + one resolution = seven in ADR-0002 amended (after the v2 review pointed out that approvals and acknowledgments needed their own event home, not field-stuffing).
- The implementation language plan was "Zero core + TypeScript adapters"; current direction is "all Zero" per the Issue 00 spike outcome (see ADR-0009 amended).
- `audit` (as a mode name) is removed; use `observe`. `require_confirmation` is removed; use `confirm`. `deny` (as an action) is removed; use `block`.
- "`bypass_detected`", "`lease_issued`", "`loop_budget_exhausted`", "`bypass_acknowledged`", "`policy_changed`", "`approval_granted`" are not event types. Bypass findings, lease records, and loop-budget state are fields on observation events; approvals and acknowledgments are `resolution` events.

If any file in the repo references the superseded vocabulary, it's a bug and must be fixed (the docs-lint check in `tooling/docs-lint` enforces this).
<!-- docs-lint:allow-superseded-end -->
