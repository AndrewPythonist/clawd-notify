# Removes the clawd-notify hooks from Claude Code settings. Other settings and hooks are left untouched.
#
#   powershell -ExecutionPolicy Bypass -File uninstall.ps1

& {
    $ErrorActionPreference = 'Stop'

    $configDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
    $path = if ($env:CLAWD_SETTINGS) { $env:CLAWD_SETTINGS } else { Join-Path $configDir 'settings.json' }
    if (-not (Test-Path $path)) { Write-Host "Nothing to do: $path not found."; return }

    $raw = [IO.File]::ReadAllText($path)
    $settings = if ($raw.Trim()) { $raw | ConvertFrom-Json } else { $null }
    if (-not $settings -or -not $settings.hooks) { Write-Host 'Nothing to do: no hooks found.'; return }

    Copy-Item $path "$path.bak" -Force
    foreach ($event in @($settings.hooks.PSObject.Properties.Name)) {
        $list = @($settings.hooks.$event | Where-Object { $_ -and -not (@($_.hooks | ForEach-Object { $_.command }) -match 'clawd-notify\.ps1') })
        if ($list.Count) { $settings.hooks | Add-Member $event $list -Force }
        else { $settings.hooks.PSObject.Properties.Remove($event) }
    }
    if (-not @($settings.hooks.PSObject.Properties).Count) { $settings.PSObject.Properties.Remove('hooks') }

    # Same 2-space formatting as install.ps1
    $s = $settings | ConvertTo-Json -Depth 100 -Compress
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
    [IO.File]::WriteAllText($path, $sb.ToString() + "`n", (New-Object Text.UTF8Encoding $false))

    Remove-Item (Join-Path ([IO.Path]::GetTempPath()) 'clawd-notify') -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host 'Clawd hooks removed.' -ForegroundColor Green
    Write-Host "You can now delete the scripts folder: $PSScriptRoot"
}
