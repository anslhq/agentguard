# ADR 0011: Phased host integration — Claude Code + Git + CI in MVP; Cursor + Codex in Milestone 2

Status: Accepted
Date: 2026-05-20

## Context

ADR-0006 declared three native plugins. The initial implementation plan listed all three as MVP-blocking. The GPT pre-implementation review pushed back on this: implementing three host adapters in parallel before the core is proven, and against three host hook specs (one of which — Codex — has incomplete `PreToolUse` shell-call coverage), is too much for the first implementation pass. The review recommended Claude Code first.

Three observations support staging:

1. **Claude Code's hook docs are the most stable and comprehensive of the three.** `Stop` `decision: "block"` + `reason` is well-documented; `PreToolUse` with `permissionDecision`, `updatedInput`, and `additionalContext` is well-documented; `PostToolUse` `additionalContext` is well-documented. Adapter behavior can be fixture-tested against published examples.
2. **Codex's `permissionDecision: "ask"` is not supported today** (see GPT review #3). This forces a different action-mapping table for Codex (`confirm` → `deny` with retry instructions). Best handled after the action mapping has been proven on Claude.
3. **Codex `PreToolUse` does not intercept all shell calls in current Codex versions.** AgentGuard cannot truthfully claim full local enforcement on Codex MVP. Best to ship Codex as "best-effort" in a later milestone with the limitation clearly stated.

## Decision

**Milestone 1 (MVP, first proof point):**

- Core CLI + envelope + diagnostic builder + ledger + LeaseStore + ClassifyStop + RepoProfile + DiffClassifier + CommandClassifier + VerificationPlanner + PolicyEngine + Doctor.
- **Claude Code plugin** (the only host adapter in MVP).
- **Git** hooks (pre-commit, pre-push).
- **GitHub Actions** workflow + `--ci` mode (CI is the authoritative gate).

**Milestone 2:**

- **Cursor plugin.**
- **Codex hooks + skill + AGENTS.md.** With explicit "best-effort enforcement" framing.
- `pack` context-packer.
- `monitors/monitors.json` for Claude Code (experimental Claude feature; deferred).
- Bypass-detection kinds beyond `policy_edit_in_session` and `env_bypass_observed` (the strong ones); the weak `verify_likely_skipped` kind comes here too.

This means MVP user-visible host coverage is Claude Code only. Cursor and Codex users get docs that say "coming in Milestone 2" plus the GitHub Actions integration which is host-agnostic.

The architectural choices that already happened — three plugins, separate dirs, no fallback — are preserved. Cursor and Codex are designed now; their issues are written; their plugin directories exist. Implementation just ships later.

## Consequences

Positive:

- MVP scope is realistic. One host adapter is faster to harden than three.
- Claude Code's documented `Stop` block-with-reason loop is a strong demonstrable proof point for the completion-lease design.
- CI integration (host-agnostic) is in MVP, so teams using *any* agent host get the authoritative gate.
- Codex's `permissionDecision: "ask"` workaround and weak shell-call coverage get more time to settle (Codex docs are moving fast).

Negative:

- Cursor users are explicitly excluded from MVP. Mitigated by: Cursor's superset hook surface means the MVP-2 implementation is mostly adapter code, not new core. The completion lease and core modules don't change.
- Codex users similarly delayed.
- Public messaging is "three plugins, two milestones." Slightly more nuanced than "three plugins shipped."

## Alternatives considered

1. **Ship all three in MVP.** Rejected per GPT review: too much surface to harden in parallel; Codex `ask` mapping needs design iteration that's safer after Claude lands.
2. **Ship Cursor first instead of Claude Code.** Cursor's hooks are also well-documented, but Claude Code's `Stop` block-with-reason is the cleanest demonstration of the completion-lease design and matches the originally-designed killer-feature loop most directly.
3. **MVP = CLI + Git + CI, no host adapter at all.** Considered. Rejected because the killer-feature lease loop requires the Stop-hook integration to be demonstrable. Without at least one host, the product story has no live demo.

## References

- ADR-0006 — three native plugins (this ADR stages their delivery).
- ADR-0008 — completion lease (Claude Code Stop is the cleanest demo of this).
- GPT pre-implementation review (Pro consultation, 2026-05-20) — recommendation to demote Cursor and Codex from MVP gate.
- `.scratch/agentguard/issues/13` (M1), `14` (M2), `15` (M2).
- `.scratch/agentguard/README.md` — phased dependency graph.
