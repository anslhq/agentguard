# ADR 0012: Output size caps and exit-code contract

Status: Accepted
Date: 2026-05-20

## Context

Two pre-implementation review findings (GPT, 2026-05-20) flagged missing contracts that would otherwise be invented inconsistently across modules:

1. **Output size caps.** Hook outputs can break agents if they grow unbounded. `additionalContext`, `diagnostics[]`, and context packs need hard caps.
2. **Exit-code contract.** Git hooks and CI rely on exit codes; without a published contract, behavior would be invented per subcommand.

## Decision

### Output size caps

A pure module `OutputCapper` runs last on every emitted JSON result. Caps:

- **Top-level result envelope:** 64 KiB total.
- **`nextAgentInstruction`:** 4 KiB.
- **`additionalContext`** (returned to host hooks): 8 KiB.
- **`diagnostics[]`:** soft cap of 50 entries; overflow summarized as `truncated: { droppedCount: N, droppedSeverityBuckets: { error: N, warn: N, ... } }`.
- **`checkResults[]`:** no soft cap (the number is bounded by `checks.json`).
- **Context pack** (`agentguard pack`): the user-supplied `--budget` is authoritative; `OutputCapper` enforces the envelope cap on top of that.

When `OutputCapper` truncates, the result envelope retains `ok`, `nextAgentInstruction`, and the most severe diagnostics first. The cap is observable: `meta: { truncated: true, originalSize: ..., cappedSize: ... }`.

### Exit-code contract

| Code | Meaning |
|---|---|
| `0` | Success. Operation completed normally. Includes `verify` planning with checks not yet run. |
| `1` | Recoverable error. Operation failed for a reason captured in `diagnostics`. Stdout is valid JSON. |
| `2` | Blocking finding in `enforce` mode. Any `action == "block"` on the result. Stdout is valid JSON. |
| `3` | Confirmation required (`action == "confirm"`). User should approve via `agentguard approve`. Stdout is valid JSON. |
| `64` | Usage error (bad flag, unknown subcommand). Plain text on stderr; no JSON guarantee. |
| `70` | Internal error (panic, unwritable ledger, corrupted policy). Stderr describes the error; stdout JSON may be partial. |

### Host adapter exit codes (corrected — GPT review v2 #1)

**All three hosts process hook JSON only on exit `0`.** Claude Code, Cursor, and Codex docs all say: exit `0` + JSON on stdout is the in-band decision channel; exit `2` + stderr is a separate blocking-error fallback where stdout JSON is ignored. Earlier drafts of this ADR got that backwards.

Adapters running with `--host <name>` therefore:

- **Always exit `0` on a successful hook execution** (regardless of whether AgentGuard's decision is allow / log / notify / confirm / block). The JSON body carries the host-shaped decision.
- **Exit `2` + stderr** only as a *fallback* when the adapter cannot emit valid JSON (genuine internal error, equivalent to CLI exit `70`).

Per-host JSON payloads:

- **Claude Code:** `hookSpecificOutput.permissionDecision: "allow" | "deny" | "ask"` (PreToolUse) or top-level `decision: "block"` + `reason` (`Stop`/`SubagentStop`). `confirm` → `permissionDecision: "ask"` with `permissionDecisionReason` (shown to user) plus `additionalContext` (shown to the agent — see cleanup #4).
- **Cursor:** `permission: "allow" | "deny" | "ask"` + `user_message`/`agent_message`. `confirm` → `permission: "ask"`.
- **Codex:** `permissionDecision: "allow" | "deny"` (no `"ask"`). `confirm` → `permissionDecision: "deny"` + `permissionDecisionReason` telling the agent to seek approval and retry. For `Stop`, all hosts use `decision: "block"` + `reason`.

The standalone CLI exit-code contract (the table above) still governs *direct* CLI use (Git hooks, CI, ad-hoc terminal). Adapters running under a hook never propagate `2`/`3` to the host. The binary has two output modes:

- Standalone (no `--host`): CLI exit codes 0/1/2/3/64/70 apply; stdout is the AgentGuard JSON envelope.
- Hook adapter (`--host <name>`): exit `0` with host-shaped JSON on success; exit `2` + stderr is a defensive fallback for internal errors only.

## Consequences

Positive:

- Hook payloads have a known size ceiling. No surprise truncation by hosts.
- Git hooks and CI have a clear contract for "is this a block?" — exit code `2`.
- Confirmation flow is distinguishable from block in standalone CLI usage (exit `3`).
- `OutputCapper` is a single tested module; truncation behavior is consistent.

Negative:

- Adapters carry a small mapping table (3 entries each). Acceptable.
- Confirmation collapses to "deny + retry-after-approval" on Codex. Acceptable — Codex's `ask` is unsupported (see ADR-0011 reference).
- Two output modes (standalone vs adapter) in one binary. Acceptable — the `--host` flag clearly partitions them.

## Alternatives considered

1. **No size cap; rely on hosts to truncate.** Rejected — different hosts truncate differently, and AgentGuard would lose control of which diagnostics get dropped.
2. **Single exit-code "1 = anything bad."** Rejected — Git hooks and CI need to distinguish block from soft fail.
3. **Cap by `diagnostics.length` not bytes.** Rejected — diagnostics can be wildly different sizes; byte caps are the safer ceiling.

## References

- CONTEXT.md — "Result envelope size cap" and "Exit-code contract" sections.
- `.scratch/agentguard/issues/01-cli-bootstrap.md` — owns the exit-code contract.
- `.scratch/agentguard/issues/25-output-caps.md` — owns the `OutputCapper` module.
