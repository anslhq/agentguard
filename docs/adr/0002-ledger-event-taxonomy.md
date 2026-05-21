# ADR 0002: One ledger event per AgentGuard invocation

Status: Accepted
Date: 2026-05-20

## Context

<!-- docs-lint:allow-superseded-start -->
Initial PRD listed approximately fourteen fine-grained ledger event types:

```
session_start, risk_check, command_allowed, command_denied,
file_change_detected, verify_started, verify_finished,
check_failed, check_passed, context_pack_created,
completion_blocked, completion_allowed, policy_changed, bypass_detected
```

Several pairs overlapped: `risk_check` produced `command_allowed`/`command_denied`; `verify_started`/`verify_finished` bracketed `check_failed`/`check_passed`; `policy_changed` duplicated information already carried by a `POL001` diagnostic inside a verify event.
<!-- docs-lint:allow-superseded-end -->

This created two problems:

1. **Query complexity.** Answering "what happened in this session?" required joining multiple event types and reconstructing temporal relationships.
<!-- docs-lint:allow-superseded-start -->
2. **Schema drift risk.** Independent event schemas meant a `verify_finished` could disagree with the sum of its `check_failed`/`check_passed` children.
<!-- docs-lint:allow-superseded-end -->

## Decision

The taxonomy is **one event per AgentGuard invocation**. After two amendments (post-ADR-0008 in v1, post-v2-review here), it lands on **six observation events + one resolution event = seven total**:

```
Observation events (one per AgentGuard observation call):
  session_start
  risk
  verify
  done
  pack
  classify_stop

Resolution event (one per AgentGuard resolution call):
  resolution
```

History:
- v1: 14 fine-grained events.
- v1 of this ADR: collapsed to 6 observation events.
- v1 amendment (after ADR-0008): added `classify_stop` → 6 observation events.
- v2 amendment (this — after the v2 pre-implementation review): added `resolution` for `agentguard approve`, `agentguard ack`, `agentguard ack-bypass` invocations, because forcing them onto `risk`/`verify` events muddled both shapes.

Each event still carries the full result envelope produced by that invocation, plus invocation-specific fields.

### Field mappings (full schema in CONTEXT.md)

- **Lease records** live as a `lease` field on `done` events when `done.leaseDecision == "issued"`. `LeaseStore` finds the lease by walking back to the most recent such `done` event.
- **Loop-budget state** lives as a `loopBudget` field on `classify_stop` events.
- **Bypass findings** live as a `bypassFindings[]` array on the next `verify` or `done` event after the finding is observed.
- **Approvals** are now `resolution` events with `kind: "approval"`, `targetId: <approvalId>`, and `scope: {command, cwd}` + `ttlSeconds`.
- **Diagnostic acknowledgments** are `resolution` events with `kind: "diagnostic_ack"`, `targetId: "<CODE>"`.
- **Bypass acknowledgments** are `resolution` events with `kind: "bypass_ack"`, `targetId: "<bypass-finding-id>"`.

### Why `resolution` is a real seventh event type

The v2 review pointed out that `approve`, `ack`, and `ack-bypass` are genuine AgentGuard invocations with their own inputs (a target id), outputs (an acceptance/denial result), and durable effects (lease unblocking). Field-stuffing them onto `risk` events created two problems: it muddled the meaning of `risk` (now writes "I evaluated a command" *and* "I recorded an approval"), and it broke the "one row per invocation" invariant when the user ran `approve` without an antecedent `risk` in the same session.

Adding `resolution` keeps each invocation cleanly typed. The "exactly six" rule was a stylistic constraint that started to hurt the design; the substantive rule — "one event per invocation, no out-of-band events" — is preserved.

## Consequences

Positive:

- One row per AgentGuard call. Trivial mental model.
- "What happened in this session?" is a flat scan.
- Each row is self-contained for replay, analytics, and context-pack input.
- Event schema and result-envelope schema are one schema.

Negative:

- Rows are larger. A verify with many diagnostics produces a ~few-KB row instead of several tiny rows. JSONL handles this fine; not a real performance concern at expected scale.
- Loses the ability to log "verify started, still running" intermediate state. Acceptable — AgentGuard verifies are short and synchronous; failures during a verify produce one final row with `ok: false` and the partial results.

## Alternatives considered

1. **Keep ~14 fine-grained event types.** Maximum granularity, but creates the query/schema-drift problems above.
2. **Hybrid: one event per call but emit per-check sub-events nested.** Considered briefly. Adds a sub-event concept that complicates flat-file JSONL parsing without enough benefit.

## References

- `CONTEXT.md` — Ledger terms section.
- `.scratch/agentguard/PRD.md` — section "Ledger event types" (will be updated to reference this ADR).
- `.scratch/agentguard/issues/11-done-completion-gate.md`, `07-verify-base.md`, `05-risk-base.md` — issues that emit these events.
