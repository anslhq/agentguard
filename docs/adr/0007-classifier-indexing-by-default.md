# ADR 0007: Classifier rule lookup is indexed from day one

Status: Accepted
Date: 2026-05-20

## Context

Two AgentGuard modules will be hot paths once the MVP is wired into hook adapters:

- **`CommandClassifier`** — `(command_string, repo_profile, policy) → RiskResult`. Invoked on every `beforeShellExecution` / `PreToolUse` event, which can fire many times per turn.
- **`DiffClassifier`** — `(git_status, git_diff) → ChangeClass[]`. Invoked on every `afterFileEdit` / `PostToolUse` event, and indirectly on every `verify` and `done`.

A naive implementation that iterates every rule against every candidate gives `O(rules × candidates)`. With ~20 MVP rules and small diffs this is fine. With ~200 rules in a year and a 1000-file diff (rebase, generated code) it is not. The shape change later — adding indexing after every caller assumes a linear scan — is invasive.

The complexity-optimizer skill flags both of these as classic O(n²) candidates that should be designed with an index from the start, not retrofitted. The brooks-sweep skill flags them as classic shallow-module risks (the "scan every rule" implementation is shallower than the interface promises).

## Decision

Both classifiers ship with rule indexes from the first commit:

**`CommandClassifier`:**
- Rules are pre-indexed by their **first command token** at policy-load time. `rm` rules live under key `rm`, `git` rules under `git`, etc. Anchored regex first-tokens (`^rm`, `^git`) trivially yield a key; un-anchored or complex patterns fall back to a small "unindexed" bucket scanned unconditionally.
- Lookup: tokenize the command's first word, look up the bucket, evaluate only those rules + the unindexed bucket. Expected complexity: `O(matched-bucket + unindexed)`, where both are tiny in practice.
- Tokenization is shared (a single std.parse pass), not repeated per rule.

**`DiffClassifier`:**
- Rules whose `requiredFor` is a literal path (`package.json`, `pnpm-lock.yaml`) are placed in an exact-match index.
- Rules whose `requiredFor` is a single-segment glob (`*.ts`, `*.tsx`) are placed in an extension index keyed by extension.
- Rules with multi-segment globs (`auth/**`, `db/migrations/**`, `**/secrets/**`) are placed in a path-prefix index where the longest static prefix is the key.
- Rules with arbitrarily complex globs fall back to the unindexed bucket.
- Lookup per changed file: exact match → extension → longest-prefix match in the prefix index → unindexed bucket. Expected complexity per file: `O(log(prefix-index) + unindexed)`.

Both indexes are pure data structures built once when policy/checks are loaded. They are part of the **implementation** of the classifier, not part of its **interface** — the interface stays `(command, profile, policy) → RiskResult` and `(diff) → ChangeClass[]`. Callers and tests cross the same seam regardless of indexing strategy.

The fixture-table tests are the **interface test surface** — they assert `(input, expected_output)` and stay valid as the indexing strategy evolves.

## Consequences

Positive:

- Hot paths stay roughly `O(rules-that-actually-apply + unindexed-fallback)` from the first commit.
- Interface stays clean: indexing is an implementation detail, never a caller concern.
- Adding rules does not slow down callers proportionally.
- Brooks-sweep / complexity-optimizer post-implementation passes won't flag these as obvious O(n²) hotspots.

Negative:

- Slightly more code at the first commit than a naive scan. Acceptable: indexing is well-understood and the cost is bounded.
- Indexer must be tested. Mitigated by the same fixture-table tests that cover the classifiers — they exercise the index by construction.

## Alternatives considered

1. **Ship naive scan first; index later.** The complexity-optimizer playbook warns against this for hot paths. Retrofitting requires changing how rules declare their match criteria, which ripples into every rule file. Cheaper to do it once.
2. **Compile the rule set into a single regex / Aho-Corasick automaton.** Powerful, but the rule set will include non-regex predicates (path globs, manifest-vs-lockfile relationships) that don't compose. Rejected as overkill for v1.

## References

- `LANGUAGE.md` (architecture vocabulary) — "the interface is the test surface."
- complexity-optimizer skill — O(n²) detection patterns.
- brooks-sweep skill — shallow-module detection.
- `.scratch/agentguard/issues/05-risk-base.md`, `07-verify-base.md` — implementation issues that ship the initial classifiers.
