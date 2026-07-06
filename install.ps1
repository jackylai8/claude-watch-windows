<#
  claude-watch-windows installer (PowerShell)

  NOTE: On managed / corporate Windows the PowerShell execution policy is often
  enforced by Group Policy, which even -ExecutionPolicy Bypass cannot override.
  If this script is blocked, use the Git Bash installer instead:  bash install.sh

  Installs a 3-line Claude Code status line plus the /tok token marker.
  Idempotent. Merges into an existing settings.json without clobbering other
  keys or hooks, backs it up first, and removes obsolete fetch-usage.sh hooks.

  Usage:  powershell -ExecutionPolicy Bypass -File .\install.ps1
          (if blocked:  first run  Unblock-File .\install.ps1  , or use install.sh)
#>

$ErrorActionPreference = 'Stop'

try {
    $pkg        = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (-not $pkg) { throw "Could not resolve the script folder. Run it as a file: powershell -ExecutionPolicy Bypass -File .\install.ps1" }
    $claudeDir  = Join-Path $env:USERPROFILE '.claude'
    $cmdDir     = Join-Path $claudeDir 'commands'
    $settings   = Join-Path $claudeDir 'settings.json'

    Write-Host "claude-watch-windows installer" -ForegroundColor Cyan
    Write-Host "Target: $claudeDir`n"

    # --- 0. preflight: required files present? ---
    foreach ($f in @('statusline-command.sh','tokmark.sh','commands\tok.md')) {
        if (-not (Test-Path (Join-Path $pkg $f))) {
            throw "Missing file '$f' next to install.ps1. Download the whole repo, not just the installer."
        }
    }

    # --- 1. ensure dirs exist ---
    foreach ($d in @($claudeDir, $cmdDir)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    }

    # --- 2. copy scripts + slash command ---
    Copy-Item (Join-Path $pkg 'statusline-command.sh') $claudeDir -Force
    Copy-Item (Join-Path $pkg 'tokmark.sh')            $claudeDir -Force
    Copy-Item (Join-Path $pkg 'commands\tok.md')       $cmdDir    -Force
    Write-Host "[ok] copied statusline-command.sh, tokmark.sh, commands\tok.md"

    # --- 3. ensure jq (prefer bundled, then PATH, then ~/.claude, then winget) ---
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
            Write-Host "[!!] Could not install jq. Drop a jq.exe into $claudeDir and re-run." -ForegroundColor Red
        }
    }

    # --- 4. merge settings.json (preserve existing keys/hooks) ---
    if (Test-Path $settings) {
        try { $cfg = Get-Content $settings -Raw | ConvertFrom-Json }
        catch { throw "Existing settings.json is not valid JSON. Fix or remove it, then re-run. (Left untouched.)" }
        Copy-Item $settings "$settings.bak-statusline" -Force
        Write-Host "[ok] backed up settings.json -> settings.json.bak-statusline"
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

    # Remove any legacy fetch-usage.sh hooks (rate limits now come from stdin).
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
    $json = $json -replace '\\u003e','>' -replace '\\u003c','<' -replace '\\u0026','&' -replace '\\u0027',"'"
    [System.IO.File]::WriteAllText($settings, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "[ok] merged statusLine into settings.json"

    Write-Host "`nDone. Restart Claude Code to see the status line." -ForegroundColor Green
    Write-Host "Arm the token marker with /tok (or 'bash ~/.claude/tokmark.sh'); /tok clear to reset." -ForegroundColor Green
}
catch {
    Write-Host "`n[FAILED] $($_.Exception.Message)" -ForegroundColor Red
    if ($_.InvocationInfo) { Write-Host ("  at" + $_.InvocationInfo.PositionMessage) -ForegroundColor DarkGray }
    Write-Host "If PowerShell is blocking scripts on a managed PC, use Git Bash instead:  bash install.sh" -ForegroundColor Yellow
}
finally {
    # keep the window open so errors are readable when launched by double-click
    if ($Host.Name -eq 'ConsoleHost') { Read-Host "`nPress Enter to close" | Out-Null }
}
