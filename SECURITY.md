# Security Policy

## Status

AgentGuard is currently **alpha** software.

It should **not** be treated as a production-grade security boundary yet.

Today the project is best understood as:

- a local-first workflow control system in development
- a deterministic guardrail layer for coding-agent loops
- an implementation that still contains partial and stubbed areas

Do not rely on it as your sole protection for:

- secrets handling
- destructive command prevention
- policy enforcement across all host integrations
- tamper-proof auditability

## Reporting a vulnerability

If you believe you have found a security issue, please avoid opening a public issue with exploit details.

Instead, contact the maintainers privately first. If no dedicated security inbox is listed yet, open a minimal issue asking for a private contact channel without publishing the exploit details.

When reporting, include:

- affected version or commit
- host/tooling context
- reproduction steps
- impact assessment
- whether the issue is design-level, implementation-level, or docs/claim mismatch

## Scope notes

Security reports are especially useful around:

- command classification bypasses
- host hook escape paths
- secret leakage in diagnostics or context packs
- ledger integrity mismatches
- unsafe approval or lease behavior

## Disclosure expectations

Because this project is pre-1.0, some findings may identify places where the documentation overstates what is enforced. Those are still valuable and should be reported.
