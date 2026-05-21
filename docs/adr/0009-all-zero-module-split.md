# ADR 0009: All Zero — no TypeScript in the runtime

Status: Accepted
Date: 2026-05-20

## Context

The PRD called for a "Zero core + TypeScript adapter" split, citing host payload parsing as a place where TypeScript would be more ergonomic. Issue 20 was left as an HITL decision pending an ADR.

Three things have since happened that change the calculus:

1. Zero 0.1.3 stdlib was confirmed to have all needed primitives: `std.fs` + `owned<File>` for ledger and lease writes, `std.json` for JSON I/O, `std.parse` for command tokenization, `std.args` / `std.env` for CLI + bypass env probes, `std.time` for session and lease expiry. `std.proc` exists but is not needed (ADR-0004: AgentGuard never runs user checks).
2. ADR-0003 binds AgentGuard's diagnostic shape to Zero's diagnostic shape field-for-field. AgentGuard *is* a Zero-aligned product. A TypeScript runtime against a Zero-shaped diagnostic is dissonant.
3. The architecture-skill vocabulary (`LANGUAGE.md`) sharpens the question. Per the deletion test: if AgentGuard's TS adapters were deleted, the work disappears — but the work is duplicated by Zero anyway. That makes the TS adapter a **shallow module** by construction.

## Issue 00 spike outcome (recorded 2026-05-20)

**Outcome A on language axis; A on matcher axis; B on hosted-IO runtime axis (with `cc` linker shim, not a TypeScript adapter).**

- **Stdin reading.** Path-form `std.fs.read("/dev/stdin", buf) -> usize` typechecks and works on linux-musl-x64 direct. On darwin-arm64 the direct `--emit exe` backend rejects programs containing any `std.fs.*` call (CGEN004 documented in `zerolang/docs/articles/cross-compilation.md`); the maintainer workaround is `--emit obj` + `cc program.o zero_runtime.c -o program` with the ~6-line `zero_world_write` runtime shim from `zerolang/scripts/test-native.sh:851-857`. The shim is C, not TypeScript; AgentGuard source remains 100% Zero. See `tools/spike/STDIN.md` for the full proof.
- **Pattern matching.** Structured matchers — anchored exact match (`std.mem.eql`), byte-prefix via `std.mem.len` + `span[i]`, named fingerprints as compile-time byte literals — cover every rule in CONTEXT.md "Rule". No regex is needed. See `tools/spike/MATCHERS.md` for the proof.
- **Upstream contribution (made by AgentGuard during Issue 00).** `std.mem.eql` lowered to `IR_VALUE_BYTE_VIEW_EQ` was implemented on Linux x86-64 (`emit_elf64.c:1792`) but absent on darwin-arm64 Mach-O (`emit_macho64.c` default-case → CGEN004). AgentGuard added the ~55-line AArch64 lowering at `emit_macho64.c` immediately before the `BYTE_VIEW_INDEX_LOAD` case; verified by 8/8 length+content fixture tests against the locally-built compiler. The patch is upstream-ready and should be submitted to `tylerb-public/zero`.
- **Known remaining gap.** Mach-O has no `raise`-to-exit-code lowering, so `Void raises` mains on darwin-arm64 always exit 0. This affects the ADR-0012 exit-64 contract on Mac local dev only — CI on linux-musl-x64 enforces exit-64 normally via the ELF64 `_start` stub at `emit_elf64.c:3060-3088`. Documented as a known M1 caveat in CONTEXT.md "Exit-code contract".

## Decision

AgentGuard's runtime is **entirely Zero**, with a ~6-line C runtime shim on hosts where the direct backend lacks a hosted-IO target (today: only when building for darwin-arm64 `--emit exe`). Two original conditional checks below are now resolved:

1. **Stdin reading.** Hook adapters must read a JSON payload from stdin. The Zero stdlib lists `std.fs`, `std.args`, `std.env`, etc., but a public-source playground note (May 2026) reports Zero v0.1.3 does not yet expose a stdin API. Issue 00 must either confirm a working stdin pattern or settle on a small shim.
2. **Pattern matching for rules.** Some rules need substring, glob, or fingerprint matching (`CommandClassifier` first-token + args pattern, `DiffClassifier` path globs, completion-claim detector). If Zero lacks regex in v0.1.3, AgentGuard uses **structured matchers only** (anchored substring, glob, named fingerprints from a built-in registry), which is sufficient for every MVP rule (see ADR-0009-revised matcher list in CONTEXT.md "Rule").

Acceptable outcomes from Issue 00:

- **A.** Zero v0.1.3 supports stdin + sufficient matchers. Ship all-Zero as planned.
- **B.** Zero supports matchers but not stdin. Ship a **minimal POSIX shell shim** (~30 lines, no product logic) that reads stdin, base64-encodes it, and execs the Zero binary with the payload as a flag. Product logic stays Zero.
- **C.** Zero supports stdin but lacks the matchers we need. Ship structured matchers only (drop regex from MVP rule DSL entirely). No language change.
- **D.** Neither stdin nor matchers work as needed. Block: re-evaluate language. This is the only outcome that requires a follow-up ADR.

In outcomes A–C, no TypeScript appears in the runtime. The shim in B is shell, not TypeScript. The "no `node_modules`" property is preserved.

No language change in this ADR is final until Issue 00 reports.

The split is along the architectural seam, not a language seam:

| Module | Where | Notes |
|---|---|---|
| `PolicyEngine` | Zero | Pure. |
| `CommandClassifier` | Zero | Pure. Indexed per ADR-0007. |
| `DiffClassifier` | Zero | Pure. Indexed per ADR-0007. |
| `VerificationPlanner` | Zero | Pure. |
| `DiagnosticBuilder` | Zero | Pure. Shape per ADR-0003. |
| `NextInstructionGenerator` | Zero | Pure. |
| `ContextPacker` | Zero | Pure, with redaction. |
| `LeaseStore` | Zero | Pure ledger reader. |
| `ClaimDetector` | Zero | Pure regex over message text. |
| `CompletionClassifier` | Zero | Pure. |
| `LoopBudget` | Zero | Pure ledger reader. |
| `Ledger` | Zero | Thin `std.fs` writer/reader. |
| `RepoProfile` | Zero | Filesystem scan. |
| `Doctor` | Zero | Probe composition. |
| `HookAdapter` (host) | Zero | Parses host stdin JSON via `std.json`, formats host stdout via `std.json`. One adapter per host (3). |
| `HookInstaller` | Zero | File-writing utility. |
| Plugin-build tooling | Zero | `tooling/render-skills` reads markdown templates, writes host-specific skill files. |

The published `agentguard` binary is a single Zero-compiled artifact. The Claude Code / Cursor / Codex plugins ship only this binary plus their host-native JSON/MD configuration files (`hooks.json`, `SKILL.md`, `.codex/hooks.json`).

No npm, no `node_modules`, no `tsx`. Users install AgentGuard via `curl … | sh` (the installer fetches the right Zero-compiled binary for their OS) and the host plugins are git-distributable directories with the binary as the only execution dependency.

## Consequences

Positive:

- One language, one build, one test harness, one published artifact.
- Diagnostic shape (ADR-0003) and the runtime stay aligned.
- No `node_modules` pollution in user repos.
- Zero's `World`-capability model and explicit error sets enforce determinism — the brand promise (PRD §5.2) holds in code.
- The host-adapter seam stays a real seam (3 host adapters, by the two-adapter rule) but all three live in the same language.

Negative:

- Zero 0.1.3 is pre-1.0 and the README warns against production / sensitive-data / trusted-infrastructure use. AgentGuard's mitigation: scope the MVP to detection and gating (no secret handling beyond redaction); avoid claiming production security guarantees in marketing.
- `std.json` parsing is more explicit than `JSON.parse` — adapter code is somewhat more verbose. Acceptable: host payloads have flat, predictable shapes, and the explicitness aligns with the deterministic brand.
- The team must be comfortable in Zero. Trade-off accepted by the project's overall direction.

## Alternatives considered

1. **Zero core + TypeScript adapters** (the original PRD position). Rejected per the deletion-test argument: deleting the TS adapters removes work that Zero would otherwise do — pure overhead.
2. **TypeScript core + Zero for nothing** — never seriously considered. Loses every alignment benefit.
3. **Rust or Go.** Both viable in the abstract. Rejected because Zero's diagnostic shape, capability model, and agent-first design are direct product-fit advantages that Rust/Go don't have. The Zero 0.1.x pre-1.0 risk is real but mitigated by the MVP's scope.

## References

- ADR-0003 — diagnostic shape mirrors Zero.
- ADR-0004 — verify is plan-only (eliminates `std.proc` need for user checks).
- ADR-0006 — three native plugins, one binary.
- ADR-0007 — indexed classifiers from day one.
- `zero skills get zero-stdlib --full` — capability inventory.
- `LANGUAGE.md` (architecture skill) — module / interface / depth / seam vocabulary; deletion test.
- `.scratch/agentguard/issues/20-zero-vs-ts-split.md` — issue this ADR closes.
