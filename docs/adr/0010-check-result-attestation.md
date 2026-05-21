# ADR 0010: Check results carry attestation, and `enforce` mode requires observed attestation

Status: Accepted
Date: 2026-05-20

## Context

ADR-0004 made `verify` plan-only: AgentGuard does not execute user checks; the agent runs them and AgentGuard records the result via `verify --record-pass` / `--record-fail`.

This is the right shape for capability isolation, but it leaves a gap: an agent (or a stubborn human) can call `agentguard verify --record-pass typecheck` without actually running `pnpm typecheck`. The lease then becomes self-attested — a fact about what someone *claimed* happened, not a fact about what *did* happen. ADR-0008's completion-lease invariant depends on the lease being trustworthy. Self-attestation undermines that.

The GPT pre-implementation review (#9) flagged this as a critical gap.

## Decision

Every recorded check result carries an `attestation` field with one of four values:

- `hook-observed` — a host hook adapter watched the actual shell command run and captured its exit code. The hook payload included the command line and exit status; AgentGuard recorded the result with provenance.
- `ci-observed` — a CI runner (GitHub Actions workflow) ran the check and recorded the result via `agentguard verify --record-pass --source ci-observed` after a successful step.
- `manual` — `agentguard verify --record-pass <id>` was called directly without an observed run. The actor (`user`, `agent-self`, or a named identity) is captured in `attestationDetails.actor`.
- `unknown` — legacy or migrated records; only acceptable during a documented migration window.

Recording surface:

- `agentguard verify --record-pass <id> [--source hook-observed|ci-observed|manual] [--exit-code N] [--command "..."]`. Default `--source` is `manual`.
- Hook adapters always pass `--source hook-observed --command "<observed cmd>" --exit-code <N>`.
- CI workflows pass `--source ci-observed --exit-code <N>`.

**Mode-dependent acceptance for lease issuance:**

- `observe` mode accepts all attestation kinds toward a lease.
- `enforce` mode accepts only `hook-observed` and `ci-observed`. `manual` records are still written (they appear in `checkResults[]`) but they do not enable a lease.

This makes lease forgery in `enforce` mode require either tampering with the ledger or compromising the hook adapter — both detectable (ledger is tamper-evident; adapter is the AgentGuard binary itself).

## Consequences

Positive:

- Leases are evidence-backed, not self-claimed.
- The agent's natural workflow (running checks via Bash) automatically produces `hook-observed` records when AgentGuard's hooks are installed. No new agent behavior required.
- Manual recording is preserved for developers running checks outside the agent loop in `observe` mode.
- CI gets a first-class attestation source for required-status-check workflows.

Negative:

- One more field on every `CheckResult`. Minor.
- `enforce`-mode users who run checks manually (no hooks installed) get no lease until they call `agentguard verify --record-pass --source manual` and either (a) downgrade to `observe`, (b) install hooks, or (c) acknowledge that the lease will not be available. This is the correct trade-off — `enforce` mode says "I want guarantees."
- Hook adapters become slightly more complex: matching observed shell commands to configured check `command` strings.

## Alternatives considered

1. **No attestation; trust all records.** Status quo. Rejected: undermines ADR-0008.
2. **Always require hook-observed.** Rejected: too strict for solo developers in `observe` mode.
3. **Cryptographic signing of records.** Rejected: overkill for the local-first MVP. Attestation labels are sufficient and far simpler.

## References

- ADR-0004 — verify is plan-only (the gap this ADR closes).
- ADR-0008 — completion lease (the consumer of trustworthy check state).
- CONTEXT.md — "Attestation" section.
- `.scratch/agentguard/issues/07-verify-base.md`, `11-done-completion-gate.md`, `13-hooks-claude-code.md`, `17-github-actions.md`.
