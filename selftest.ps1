# herd-flows post-fix selftest (ASCII only: PS 5.1 reads BOM-less UTF-8 as ANSI)
# Covers: 1) parse all .ps1  2) config.json loads  3) native arg escaping roundtrip
#         4) verifier verdict parsing (incl. echo-only anti-rubber-stamp case)  5) herdr smoke
$ErrorActionPreference = 'Stop'
$root = 'D:\devloop\workSpace\app_ZCode\herd-flows'
$fail = 0

# ---------- 1. Parse ----------
$files = @(
    "$root\orchestrator\engine.ps1",
    "$root\orchestrator\verifier.ps1",
    "$root\orchestrator\profile-manager.ps1",
    "$root\orchestrator\adapters\herdr-adapter.ps1",
    "$root\orchestrator\adapters\gateway-adapter.ps1",
    "$root\runner\herdr-pool.ps1",
    "$root\scripts\install-deps.ps1",
    "$root\scripts\start-all.ps1",
    "$root\scripts\start-gui.ps1",
    "$root\scripts\start-proxy.ps1",
    "$root\scripts\start-herdr.ps1",
    "$root\scripts\update-all-upstreams.ps1",
    "$root\proxy\update-cockpit.ps1"
)
foreach ($f in $files) {
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errs)
    if ($errs.Count) { Write-Host "[FAIL] parse: $f"; $errs | ForEach-Object { $_.Message }; $fail++ }
    else { Write-Host "[ok] parse: $(Split-Path $f -Leaf)" }
}

# ---------- 2. config.json ----------
$cfg = Get-Content "$root\runner\config.json" -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host "[ok] config.json profiles: $($cfg.workerProfiles.PSObject.Properties.Name -join ', ')"

# ---------- 3. Native arg escaping roundtrip ----------
$echo = Join-Path $env:TEMP "hf-echo-args.ps1"
@'
Write-Output ("COUNT=" + $args.Count)
$i = 0
foreach ($a in $args) { Write-Output ("ARG$i<<" + $a + ">>"); $i++ }
'@ | Set-Content $echo -Encoding ASCII

. "$root\orchestrator\adapters\herdr-adapter.ps1"

$payload = @(
    'a"b&c%d^e|f<g>h',
    '--',
    'x y z',
    "line1`nline2",
    '%USERNAME% & echo INJECTED',
    'C:\dir with sp\',
    'C:\nospacetrail\'
)
# borrow powershell.exe as the "native exe"; replicate Invoke-Hdr's escaping core
$testArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $echo) + $payload
$safeArgs = foreach ($a in $testArgs) {
    $s = "$a" -replace '"', '\"'
    if ($s -match '\s' -and $s -match '\\+$') { $s += '\' }
    $s
}
$out = (& powershell.exe @safeArgs 2>&1 | ForEach-Object { "$_" }) -join "`n"
# injection check = exact arg count + verbatim bytes: any intermediate shell split/expand breaks COUNT or content
if ($out -notmatch '(?m)^COUNT=7$') { Write-Host "[FAIL] arg count broken: $(($out -split "`n")[0])"; $fail++ }
else { Write-Host "[ok] arg count exact (no shell split/expand)" }
$hits = [regex]::Matches($out, '(?s)ARG(\d+)<<(.*?)>>')
for ($i = 0; $i -lt $payload.Count; $i++) {
    if ($hits[$i].Groups[2].Value -ceq $payload[$i]) { Write-Host "[ok] arg[$i] roundtrip" }
    else { Write-Host "[FAIL] arg[$i]: sent=<<$($payload[$i])>> got=<<$($hits[$i].Groups[2].Value)>>"; $fail++ }
}

# ---------- 4. Verifier verdict parsing ----------
. "$root\orchestrator\verifier.ps1"

$caseA = "fmt spec: VERDICT: <PASS huo FAIL>`nREASONS: <reason>`n`nanswer:`nI checked foo.ps1, complete.`nVERDICT: PASS"
$r = Parse-VerifierVerdict $caseA
if ($r.verdict -eq 'PASS') { Write-Host "[ok] caseA echo+final-PASS -> PASS" } else { Write-Host "[FAIL] caseA: $($r.verdict)"; $fail++ }

$caseB = "fmt spec: VERDICT: <PASS huo FAIL>`n`nanswer:`nfile missing.`nVERDICT: FAIL`nREASONS: deliverable file absent`nREDO: reimplement and write foo.ps1"
$r = Parse-VerifierVerdict $caseB
if ($r.verdict -eq 'FAIL' -and $r.reasons -eq 'deliverable file absent' -and $r.redo -eq 'reimplement and write foo.ps1') {
    Write-Host "[ok] caseB FAIL+REASONS+REDO parsed"
} else { Write-Host "[FAIL] caseB: $($r.verdict) / $($r.reasons) / $($r.redo)"; $fail++ }

$caseC = "fmt spec: VERDICT: <PASS huo FAIL>`nREASONS: <reason>`nREDO: <redo>`n(model timed out, scrollback holds only the echo)"
$r = Parse-VerifierVerdict $caseC
if ($r.verdict -eq 'FAIL') {
    Write-Host "[ok] caseC echo-only no answer -> FAIL (anti rubber-stamp)"
} else { Write-Host "[FAIL] caseC: $($r.verdict)"; $fail++ }

$caseD = "analysis...`nVERDICT: FAIL`nfinal conclusion:`nVERDICT: PASS"
$r = Parse-VerifierVerdict $caseD
if ($r.verdict -eq 'PASS') { Write-Host "[ok] caseD last occurrence wins" } else { Write-Host "[FAIL] caseD: $($r.verdict)"; $fail++ }

# ---------- 5. herdr smoke (read-only status on a scratch session) ----------
$herdr = Find-HerdrExe -ExplicitPath $cfg.PSObject.Properties['herdrExe'].Value
Write-Host "[ok] herdr found: $herdr"
$smoke = Invoke-Hdr $herdr 'hf-selftest' @('status') | Out-String
Write-Host "[ok] herdr smoke (exit=$LASTEXITCODE): $(($smoke.Trim() -split "`r?`n")[0])"

# ---------- Summary ----------
if ($fail -eq 0) { Write-Host "`n=== ALL SELFTESTS PASSED ===" -ForegroundColor Green; exit 0 }
else { Write-Host "`n=== $fail FAILURES ===" -ForegroundColor Red; exit 1 }
