# Host Payload Fixtures (Issue 22)

This directory stores **real host hook payloads** captured from live host sessions
plus synthetic fixtures for shapes we have not yet captured.

## Layout

```
host_payloads/
├── claude-code/
│   ├── PreToolUse_Bash_safe/
│   │   ├── payload.json          # raw stdin payload
│   │   ├── host.txt              # host name, version, AgentGuard version, timestamp
│   │   └── expected.json         # expected AgentGuard envelope on stdout
│   └── ...
├── cursor/                       # M2 placeholders
└── codex/                        # M2 placeholders
```

## Synthetic vs captured

- **Synthetic** fixtures (clearly labeled in `host.txt`) are shaped from the
  published host docs but were not captured from a live session. They are good
  enough for adapter shape verification but **must be replaced by real
  captures** before M1 ships to users.
- **Captured** fixtures came from a live host session via
  `tooling/capture-host-payloads/`. These are the authoritative test inputs.

## Capturing real payloads

The capture protocol (Issue 22) defines a `tooling/capture-host-payloads.0`
wrapper that records stdin to disk before invoking the AgentGuard binary.
Configure the host plugin to invoke that wrapper instead of `agentguard`,
run through every event in a real session, then move the captured files into
this directory and write `host.txt` + `expected.json`.

Until the wrapper lands as a Zero program (currently blocked on
`std.fs.readBytes` in the Mach-O direct backend — see AGENTS.md), capture is
done by editing `plugins/claude-code/hooks/hooks.json` to prepend `tee
.../payload.json |` to each `command`.
