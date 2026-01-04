# Epistemics (SYSopGPTWSL)

Use these tags in reports, issues, and change proposals.

## Confidence tags
- `[OBSERVED]` Directly seen output from a command, file, or log.
  - Include the command and the key output line(s).
- `[INFERRED]` Conclusion drawn from multiple observations.
  - State the reasoning and point to the observations.
- `[HYPOTHETICAL]` Guess / next diagnostic step.
  - Treat as a question; propose a command to confirm.

Optional:
- `[USER-CLAIM]` You said it; not yet verified.

## Context tags (WSL-specific)
- `(Codex runner)` Command run inside Codex’s tool runner; may have sandbox limits.
- `(Interactive shell)` Command run in an interactive Ubuntu terminal (authoritative for `systemctl`).

## Examples
- `[OBSERVED] (Codex runner) systemctl is-system-running => Failed to connect to bus: Operation not permitted`
- `[OBSERVED] (Interactive shell) systemctl is-system-running => running`
- `[INFERRED] systemd is healthy; Codex runner cannot connect to bus`
- `[HYPOTHETICAL] If interactive systemctl fails too, run Windows PowerShell: wsl --shutdown`
