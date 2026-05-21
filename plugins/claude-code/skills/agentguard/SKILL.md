---
name: agentguard
description: Run AgentGuard checks before destructive commands, verify edits, and guard task completion. Use when working in a repo with `.agentguard/`.
---

# AgentGuard

AgentGuard supervises agent coding sessions by risk-gating commands, verifying
edits, and enforcing a completion lease invariant. Every command emits JSON
with a stable schema and a `nextAgentInstruction` field that names the next
step. Read the JSON, do exactly what it says, then rerun the relevant
AgentGuard command.

## When to invoke

Invoke AgentGuard whenever any of these conditions hold for the host you are
running in:

- About to run a shell command — call `agentguard risk --command "..." --json`
  before execution. If `action` is `block` or `confirm`, follow the
  `nextAgentInstruction` exactly. Never substitute another command.
- After editing files — call `agentguard verify --json`. If `requiredChecks`
  is non-empty, run them and report results via
  `agentguard verify --record-pass <check>` or `--record-fail <check>`.
- Before claiming task completion in a Stop message — call
  `agentguard done --finalize --json`. If `leaseDecision` is not `issued`,
  resolve the blockers reported in `diagnostics` first.

## Three rules you cannot break

1. **Completion is proved by a lease, never by prose.** A claim of "done" in
   your last message must be backed by a fresh, valid `done --finalize`
   lease. The Stop hook will block you otherwise and re-prompt with the
   exact next action.
2. **You do not run AgentGuard's own checks.** AgentGuard plans; you
   execute. Use `agentguard verify --json` to learn which checks the agent
   workflow expects, run them yourself, then record outcomes via
   `--record-pass` / `--record-fail` with `--source hook-observed` when your
   host runs them under a `PostToolUse`/`afterShellExecution` hook (default)
   or `--source manual` when you ran them out-of-band (only honored in
   `observe` mode per ADR-0010).
3. **You never edit `.agentguard/policy.json`, `.agentguard/checks.json`,
   any host hook config, or the ledger.** AgentGuard reports those edits as
   strong-confidence bypass findings. Ask the human to make policy changes.

## Diagnostic codes

Diagnostic codes (CMD\*\*\*, DEP\*\*\*, CHG\*\*\*, POL\*\*\*, SEC\*\*\*,
CTX\*\*\*, DOC\*\*\*) are stable and never reused. Run
`agentguard explain <CODE>` for the full description.

## Exit codes

Standalone CLI use (Git hooks, CI, ad-hoc terminal):

- `0` — success
- `1` — recoverable error
- `2` — blocking finding (`action == "block"`)
- `3` — confirmation required (`action == "confirm"`)
- `64` — usage error
- `70` — internal error

Hook adapters running with `--host <name>` always exit `0` and convey the
decision in the host-shaped JSON on stdout.
