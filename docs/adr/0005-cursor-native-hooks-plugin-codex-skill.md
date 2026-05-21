# ADR 0005: Cursor and Codex get native distribution units, not just snippets

Status: Accepted
Date: 2026-05-20

## Context

The initial PRD treated Cursor and Codex as variants of the same "drop a rule snippet" pattern used for Claude Code. Live docs (fetched 2026-05-20) show that:

1. **Cursor has a native hooks system that is a strict superset of Claude Code's**, including:
   - `beforeShellExecution` (with regex `matcher`) and `afterShellExecution` (with full command output + duration).
   - `beforeReadFile` — gates file reads at the source, *before* content reaches the model. Solves `SEC001` (.env touch) earlier than diff-based detection.
   - `beforeMCPExecution` / `afterMCPExecution` — gates MCP tool calls.
   - `sessionStart` / `sessionEnd` with native `session_id` — AgentGuard can adopt the host session ID instead of synthesizing one.
   - `stop` with `followup_message` and `loop_count` — Cursor will auto-submit a new user message to the agent. Lets AgentGuard feed `nextAgentInstruction` *directly* back into the loop.
   - `beforeSubmitPrompt`, `preCompact`, `workspaceOpen`, `afterAgentResponse`, `afterAgentThought` — observability surfaces we can use later.

2. **Cursor has a plugin distribution unit** (`.cursor-plugin/plugin.json`) that bundles hooks, rules, skills, agents, commands, and MCP servers into a single installable git repo. Cursor also supports loading Claude Code hooks natively, so a Claude Code adapter is partially reusable.

3. **Codex has no hooks**, but does have:
   - **`AGENTS.md`** layered instruction discovery (global → repo → cwd).
   - **Skills**: `.agents/skills/<name>/SKILL.md` with optional `agents/openai.yaml` for MCP/tool dependencies and UI metadata. Skills are auto-discovered.
   - **Plugins** as a distribution unit for skills + app mappings + MCP server configuration.

Sources:
- `https://cursor.com/docs/hooks` (the full hook reference for Cursor)
- `https://cursor.com/docs/plugins` (plugin format and marketplace)
- `https://developers.openai.com/codex/skills` (skill format and discovery)
- `https://developers.openai.com/codex/guides/agents-md` (AGENTS.md discovery and layering)

## Decision

AgentGuard ships three distinct host integrations, each using the host's native distribution unit:

1. **Cursor: a plugin.** A git-distributable directory at the top level of the AgentGuard repo containing `.cursor-plugin/plugin.json`, `hooks.json` (with `beforeShellExecution`, `afterShellExecution`, `beforeReadFile`, `afterFileEdit`, `sessionStart`, `sessionEnd`, `stop`), `rules/agentguard.mdc`, and `skills/agentguard/SKILL.md`. The `stop` hook uses `followup_message` to feed `nextAgentInstruction` back to the agent when `done` returns `not_done`. Installable from the Cursor marketplace, from a local symlink under `~/.cursor/plugins/local/`, or from a team marketplace.

2. **Codex: a skill + AGENTS.md snippet.** A `.agents/skills/agentguard/SKILL.md` (with `agents/openai.yaml` declaring AgentGuard's MCP server as a tool dependency) plus an optional `AGENTS.md` block for global guidance.

3. **Claude Code: a `.claude/settings.json` hooks block.** Unchanged from the original plan. Cursor's third-party-hooks loader means this also works as a Cursor fallback when the native Cursor plugin is not installed.

`agentguard hooks install --tool <cursor|codex|claude-code>` becomes `agentguard hooks install --host <cursor|codex|claude-code>` (renaming "tool" to "host" — see CONTEXT.md "Host" definition). Each installer writes the host-native artifact, not a generic snippet.

## Consequences

Positive:

- Cursor users get the full hook surface (file-read gating, MCP gating, native session IDs, the `followup_message` re-prompt loop). The killer feature lands in its purest form on Cursor.
- Codex users get the discovery model Codex actually uses (skills + AGENTS.md), not a degraded "paste this snippet" experience.
- Sessions in Cursor adopt the host `session_id`. The inactivity-timeout fallback (CONTEXT.md) only fires for Codex / CLI / MCP contexts.
- AgentGuard becomes a marketplace plugin candidate.

Negative:

- Three host artifacts instead of one shared snippet. Each needs its own template and installer.
- The "followup_message loop" path is Cursor-only. Claude Code falls back to the read-`nextAgentInstruction`-from-JSON pattern. Documented as a known asymmetry.
- More surface to test (host-payload fixtures per host).

## Alternatives considered

1. **Keep "snippet for each host" as in the original PRD.** Cheapest, but leaves the most value on the table — particularly Cursor's `followup_message` loop and `beforeReadFile` gate.
2. **Cursor plugin only, defer Codex skill to later.** Tempting but Codex usage among our target persona is real; the skill is cheap to add and gives parity.
3. **Single MCP server for all hosts.** MCP is the right shape for Codex (which lacks hooks), but Cursor and Claude Code get more leverage from native hooks. MCP becomes a parallel exposure surface in a later milestone, not a replacement.

## References

- Cursor hooks: `https://cursor.com/docs/hooks`
- Cursor plugins: `https://cursor.com/docs/plugins`
- Codex skills: `https://developers.openai.com/codex/skills`
- Codex AGENTS.md: `https://developers.openai.com/codex/guides/agents-md`
- `CONTEXT.md` — Host integration terms section.
- `.scratch/agentguard/issues/13`, `14`, `15` — host integration issues, updated accordingly.
