# ADR 0006: Three native plugins, no cross-host fallback

Status: Accepted
Date: 2026-05-20

Supersedes the "Cursor can load Claude Code hooks natively, so the Claude Code adapter doubles as a Cursor fallback" framing in ADR-0005.

## Context

ADR-0005 set the direction: each host gets its native distribution unit instead of generic snippets. Drafting the issues afterwards leaned on Cursor's third-party-hooks loader to share artifacts. That framing is wrong:

- Cursor's third-party loader is **interop convenience**, not a design point. Treating it as the official Cursor integration ships a strictly inferior experience: no `beforeReadFile`, no `beforeMCPExecution`, no `followup_message` loop on `stop`, no native `sessionStart`/`sessionEnd` session IDs, no `workspaceOpen`. Users would never know they're getting the degraded path.
- It also conflates **plugin identity**. Two hosts loading "the same" hook config creates a fragile shared seam (this **module**'s **interface** is the hook payload — and the two host payload shapes disagree on several fields).
- The architecture vocabulary forces the right framing: each host plugin is a thin **adapter** at its native **seam**. Sharing an adapter across two hosts is a **shallow** abstraction that fails the deletion test — deleting the "shared adapter" concept and writing two adapters concentrates host-specific complexity in two places where it belongs.

## Decision

AgentGuard ships exactly three native plugins, in three separate top-level directories inside the AgentGuard repo. No third-party loader is part of any official integration path.

```
agentguard/
├── plugins/
│   ├── claude-code/                  ← native Claude Code plugin
│   │   ├── .claude-plugin/plugin.json
│   │   ├── hooks/hooks.json
│   │   ├── skills/agentguard/SKILL.md
│   │   ├── monitors/monitors.json    (optional M2: surface bypassFindings from verify/done events)
│   │   └── .mcp.json                 (optional: expose AgentGuard MCP)
│   │
│   ├── cursor/                       ← native Cursor plugin
│   │   ├── .cursor-plugin/plugin.json
│   │   ├── hooks.json
│   │   ├── rules/agentguard.mdc
│   │   └── skills/agentguard/SKILL.md
│   │
│   └── codex/                        ← Codex skill (no .codex-plugin directory)
│       └── .agents/skills/agentguard/
│           ├── SKILL.md
│           └── agents/openai.yaml
```

Note that **Codex has no plugin-directory analog** to Claude Code's `.claude-plugin/` or Cursor's `.cursor-plugin/`. Codex distributes skills directly via discovery from `.agents/skills/`. The `plugins/codex/` directory in our repo holds the skill folder; it is named `plugins/codex/` for symmetry with the others, not because Codex defines a `.codex-plugin/` format.

Each plugin's `hooks.json` (or skill) talks only to the host that defines those events. There is no shared host payload type. The three plugins share only:

1. The `agentguard` binary they invoke.
2. The core modules behind the binary (`PolicyEngine`, `CommandClassifier`, `DiffClassifier`, `VerificationPlanner`, `DiagnosticBuilder`, `ContextPacker`, `Ledger`).
3. The `--host <name>` flag plumbing that tells the binary which host payload shape to parse from stdin and which response shape to emit on stdout.

The `--host` adapter inside the binary is a real seam: three concrete adapters today (`claude-code`, `cursor`, `codex`), so the seam is justified by the two-adapter rule.

## Consequences

Positive:

- Each host gets the full surface its hook system supports — including the killer-feature re-prompt loop in both Claude Code (`Stop` `decision: "block"` + `reason`) and Cursor (`stop` `followup_message`).
- The host adapter is a real seam (3 adapters), not a hypothetical one.
- Installation, versioning, and updates are independent per host. A Cursor user is not blocked by a Claude Code hook-format change.
- Plugin namespacing differs cleanly per host (Claude Code namespaces skills as `/agentguard:risk`, Cursor does not). The skill files written for each host can use the host's native conventions.

Negative:

- Three install paths to document and test instead of one.
- Three sets of host-payload fixture tests.
- The Cursor plugin and Claude Code plugin both bundle a `skills/agentguard/SKILL.md` — file content overlaps. Mitigation: a small generator (`tooling/render-skills.ts` or its Zero equivalent) reads a shared markdown source and writes the host-flavored skill files at build time. The build-time step is internal; the published plugins are self-contained.

## Alternatives considered

1. **One plugin loaded via Cursor's third-party loader.** Rejected — strictly inferior Cursor experience.
2. **Codex `.codex-plugin/` directory.** Considered for symmetry. Rejected because Codex's documented format is the skill directory; inventing a parallel format would only confuse users.
3. **Single MCP server exposing AgentGuard to all hosts.** MCP is a parallel exposure surface (planned in a later milestone), not a replacement for native hooks. Hooks intercept the loop; MCP is invoked only when the agent decides to call a tool.

## References

- ADR-0005 — original native-distribution decision.
- `https://docs.claude.com/en/docs/claude-code/plugins`
- `https://cursor.com/docs/plugins`
- `https://developers.openai.com/codex/skills`
- `CONTEXT.md` — Host integration terms.
- `.scratch/agentguard/issues/13`, `14`, `15` — updated to drop fallback framing.
