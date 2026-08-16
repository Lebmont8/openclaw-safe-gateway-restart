# OpenClaw Safe Gateway Restart

A small wrapper that requests an OpenClaw safe gateway restart and refuses to
report success until it has fresh runtime proof.

PID-only checks are insufficient: container supervisors can keep the same
gateway process while OpenClaw reloads channels in place. This tool accepts
success only when health is `ok` and either:

- a new listener PID appears; or
- the newest `channels.*.lastStartAt` runtime generation advances.

## Install

```bash
git clone https://github.com/Lebmont8/openclaw-safe-gateway-restart.git
cd openclaw-safe-gateway-restart
npm run verify
```

## Use

```bash
./scripts/safe-restart.sh
```

Configuration:

- `OPENCLAW_CLI` — OpenClaw executable
- `OPENCLAW_GATEWAY_PORT` — listener port, default `18789`
- `OPENCLAW_RESTART_WAIT_SECONDS` — timeout, default `600`
- `OPENCLAW_RESTART_POLL_SECONDS` — polling interval, default `1`
- `OPENCLAW_RESTART_LOG_FILE` — log path

`--force` requests `--skip-deferral`. It does not send signals itself, but it
can interrupt active work and should be used only with explicit approval.

## Verification model

```text
pre-restart health + PIDs
          |
          v
openclaw gateway restart --safe --json
          |
          v
fresh health AND (new PID OR newer runtime generation)
```

MIT licensed.
