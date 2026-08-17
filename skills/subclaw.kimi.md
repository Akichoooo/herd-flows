---
name: subclaw
description: Use when Kimi Code should delegate repo scans, reviews, drafting, or peer-review passes to cheap worker models through the herdr + cockpit-cliproxy gateway pool, with live pane echo in Kimi CLI. Verifier layer auto-checks output and redoes on FAIL without spending orchestrator tokens.
---

# subclaw v2 (Kimi Code branch)

Kimi Code is the orchestrator. The runner is the SAME engine-neutral PowerShell as the Claude branch — `D:\devloop\workSpace\app_ZCode\herd-flows\runner\herdr-pool.ps1`. Workers are real `claude` CLI instances in herdr panes, pointed at cockpit-cliproxy gateway instances (:1456-1459) fronting SenseNova.

## ROUTING RULES

1. Current orchestrator engine = **kimi**. The delegation paths described here are the ONLY legal paths in this engine.
2. NEVER call other engines' NATIVE subagent mechanisms: no Claude Code Task tool / `.claude/agents`, no Codex TOML agents. Using them inside Kimi causes hard errors (cross-wiring bug class).
3. Spawning external worker CLIs is allowed — but ONLY through this skill's runner (`herdr-pool.ps1`), never by hand-writing engine-specific flags.
4. Kimi-native delegation (`/coder`, `/explore`, `/plan`, `/swarm`) stays available for Kimi-side subagents; worker pools MUST go through the herdr runner.
5. The old `scripts/run_kimi_claw_pool.ps1` (claw-proxy :4748 based) is ARCHIVED — do not use. claw-proxy is retired.

## Endpoints

- herdr session: `subclaw` (start: `herdr --session subclaw` in a terminal, or the runner's `-Ensure` bootstraps it)
- Gateway pool: `http://127.0.0.1:1456..1459` (cockpit-cliproxy,准入 key `sk-subclaw-gateway`)
- Config: `D:\devloop\workSpace\app_ZCode\herd-flows\runner\config.json` (profiles, gateway ports, verifier template)
- Runner: `D:\devloop\workSpace\app_ZCode\herd-flows\runner\herdr-pool.ps1`

## Workflow

1. First call in a session:
```powershell
powershell D:\devloop\workSpace\app_ZCode\herd-flows\runner\herdr-pool.ps1 -Ensure
```
Checks herdr session is up, writes per-profile worker settings, probes each gateway port. If a port reports DOWN, ask the user to `docker compose -f "D:\Docker Project\cockpit-tools\compose.subclaw-pool.yml" --env-file "D:\Docker Project\cockpit-tools\.env" up -d`.

2. Dispatch (workers are `claude` CLI — Kimi has no CLI, so Kimi orchestrates and Claude executes):
```powershell
powershell D:\devloop\workSpace\app_ZCode\herd-flows\runner\herdr-pool.ps1 -Dispatch "<task>" -Profile flash -Name w1
```
Profiles: `flash` (6.8-flash-lite, :1458), `deepseek` (deepseek-v4-flash, :1457), `glm` (glm-5.2, :1456). Verifier on by default.

3. Read back / status / clean:
```powershell
powershell D:\devloop\workSpace\app_ZCode\herd-flows\runner\herdr-pool.ps1 -Read w1
powershell D:\devloop\workSpace\app_ZCode\herd-flows\runner\herdr-pool.ps1 -Status
powershell D:\devloop\workSpace\app_ZCode\herd-flows\runner\herdr-pool.ps1 -Clean w1
```

## Verifier layer (saves your tokens)

- Verifier = a second worker on the `deepseek` profile.
- FAIL → worker gets redo instructions and reruns; you only see the final pass/abort.
- Skip with `-NoVerify` for trivial tasks.

## Conventions

- Worker names: `[a-z][a-z0-9_-]{0,31}`, unique among live agents.
- Brief files: pass the path as the task text; the worker reads it itself.
- Reports persist in pane scrollback; use `-Read <name> --lines N` for more.
