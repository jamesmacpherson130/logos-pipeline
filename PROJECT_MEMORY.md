# Project Memory (Assistant Working Agreement)
- “Do as much of the work as possible”: default to end-to-end commands & patches; minimize clarifying questions.
- “Logos Protocol” semantics:
  - Treat **logos** as a directive to apply our protocol: (a) run the Logos pipeline where relevant; (b) use doctrine + tags to answer or guide next steps; (c) return actionable commands and artifacts.
  - Assume protocol is *always on* unless explicitly paused.
- Timeline & efficiency: prioritize speed, automation, and idempotent scripts; avoid UI clicks when CLI can do it.
- Durability: anything done with Pro **must not** require Pro later; all outputs saved to disk and committed.
- Environment: Windows + PowerShell 7; prefer aliases for frequent tasks; scheduled daily snapshots OK.
- Git: keep repo lean; commit snapshots/reports; normalize line endings; push when remote configured.
- Accessibility: PSReadLine predictions are nice-to-have; never required for pipeline.
- Error-handling: scripts should fail fast with clear messages and safe defaults; print next-step hints.
Last updated: 2025-10-01T11:25:00
