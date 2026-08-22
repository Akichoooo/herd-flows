---
description: Dispatch scan/review/draft/patch tasks to cheap worker models via herdr panes + cockpit-cliproxy gateway pool. Saves orchestrator tokens; verifier layer auto-checks output. Usage /subclaw <task> | /subclaw file=<path>
allowed-tools: Bash(powershell*), Bash(bash*), Bash(curl*), Read, Write, Edit, Glob, Grep
argument-hint: "<task description> | file=<path-to-task.md>"
author: Akichoooo
---

# /subclaw v2 — herdr + cliproxy gateway pool + verifier

You (Claude) are the orchestrator (牧人). Workers (羊群) run in herdr panes, each a real `claude` CLI instance pointed at a cockpit-cliproxy gateway instance (:1456-1459) fronting SenseNova/LLMs. The verifier layer (牧羊犬) auto-checks worker output and redoes on FAIL without spending your tokens.

## REPO ROOT (`<ROOT>`)

All `<ROOT>` below refer to the herd-flows repo root, default `D:\devloop\workSpace\app_ZCode\herd-flows`.
If that path does not exist, locate `runner\herdr-pool.ps1` first (search your workspace or ask the user) and substitute.

## ROUTING RULES

1. Orchestrator engine = **claude**. The runner is engine-neutral PowerShell; do not hand-write `claude -p` flags.
2. All dispatch goes through `<ROOT>\runner\herdr-pool.ps1`. Never spawn worker CLIs directly.
3. Before first use in a session: `powershell <ROOT>\runner\herdr-pool.ps1 -Ensure` (verifies herdr pasture session, writes worker settings, probes gateway ports). Exit code 0 = ready; 1 = herdr session down; 2 = all gateway ports down.
4. If gateway ports report DOWN, tell the user to run `powershell <ROOT>\scripts\start-proxy.ps1` (or `docker compose -f <ROOT>\proxy\compose.subclaw-pool.yml --env-file <ROOT>\proxy\.env up -d`).

## Profiles (model + gateway port + CLI)

| Profile | Model | Port | Use for |
|---|---|---|---|
| `flash` | sensenova-6.8-flash-lite | 1458 | bulk scans, first-pass drafts, classification |
| `deepseek` | deepseek-v4-flash | 1457 | reasoning, audit, cross-file analysis, verification |
| `glm` | glm-5.2 | 1456 | long-context reading, code review |

Override port per dispatch with `-Port <n>`.

## Dispatch

```powershell
powershell <ROOT>\runner\herdr-pool.ps1 -Dispatch "<task>" -Profile flash -Name w1
# async non-blocking dispatch: -Async
# with verifier (default on): omit -NoVerify
# read back later: -Read w1
# status:          -Status w1
# clean up:        -Clean w1
```

The runner: splits a pane (smart direction — wide→right, narrow→down), starts `claude --settings <generated>`, prompts with `--wait`, reads output, then runs the verifier loop (max 2 rounds; FAIL → redoes; PASS → done).

**Exit codes**: `0` = done / verifier PASS (or `-NoVerify`); `2` = verifier FAIL after max rounds (inspect with `-Read`); `3` = worker blocked (needs human attention).

## Verifier layer (saves your tokens)

- Verifier = a second worker on `deepseek` profile acting as the sheepdog / quality inspector.
- It is instructed to actually inspect delivered files (not just the worker's claims) and emit a final `VERDICT:` line the runner parses.
- Worker FAILs are redone **without** your intervention; you only see the final pass/abort.
- Skip with `-NoVerify` for trivial tasks.

## Conventions

- Names: `[a-z][a-z0-9_-]{0,31}`, unique among live agents.
- Brief files: pass path as the task text; the worker reads it itself.
- Do not close panes you did not create.
- Reports persist in pane scrollback; use `-Read <name>` to inspect.
