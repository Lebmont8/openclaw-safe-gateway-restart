# Security

The default mode requests OpenClaw's deferred safe restart and never sends a
signal or kills a process itself. `--force` adds `--skip-deferral`; use it only
after explicit approval for an emergency restart.

The verifier reads only health state and listener PIDs. It writes a bounded
operational log and does not print configuration or credentials.
