---
name: subclaw
description: Use when Kimi Code should delegate repo scans, reviews, drafting, or peer-review passes to cheap worker models through the herdr + cockpit-cliproxy gateway pool, with live pane echo in Kimi CLI. Verifier layer auto-checks output and redoes on FAIL without spending orchestrator tokens.
---

# subclaw v2 (Kimi Code branch)

Kimi Code is the orchestrator (牧人). The runner is the SAME engine-neutral PowerShell as the Claude branch. Workers (羊群) are real `claude` CLI instances in herdr panes, pointed at cockpit-cliproxy gateway instances (:1456-1459) fronting SenseNova/LLMs. The verifier layer (牧羊犬) auto-checks output and redoes on FAIL without spending orchestrator tokens.

## REPO ROOT (`<ROOT>`)

All `<ROOT>` below refer to the herd-flows repo root, default `D:\devloop\workSpace\app_ZCode\herd-flows`.
If that path does not exist, locate `runner\herdr-pool.ps1` first (search your workspace or ask the user) and substitute.

## ROUTING RULES

1. Current orchestrator engine = **kimi**. The delegation paths described here are the ONLY legal paths in this engine.
2. NEVER call other engines' NATIVE subagent mechanisms: no Claude Code Task tool / `.claude/agents`, no Codex TOML agents. Using them inside Kimi causes hard errors.
3. Spawning external worker CLIs is allowed — but ONLY through this skill's runner (`herdr-pool.ps1`), never by hand-writing engine-specific flags.
4. Kimi-native delegation stays available for Kimi-side subagents; worker pools MUST go through the herdr runner.

## Endpoints

- Herdr session: `subclaw` (start: `powershell <ROOT>\scripts\start-herdr.ps1`)
- Gateway pool: `http://127.0.0.1:1456..1459` (cockpit-cliproxy, 准入 key `sk-subclaw-gateway`)
- Config: `<ROOT>\runner\config.json`
- Runner: `<ROOT>\runner\herdr-pool.ps1`

## Profiles (model + gateway port + CLI)

| Profile | Model | Port | Use for |
|---|---|---|---|
| `flash` | sensenova-6.8-flash-lite | 1458 | bulk scans, first-pass drafts, classification |
| `deepseek` | deepseek-v4-flash | 1457 | reasoning, audit, cross-file analysis, verification |
| `glm` | glm-5.2 | 1456 | long-context reading, code review |

Override port per dispatch with `-Port <n>`.

## Workflow

1. First call in a session:
```powershell
powershell <ROOT>\runner\herdr-pool.ps1 -Ensure
```
Checks Herdr session is up, writes per-profile worker settings, probes each gateway port. Exit code 0 = ready; 1 = herdr session down; 2 = all gateway ports down. If ports report DOWN, ask user to run `powershell <ROOT>\scripts\start-proxy.ps1`.

2. Dispatch:
```powershell
powershell <ROOT>\runner\herdr-pool.ps1 -Dispatch "<task>" -Profile flash -Name w1
# async dispatch: -Async
```
Verifier on by default. **Exit codes**: `0` = done / verifier PASS (or `-NoVerify`); `2` = verifier FAIL after max rounds (inspect with `-Read`); `3` = worker blocked (needs human attention).

3. Read back / status / clean:
```powershell
powershell <ROOT>\runner\herdr-pool.ps1 -Read w1
powershell <ROOT>\runner\herdr-pool.ps1 -Status
powershell <ROOT>\runner\herdr-pool.ps1 -Clean w1
```

## Verifier layer (saves your tokens)

- Verifier = a second worker on the `deepseek` profile acting as the sheepdog / inspector.
- It is instructed to actually inspect delivered files (not just the worker's claims) and emit a final `VERDICT:` line the runner parses.
- FAIL → worker gets redo instructions and reruns; you only see the final pass/abort.
- Skip with `-NoVerify` for trivial tasks.
