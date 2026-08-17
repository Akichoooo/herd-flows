# legacy（claw-proxy 时代归档）

这些文件是旧版 subclaw（基于 claw-proxy :4748 + run-claw-pool.sh）的产物。
claw-proxy 已退役，被 cockpit-cliproxy 网关池（gateway/）替代。
保留归档不删，供追溯历史决策和回滚参考。

## 文件说明

- `run-claw-pool.sh` — 旧版 worker 池 runner（spawn claude -p 子进程）
- `claw-keys.tsv` — 旧版 Mimo key 池（直连模式）
- `claw-keys.sensenova.tsv` — SenseNova 直连 key 池（未实际使用）
- `subclaw-dispatch.sh` — Dragnet 侧启动器（WSL bash，包装 run-claw-pool.sh）
- `claw-shim.sh` — WSL 里 claude.exe 的 shim

不要在新工作中使用这些文件。新版编排走 `runner/herdr-pool.ps1`。
