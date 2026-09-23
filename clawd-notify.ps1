# Claude Code hook entry point (Stop / Notification).
# Reads the hook JSON from stdin, starts clawd-popup.ps1 as a detached process and exits right away,
# so Claude is never kept waiting. The popup builds the texts itself.

$hook = $null
if ([Console]::IsInputRedirected) {
    [Console]::InputEncoding = [Text.Encoding]::UTF8
    try { $hook = [Console]::In.ReadToEnd() | ConvertFrom-Json } catch {}
}

if ($hook.hook_event_name -eq 'Notification') {
    $payload = @{ kind = 'attention'; message = $hook.message }
} else {
    $payload = @{ kind = 'done'; project = if ($hook.cwd) { Split-Path $hook.cwd -Leaf } else { '' } }
}

$json = $payload | ConvertTo-Json -Compress
$b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))

$popup = Join-Path $PSScriptRoot 'clawd-popup.ps1'
Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$popup`"", '-Data', $b64
)
