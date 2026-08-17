#!/bin/sh
# subclaw-dispatch.sh - Dragnet side launcher for the claw pool.
# Usage: bash scripts/subclaw-dispatch.sh [-j N] [-T SEC] brief1.md brief2.md ...
set -e

CLAW_SCRIPT="/mnt/c/Users/92586/.claude/scripts/run-claw-pool.sh"
CLAUDE_EXE="/mnt/c/Users/92586/.local/bin/claude.exe"
WORKDIR="/mnt/d/devloop/workSpace/app_ZCode/Dragnet"

# Shim: pool script needs bare `claude` on PATH; provide one that execs claude.exe.
# /tmp is wiped on WSL restarts, so always (re)install from the repo copy.
mkdir -p /tmp/clawbin
cp "$(dirname "$0")/claw-shim.sh" /tmp/clawbin/claude
chmod +x /tmp/clawbin/claude
export PATH="/tmp/clawbin:$PATH"

# Convert any Windows-style brief paths to /mnt form.
ARGS=""
for arg in "$@"; do
  case "$arg" in
    D:\\*|D:/*) ARG="/mnt/d/$(echo "$arg" | sed -e 's#^[Dd]:##' -e 's#\\#/#g' -e 's#^/##')";;
    *) ARG="$arg";;
  esac
  ARGS="$ARGS $ARG"
done

# shellcheck disable=SC2086
# --no-tree: WSL 里没有裸 python（只有 python3），tree UI 会把编排器卡死在初始化。
# -m 显式指定模型：proxy 模式下 MODEL 环境变量会被 default_model 覆盖，必须用 -m。
exec env MODEL="${MODEL:-deepseek-v4-flash}" bash "$CLAW_SCRIPT" --bash --no-tree -m "${MODEL:-deepseek-v4-flash}" -w "$WORKDIR" $ARGS
