<#
  claude-watch-windows installer

  Installs a 3-line Claude Code status line (model + git | cost + in/out tokens |
  rate limits + context + duration) plus the /tok token marker.

  Safe to run repeatedly (idempotent). Merges into an existing settings.json
  without clobbering other keys or hooks, and backs it up first.

  Usage:  right-click > "Run with PowerShell"   OR
          powershell -ExecutionPolicy Bypass -File .\install.ps1
#>

$ErrorActionPreference = 'Stop'
$pkg        = Split-Path -Parent $MyInvocation.MyCommand.Path
$claudeDir  = Join-Path $env:USERPROFILE '.claude'
$cmdDir     = Join-Path $claudeDir 'commands'
$settings   = Join-Path $claudeDir 'settings.json'

Write-Host "claude-watch-windows installer" -ForegroundColor Cyan
Write-Host "Target: $claudeDir`n"

# --- 1. ensure dirs exist ---
foreach ($d in @($claudeDir, $cmdDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

# --- 2. copy scripts + slash command ---
Copy-Item (Join-Path $pkg 'statusline-command.sh') $claudeDir -Force
Copy-Item (Join-Path $pkg 'tokmark.sh')            $claudeDir -Force
Copy-Item (Join-Path $pkg 'commands\tok.md')       $cmdDir    -Force
Write-Host "[ok] copied statusline-command.sh, tokmark.sh, commands\tok.md"

# --- 3. ensure jq is available (scripts prepend ~/.claude to PATH) ---
$jqDest    = Join-Path $claudeDir 'jq.exe'
$jqBundled = Join-Path $pkg 'jq.exe'
if (Test-Path $jqBundled) {
    Copy-Item $jqBundled $jqDest -Force
    Write-Host "[ok] installed bundled jq.exe"
} elseif (Get-Command jq -ErrorAction SilentlyContinue) {
    Write-Host "[ok] jq found on PATH"
} elseif (Test-Path $jqDest) {
    Write-Host "[ok] jq.exe already present in ~/.claude"
} else {
    Write-Host "[..] jq not found; trying winget..." -ForegroundColor Yellow
    try {
        winget install --id jqlang.jq --source winget --accept-source-agreements --accept-package-agreements --silent | Out-Null
        Write-Host "[ok] installed jq via winget (restart your terminal so it lands on PATH)"
    } catch {
        Write-Host "[!!] Could not install jq automatically. Install it (winget install jqlang.jq)" -ForegroundColor Red
        Write-Host "     or drop a jq.exe into $claudeDir, then re-run." -ForegroundColor Red
    }
}

# --- 4. merge settings.json (preserve existing keys/hooks) ---
if (Test-Path $settings) {
    Copy-Item $settings "$settings.bak-statusline" -Force
    Write-Host "[ok] backed up settings.json -> settings.json.bak-statusline"
    $cfg = Get-Content $settings -Raw | ConvertFrom-Json
} else {
    $cfg = [PSCustomObject]@{}
}

function Set-Prop($obj, $name, $value) {
    if ($obj.PSObject.Properties[$name]) { $obj.$name = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}

Set-Prop $cfg 'statusLine' ([PSCustomObject]@{
    type    = 'command'
    command = 'bash ~/.claude/statusline-command.sh'
})

# Remove any legacy fetch-usage.sh hooks (rate limits now come from stdin, so
# the old background API fetch is obsolete). Leaves all other hooks untouched.
if ($cfg.PSObject.Properties['hooks']) {
    foreach ($event in @('PreToolUse','Stop')) {
        if ($cfg.hooks.PSObject.Properties[$event]) {
            $kept = @($cfg.hooks.$event | Where-Object {
                -not (@($_.hooks) | Where-Object { $_.command -match 'fetch-usage\.sh' })
            })
            if ($kept.Count -eq 0) { $cfg.hooks.PSObject.Properties.Remove($event) }
            else { $cfg.hooks.$event = $kept }
        }
    }
}

$json = $cfg | ConvertTo-Json -Depth 20
# PS 5.1 escapes > < & ' as \uXXXX; un-escape for readability (still valid JSON)
$json = $json -replace '\\u003e','>' -replace '\\u003c','<' -replace '\\u0026','&' -replace '\\u0027',"'"
[System.IO.File]::WriteAllText($settings, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[ok] merged statusLine into settings.json"

Write-Host "`nDone. Restart Claude Code to see the status line." -ForegroundColor Green
Write-Host "Arm the token marker with /tok (or 'bash ~/.claude/tokmark.sh'); /tok clear to reset." -ForegroundColor Green
