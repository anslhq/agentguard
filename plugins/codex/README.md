# AgentGuard — Codex plugin (Milestone 2)

This directory holds the Codex-side artifacts for AgentGuard:

- `.codex/hooks.json` — Codex hooks wiring for SessionStart, PreToolUse,
  PostToolUse, UserPromptSubmit, and Stop. All call into the `agentguard`
  binary with `--host codex`.
- `.agents/skills/agentguard/SKILL.md` — Codex auto-discovered skill. Generated
  from `plugins/_shared/SKILL_SRC.md` by `tooling/render-skills/`.
- `AGENTS.md.snippet` — append-only block for the repo's or user's `AGENTS.md`.

## Enforcement caveats (must be in user-facing docs)

- **`PreToolUse` does not intercept all shell calls.** In current Codex
  versions, certain shell invocations bypass the `PreToolUse` hook. AgentGuard
  enforcement on Codex is **best-effort**, not guaranteed. CI (Issue 17) is
  the authoritative gate on the protected branch.
- **`permissionDecision: "ask"` is not supported for `PreToolUse` on Codex.**
  AgentGuard's `action: "confirm"` maps to `permissionDecision: "deny"` with
  a `permissionDecisionReason` telling the agent to surface the approval
  request to the human, who then runs `agentguard approve <id>` and asks the
  agent to retry. The approval is consumed on retry within the TTL.

These caveats are restated in the post-install message of
`agentguard hooks install --host codex` so users see them before relying on
Codex-side enforcement.
