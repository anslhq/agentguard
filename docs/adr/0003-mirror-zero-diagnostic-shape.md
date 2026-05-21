# ADR 0003: AgentGuard diagnostics mirror Zero's diagnostic shape

Status: Accepted
Date: 2026-05-20

## Context

AgentGuard's PRD calls for stable diagnostic codes, structured JSON output, and machine-readable repair metadata. Zero 0.1.3 already ships a production-ready diagnostic schema with the same goals:

- `code`, `message`, `path`, `line`, `column`, `length`
- `expected` / `actual` structured mismatch facts
- `help` (concise next action)
- `fixSafety` taxonomy: `format-only | behavior-preserving | api-changing | target-changing | requires-human-review`
- `repair` with `id` + `summary`
- `related` spans/facts

Source: `zero skills get zero-diagnostics`.

AgentGuard's implementation is planned to use Zero for its core deterministic modules (see ADR-0004, forthcoming). Mirroring Zero's diagnostic shape exactly:

1. Lets AgentGuard reuse `std.json` writers and Zero's existing diagnostic-printing patterns.
2. Lets downstream tools (agents, CI parsers, IDE integrations) use one parser for both Zero diagnostics and AgentGuard diagnostics.
3. Inherits a `fixSafety` taxonomy that has already been thought through, instead of inventing one.

## Decision

AgentGuard diagnostics use the exact field set and `fixSafety` enum from Zero's diagnostic shape:

- Fields: `code, severity, message, path, line, column, length, expected, actual, help, fixSafety, repair, related`.
- `severity` is AgentGuard-specific (Zero diagnostics don't carry severity; they encode it in the code itself). AgentGuard uses `info | warn | error | critical` as defined in ADR-0001.
- `fixSafety` enum is fixed to Zero's five values; no AgentGuard-specific additions in MVP.
- `repair` adds an optional `alternatives` array (AgentGuard supports multi-path repairs; see "Next agent instruction" in CONTEXT.md).

The result envelope still carries a top-level `nextAgentInstruction` that may aggregate or expand on the per-diagnostic `help` fields.

## Consequences

Positive:

- One parser for Zero + AgentGuard diagnostics.
- AgentGuard inherits Zero's well-designed `fixSafety` enum without bikeshedding.
- Future tooling (LSP, IDE plugins) can treat the two as one stream.

Negative:

- AgentGuard's `severity` field has no Zero counterpart, so it's a slight extension. Acceptable — Zero encodes severity in the code; AgentGuard wants severity as a first-class field for severity → action mapping (ADR-0001).
- If Zero changes its diagnostic shape in 1.0, AgentGuard must follow or fork. Risk accepted — Zero's diagnostics are stable in v0.1.3 and the agent-first design intent is unlikely to reverse.

## Alternatives considered

1. **Invent a new shape.** Rejected — duplicate work, worse interop.
2. **Mirror only field names but invent a different fixSafety enum.** Rejected — `format-only / behavior-preserving / api-changing / target-changing / requires-human-review` is well-thought-out and matches AgentGuard's needs without modification.

## References

- `zero skills get zero-diagnostics`
- `CONTEXT.md` — Diagnostic section
- ADR-0001 — severity / action / mode split (defines AgentGuard's severity vocabulary)
