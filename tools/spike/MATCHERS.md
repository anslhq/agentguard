# Matcher Spike Report (Issue 00)

Date: 2026-05-20
Compiler: Zero v0.1.3 (with AgentGuard's `std.mem.eql` Mach-O patch applied).

## Question

Can the AgentGuard rule DSL (CONTEXT.md "Rule") be implemented using only Zero v0.1.3 primitives? Specifically: first-token exact match, anchored substring/glob, named fingerprints.

## Findings

| Capability needed | Zero v0.1.3 primitive | Status |
|---|---|---|
| Exact string equality | `std.mem.eql(a, b)` → `IR_VALUE_BYTE_VIEW_EQ` | **Implemented on darwin-arm64 Mach-O after the AgentGuard upstream patch.** Already worked on linux-musl-x64. Confirmed by 8/8 fixture-table runtime tests in `/tmp/probe_eql2_bin`. |
| Byte-prefix / first-N-byte check | `std.mem.len(span)` + `span[i]` (`IR_VALUE_BYTE_VIEW_LEN` + `IR_VALUE_BYTE_VIEW_INDEX_LOAD`) | **Implemented on all emitters.** Already used in `emit_macho64.c:1286-1308`. |
| Glob (`*.lock`, `auth/**`) | Compose `std.mem.eql` for fixed parts + length checks for variable spans. The MVP rule DSL caps glob complexity to "one wildcard, anchored at start or end". | **Implementable** via composition; see `match_demo.0` for the prefix shape. Suffix is the same shape but indexed from `len - k`. |
| Named fingerprints (`aws-access-key-id`, `private-key-pem`, etc.) | Pre-compiled byte arrays + `std.mem.eql` for the leading marker, then length / charset constraints via indexed loads. | **Implementable.** No regex needed for the named fingerprints in CONTEXT.md. |
| Full regex (NOT in MVP scope) | n/a | Not implementable in v0.1.3 stdlib. Confirms ADR-0009's choice to use structured matchers only. |

## Classification

**ADR-0009 outcome A on the matcher axis** — the rule DSL is fully implementable in v0.1.3 with the std.mem primitives. No `std.regex` is needed because CONTEXT.md "Rule" already designed the DSL around structured matchers (anchored substring + glob + named fingerprints), not free-form regex.

## Reference proof

`tools/spike/match_demo.0` exercises:
- Exact match via `std.mem.eql` on a `Maybe<String>.value`.
- Prefix match via length check + four indexed byte loads.

The file `zero check --json`s clean (`ok: true`, zero diagnostics) and builds runtime-clean on darwin-arm64 with the patched compiler.

## Implementation guidance

The `CommandClassifier` and `DiffClassifier` modules (Issue 05 / Issue 07) should:

1. Use `std.mem.eql` for the first-token index (one byte-view equality per rule per command).
2. Use `std.mem.len` + indexed loads for path-prefix / extension matching in the diff classifier.
3. Keep named fingerprints (CONTEXT.md "Rule") as compile-time byte literals at the top of `src/policy/rules_sec.0`; match them with `std.mem.eql` first, then any length / charset rules via indexed loads.
4. Never invent a regex API; the structured-matcher set above is sufficient for every rule in the MVP per the matrix above.
