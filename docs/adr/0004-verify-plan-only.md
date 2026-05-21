# ADR 0004: AgentGuard verify is plan-only; the agent executes checks

Status: Accepted
Date: 2026-05-20

## Context

The initial PRD said `verify` plans required checks by default and can opt into running them with `--run`. Two influences sharpened the decision:

1. Zero 0.1.3 ships `zero fix --plan --json` as strictly plan-only. The compiler reports repairs; the agent decides whether to apply them. AgentGuard's stated philosophy is to mirror Zero's design.
2. Allowing AgentGuard to execute arbitrary shell commands brings a class of operational concerns into MVP scope: timeouts, output buffering, captured-output secret redaction, process-tree cleanup, signal handling, and stuck check processes. None of these are AgentGuard's value proposition.

The agent already has shell access. AgentGuard giving it a second way to run shell commands duplicates that surface without adding capability.

## Decision

AgentGuard never executes user-configured checks. `verify` is strictly plan-only.

- `agentguard verify --json` outputs the required checks for the current diff and their last-recorded state (`not-run`, `passed-current`, `passed-stale`, `failed-current`, `failed-stale`, `unknown`).
- `agentguard verify --record-pass <check-id>` and `--record-fail <check-id> [--exit-code N]` are the only ways to update check state.
- Recorded state lives in `.agentguard/cache/last-verify.json`, keyed by check id and current diff hash. Edits after a recorded pass demote that check to `passed-stale`.
- Hook adapters automate recording. Claude Code's `PostToolUse` adapter recognizes a Bash invocation matching a configured check `command` and records the result based on exit code. Cursor and Codex integrations document the recording step in their respective `AGENTS.md` / rules snippets.

Probes (`doctor`) and rules (`verify`/`risk`) still run inside AgentGuard. Only **checks** are deferred to the agent.

## Consequences

Positive:

- AgentGuard never executes user code. No timeout, output-buffering, captured-output redaction, or process-lifetime concerns in MVP.
- Mirrors Zero's plan-only `fix` design. Consistent agent-first philosophy.
- The agent's existing tool surface (Bash) is the single execution path.
- AgentGuard cannot be a vector for runaway test suites or leaked secrets in captured output.

Negative:

- Solo developers running checks manually (outside an agent loop) need one extra step to record the result. A `agentguard wrap pnpm typecheck` convenience command can mitigate this in a later milestone.
- Issue 07's "run mode" goes away; Issue 07 narrows to plan + record. Issue 17 (GitHub Actions) needs to spell out that the workflow runs the user's checks via the workflow YAML (not via AgentGuard) and then calls `agentguard verify --record-*`.
- Hook adapters take on slightly more responsibility (recognizing check-command Bash invocations).

## Alternatives considered

1. **Plan by default + `--run` opt-in (original PRD).** Pragmatic but pulls execution concerns into MVP.
2. **Plan only + `--run-check <id>` for single named checks.** Compromise position. Still pulls process execution into AgentGuard. Rejected for the same reason.
3. **Always run.** Rejected — surprises users, breaks slow test suites.

## References

- `zero skills get zero-diagnostics` — `zero fix` is plan-only in v0.1.3.
- `CONTEXT.md` — Execution model section.
- `.scratch/agentguard/issues/07-verify-base.md` — needs revision (run mode removed).
- `.scratch/agentguard/issues/13-hooks-claude-code.md` — PostToolUse adapter must recognize check commands and call `--record-*`.
- `.scratch/agentguard/issues/17-github-actions.md` — CI workflow runs checks via YAML, then records via AgentGuard.
