# ADR 0001: Split decision vocabulary into severity, action, and mode

Status: Accepted
Date: 2026-05-20

## Context

<!-- docs-lint:allow-superseded-start -->
Initial drafts of the AgentGuard PRD used a single five-level "decision" axis on every rule and command:

```
allow | audit | warn | require_confirmation | deny
```

The same vocabulary also named the repo-wide policy posture: `policy.json` had `mode: "audit" | "enforce"`.

This had two problems:

1. **Collision.** The word `audit` named both a rule outcome and a policy mode. "This rule is in audit" was ambiguous.
2. **Conflation of concerns.** The five-level axis mixed *what the rule found* with *what AgentGuard does about it*. A `deny`-severity rule in `audit` mode should log but not block — same finding, different action — and the single-axis model could not express this cleanly. Every rule had to encode mode-aware logic itself.
<!-- docs-lint:allow-superseded-end -->

## Decision

Split the vocabulary into three orthogonal axes:

- **Severity** (intrinsic to the rule): `info | warn | error | critical`.
- **Action** (what AgentGuard does): `allow | log | notify | confirm | block`.
- **Mode** (repo posture): `observe | enforce`.

Default severity → action mapping depends on mode:

| Severity | `observe` mode | `enforce` mode |
|---|---|---|
| info | log | log |
| warn | log + notify | notify |
| error | notify | confirm |
| critical | notify | block |

Rules may set `actionOverride` to opt into a stronger action regardless of mode (e.g. ledger tampering should `block` even in `observe`).

`nextAgentInstruction` is emitted whenever `action ∈ {notify, confirm, block}` — never on `allow` or `log`.

<!-- docs-lint:allow-superseded-start -->
Rename `policy.json` `mode: "audit"` to `mode: "observe"` to remove the collision with the rule-level vocabulary.
<!-- docs-lint:allow-superseded-end -->

## Consequences

Positive:

- `audit` no longer means two things.
- Rules declare a single intrinsic severity; mode-aware behavior is centralized in the policy engine's mapping function.
- The hook adapters have a clearer contract: `block` → host-blocking response; `confirm` → ask the user; `notify` → non-blocking diagnostic.
- The default mapping is one table; tests cover it once.

Negative:

<!-- docs-lint:allow-superseded-start -->
- One-time rename in every PRD, issue, schema, and code reference that used `audit | warn | require_confirmation | deny` or `mode: "audit"`.
- Documentation and external integrations must learn the three-axis model. Slightly more conceptual surface than a single axis.
<!-- docs-lint:allow-superseded-end -->

## Alternatives considered

1. **Keep the five-level decision axis.** Cheapest in tokens, but the `audit`/`audit` collision remains and every rule encodes mode-awareness.
2. **Split severity/action but keep mode `audit`/`enforce`.** Smaller rename, but leaves a vestigial naming clash with the `audit` rule outcome that no longer exists.
3. **Three-axis split with `monitor` instead of `observe` for the mode name.** Considered; `observe` reads better against `enforce` and is shorter.

## References

- `CONTEXT.md` — Decision vocabulary section.
- `.scratch/agentguard/PRD.md` — initial PRD (uses the old vocabulary; will be updated to reference this ADR).
