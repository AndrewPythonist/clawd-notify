# Installs clawd-notify: registers Claude Code hooks that show Clawd instead of a plain Windows toast.
#
#   One-liner:   irm https://raw.githubusercontent.com/AndrewPythonist/clawd-notify/main/install.ps1 | iex
#   From a clone: powershell -ExecutionPolicy Bypass -File install.ps1
#
# Safe to run again (updates in place). Existing settings are preserved; a backup is saved as settings.json.bak.

& {
    $ErrorActionPreference = 'Stop'
    $repo = 'AndrewPythonist/clawd-notify'

    # Pretty-prints compact JSON with 2-space indents (PowerShell 5.1's own formatting is hard to read).
    function Format-Json([string]$s) {
        $sb = New-Object Text.StringBuilder
        $ind = 0; $inStr = $false; $esc = $false
        for ($i = 0; $i -lt $s.Length; $i++) {
            $c = $s[$i]
            if ($inStr) {
                [void]$sb.Append($c)
                if ($esc) { $esc = $false } elseif ($c -eq '\') { $esc = $true } elseif ($c -eq '"') { $inStr = $false }
                continue
            }
            if ($c -eq '"') { $inStr = $true; [void]$sb.Append($c) }
            elseif ($c -eq '{' -or $c -eq '[') {
                $close = if ($c -eq '{') { '}' } else { ']' }
                if ($i + 1 -lt $s.Length -and $s[$i + 1] -eq $close) { [void]$sb.Append("$c$close"); $i++ }
                else { $ind++; [void]$sb.Append($c).Append("`n").Append('  ' * $ind) }
            }
            elseif ($c -eq '}' -or $c -eq ']') { $ind--; [void]$sb.Append("`n").Append('  ' * $ind).Append($c) }
            elseif ($c -eq ',') { [void]$sb.Append(",`n").Append('  ' * $ind) }
            elseif ($c -eq ':') { [void]$sb.Append(': ') }
            else { [void]$sb.Append($c) }
        }
        $sb.ToString()
    }

    # 1. Where the scripts live: this folder when run from a clone, otherwise download them.
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'clawd-popup.ps1'))) {
        $dir = $PSScriptRoot
    } else {
        $dir = Join-Path $env:LOCALAPPDATA 'clawd-notify'
        Write-Host "Downloading clawd-notify to $dir ..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $tmp = Join-Path ([IO.Path]::GetTempPath()) "clawd-notify-$PID"
        $zip = "$tmp.zip"
        Invoke-WebRequest "https://github.com/$repo/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing
        Expand-Archive $zip $tmp -Force
        [void](New-Item -ItemType Directory -Force $dir)
        Copy-Item (Join-Path $tmp 'clawd-notify-main\*.ps1') $dir -Force
        Remove-Item $zip, $tmp -Recurse -Force
    }

    # 2. Register the hooks in the user's Claude Code settings.
    $configDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
    $path = if ($env:CLAWD_SETTINGS) { $env:CLAWD_SETTINGS } else { Join-Path $configDir 'settings.json' }
    [void](New-Item -ItemType Directory -Force (Split-Path $path))

    $settings = $null
    if (Test-Path $path) {
        $raw = [IO.File]::ReadAllText($path)
        if ($raw.Trim()) { $settings = $raw | ConvertFrom-Json }
        Copy-Item $path "$path.bak" -Force
    }
    if (-not $settings) { $settings = [pscustomobject]@{} }
    if (-not $settings.hooks) { $settings | Add-Member hooks ([pscustomobject]@{}) -Force }

    $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $dir 'clawd-notify.ps1')`""
    # Stop = Claude finished; Notification only for permission requests and questions (not the idle reminder).
    foreach ($h in @(@{ event = 'Stop'; matcher = $null }, @{ event = 'Notification'; matcher = 'permission_prompt|elicitation_dialog' })) {
        $list = @($settings.hooks.($h.event) | Where-Object { $_ -and -not (@($_.hooks | ForEach-Object { $_.command }) -match 'clawd-notify\.ps1') })
        $entry = [ordered]@{}
        if ($h.matcher) { $entry.matcher = $h.matcher }
        $entry.hooks = @([pscustomobject]@{ type = 'command'; command = $cmd })
        $list += [pscustomobject]$entry
        $settings.hooks | Add-Member $h.event $list -Force
    }

    $json = Format-Json ($settings | ConvertTo-Json -Depth 100 -Compress)
    [IO.File]::WriteAllText($path, $json + "`n", (New-Object Text.UTF8Encoding $false))

    Write-Host ''
    Write-Host 'Clawd is installed!' -ForegroundColor Green
    Write-Host "  scripts:  $dir"
    Write-Host "  hooks:    $path"
    Write-Host ''
    Write-Host 'Start a new Claude Code session to pick up the hooks.'
    Write-Host 'Tip: turn off the Claude desktop app''s own notifications so you do not get two popups.'

    # 3. Say hi.
    Start-Process powershell -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$(Join-Path $dir 'clawd-popup.ps1')`"", '-Variant', 'wave'
    )
}
