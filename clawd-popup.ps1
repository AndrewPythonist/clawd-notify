# Clawd notification popup (the Claude mascot).
# Manual run:  powershell -ExecutionPolicy Bypass -File clawd-popup.ps1 [-Variant laptop] [-Kind attention] [-Lang en]
param(
    [string]$Data,      # base64(UTF-8 JSON {kind, project, message}), passed by clawd-notify.ps1
    [string]$Variant,   # force a specific pose instead of a random one
    [string]$Kind,      # done | attention
    [string]$Lang,      # ru | en (default: Windows UI language)
    [int]$Seconds = 6,
    [string]$Snapshot   # render the popup to this PNG and exit (used for README images)
)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
. (Join-Path $PSScriptRoot 'clawd-poses.ps1')

$eventKind = 'done'
$project = ''; $message = ''
if ($Data) {
    try {
        $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Data)) | ConvertFrom-Json
        if ($json.kind)    { $eventKind = $json.kind }
        if ($json.project) { $project   = $json.project }
        if ($json.message) { $message   = $json.message }
    } catch {}
}
if ($Kind) { $eventKind = $Kind }   # (PowerShell names are case-insensitive, hence $eventKind)

# --- Texts ---
if (-not $Lang) { $Lang = if ($env:CLAWD_LANG) { $env:CLAWD_LANG } else { [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName } }
$texts = @{
    ru = @{ done = 'Задача готова!'; project = 'Проект: {0}'; finished = 'Claude закончил работу'
            attention = 'Нужно твоё внимание'; waiting = 'Claude ждёт ответа' }
    en = @{ done = 'Task complete!'; project = 'Project: {0}'; finished = 'Claude has finished'
            attention = 'Claude needs you'; waiting = 'Claude is waiting for your reply' }
}
$t = if ($texts.ContainsKey($Lang)) { $texts[$Lang] } else { $texts.en }
if ($eventKind -eq 'attention') {
    $title    = $t.attention
    $subtitle = if ($message) { $message } else { $t.waiting }
} else {
    $title    = $t.done
    $subtitle = if ($project) { $t.project -f $project } else { $t.finished }
}

# --- 8-bit sound, synthesized as a WAV ---
# Notes: @(frequency Hz, duration ms); frequency 0 is a rest.
function New-ClawdSound($notes, [double]$volume) {
    $rate = 22050
    $samples = New-Object System.Collections.Generic.List[int16]
    foreach ($n in $notes) {
        $freq = [double]$n[0]; $count = [int]($rate * $n[1] / 1000)
        for ($i = 0; $i -lt $count; $i++) {
            if ($freq -eq 0) { $samples.Add(0); continue }
            $time = $i / $rate
            $f = $freq * (1 + 0.06 * [Math]::Exp(-$time * 60))   # small upward chirp at note start
            $phase = ($f * $time) % 1.0
            # 25% pulse wave mixed with a sine: a soft, toy-like chiptune voice
            $square = if ($phase -lt 0.25) { 1.0 } else { -1.0 }
            $sine   = [Math]::Sin(2 * [Math]::PI * $f * $time)
            $env    = [Math]::Min(1.0, $i / ($rate * 0.004)) * [Math]::Exp(-$time * 9)
            $samples.Add([int16](32767 * $volume * $env * (0.35 * $square + 0.65 * $sine)))
        }
    }
    $ms = New-Object IO.MemoryStream
    $w  = New-Object IO.BinaryWriter $ms
    $dataLen = $samples.Count * 2
    $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $dataLen))
    $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $w.Write([int]16)
    $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$rate); $w.Write([int]($rate * 2))
    $w.Write([int16]2); $w.Write([int16]16)
    $w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]$dataLen)
    foreach ($s in $samples) { $w.Write($s) }
    $ms.Position = 0
    $ms
}

$volume = 0.11
$melody = if ($eventKind -eq 'attention') {
    @(@(1319, 90), @(0, 45), @(1047, 90), @(0, 45), @(1568, 170))                  # "beep-boop-beep?"
} else {
    @(@(784, 65), @(1047, 65), @(1319, 65), @(1568, 90), @(0, 30), @(2093, 200))   # happy arpeggio
}

# Synthesis in PowerShell is slow, so the WAV is cached in %TEMP%.
# The file name is a hash of melody + volume, so editing either regenerates it automatically.
if (-not $Snapshot) {
    try {
        $key = "$volume|" + (($melody | ForEach-Object { $_ -join ':' }) -join ',')
        $md5 = [Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($key))
        $cacheDir = Join-Path ([IO.Path]::GetTempPath()) 'clawd-notify'
        [void](New-Item -ItemType Directory -Force $cacheDir)
        $wav = Join-Path $cacheDir ('sound-' + [BitConverter]::ToString($md5, 0, 4).Replace('-', '') + '.wav')
        if (-not (Test-Path $wav)) {
            $tmp = "$wav.$PID.tmp"
            [IO.File]::WriteAllBytes($tmp, (New-ClawdSound $melody $volume).ToArray())
            try { Move-Item $tmp $wav -ErrorAction Stop } catch { Remove-Item $tmp -ErrorAction SilentlyContinue }
        }
        $script:player = New-Object Media.SoundPlayer $wav
    } catch {
        try { $script:player = New-Object Media.SoundPlayer (New-ClawdSound $melody $volume) } catch {}
    }
}

# --- Window ---
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ShowActivated="False"
        ResizeMode="NoResize" SizeToContent="WidthAndHeight">
  <Grid x:Name="Root" Margin="16" Opacity="0">
    <Grid.RenderTransform><TranslateTransform x:Name="Slide" X="420"/></Grid.RenderTransform>
    <Border CornerRadius="16" Background="#F2262624" BorderBrush="#33FFFFFF" BorderThickness="1"
            Padding="16,14,22,14" Cursor="Hand">
      <Border.Effect><DropShadowEffect BlurRadius="18" ShadowDepth="3" Opacity="0.5"/></Border.Effect>
      <StackPanel Orientation="Horizontal">
        <Canvas x:Name="Clawd" Width="100" Height="70" VerticalAlignment="Center">
          <Canvas.RenderTransform><TranslateTransform x:Name="Hop" Y="0"/></Canvas.RenderTransform>
        </Canvas>
        <StackPanel Margin="16,0,0,0" VerticalAlignment="Center" MaxWidth="270">
          <TextBlock x:Name="TitleText" Foreground="#FAF9F5" FontSize="15" FontWeight="SemiBold"
                     FontFamily="Segoe UI"/>
          <TextBlock x:Name="SubText" Foreground="#B5B3AA" FontSize="12.5" FontFamily="Segoe UI"
                     Margin="0,3,0,0" TextWrapping="Wrap" MaxHeight="52" TextTrimming="CharacterEllipsis"/>
        </StackPanel>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Parse($xaml)
$root   = $window.FindName('Root')
$slide  = $window.FindName('Slide')
$hop    = $window.FindName('Hop')
$canvas = $window.FindName('Clawd')
$window.FindName('TitleText').Text = $title
$window.FindName('SubText').Text   = $subtitle

# --- Pick a pose and draw each frame on its own layer; animation just toggles visibility ---
$pool = if ($Variant) { $ClawdPoses | Where-Object { $_.name -eq $Variant } }
        else { $ClawdPoses | Where-Object { ($_.kinds -split ',') -contains $eventKind } }
$pose = $pool | Get-Random
if (-not $pose) { $pose = $ClawdPoses[0] }

$px = 5
$brushes = @{}
foreach ($k in $ClawdPalette.Keys) { $brushes[$k] = [Windows.Media.BrushConverter]::new().ConvertFromString($ClawdPalette[$k]) }
$layers = foreach ($spec in $pose.frames) {
    $layer = [Windows.Controls.Canvas]@{ Width = 100; Height = 70; Visibility = 'Hidden' }
    $grid = Get-ClawdFrame $spec
    for ($y = 0; $y -lt $ClawdHeight; $y++) {
        for ($x = 0; $x -lt $ClawdWidth; $x++) {
            $c = [string]$grid[$y][$x]
            if ($c -eq '.') { continue }
            $r = [Windows.Shapes.Rectangle]@{ Width = $px + 0.5; Height = $px + 0.5; Fill = $brushes[$c] }
            [Windows.Controls.Canvas]::SetLeft($r, $x * $px)
            [Windows.Controls.Canvas]::SetTop($r, $y * $px)
            [void]$layer.Children.Add($r)
        }
    }
    [void]$canvas.Children.Add($layer)
    $layer
}
$layers = @($layers)
$layers[0].Visibility = 'Visible'
$script:frame = 0

# --- Snapshot mode: render once to PNG and exit ---
if ($Snapshot) {
    $slide.X = 0; $root.Opacity = 1
    $window.Left = -10000; $window.Top = -10000
    $window.Add_ContentRendered({
        $scale = 2
        $bmp = [Windows.Media.Imaging.RenderTargetBitmap]::new(
            [int]($window.ActualWidth * $scale), [int]($window.ActualHeight * $scale), 96 * $scale, 96 * $scale,
            [Windows.Media.PixelFormats]::Pbgra32)
        $bmp.Render($window)
        $enc = [Windows.Media.Imaging.PngBitmapEncoder]::new()
        $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
        $fs = [IO.File]::Create($Snapshot); $enc.Save($fs); $fs.Close()
        $window.Close()
    })
    [void]$window.ShowDialog()
    return
}

# --- Animations ---
function New-Anim($from, $to, $ms, [switch]$Ease) {
    $a = [Windows.Media.Animation.DoubleAnimation]::new($from, $to, [TimeSpan]::FromMilliseconds($ms))
    if ($Ease) { $a.EasingFunction = [Windows.Media.Animation.CubicEase]@{ EasingMode = 'EaseOut' } }
    $a
}

$script:closing = $false
function Hide-Popup {
    if ($script:closing) { return }
    $script:closing = $true
    $out = New-Anim 0 420 280
    $out.Add_Completed({ $window.Close() })
    $slide.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $out)
    $root.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Anim 1 0 280))
}

# Stack slot: simultaneous notifications stack upwards instead of covering each other.
# Each slot is a named mutex held by this process while the popup is open.
$script:slot = 0; $script:slotMutex = $null
for ($i = 0; $i -lt 5; $i++) {
    $m = New-Object Threading.Mutex($false, "Local\ClawdSlot$i")
    try { $got = $m.WaitOne(0) } catch [Threading.AbandonedMutexException] { $got = $true }
    if ($got) { $script:slot = $i; $script:slotMutex = $m; break }
    $m.Dispose()
}
$window.Add_Closed({ if ($script:slotMutex) { $script:slotMutex.ReleaseMutex() } })

$window.Add_Loaded({
    $wa = [Windows.SystemParameters]::WorkArea
    $window.Left = $wa.Right - $window.ActualWidth
    # 16 = Root's transparent margin; neighbours overlap it so the gap between cards stays even
    $window.Top  = $wa.Bottom - $window.ActualHeight - $script:slot * ($window.ActualHeight - 16)

    $slide.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, (New-Anim 420 0 420 -Ease))
    $root.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Anim 0 1 300))

    if ($pose.hop) {
        $jump = New-Anim 0 -8 160 -Ease
        $jump.AutoReverse = $true
        $jump.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::new(3)
        $jump.BeginTime = [TimeSpan]::FromMilliseconds(350)
        $hop.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $jump)
    }

    if ($script:player) { $script:player.Play() }
    $closeTimer.Start()
    if ($layers.Count -gt 1) { $frameTimer.Start() }
})

$frameTimer = [Windows.Threading.DispatcherTimer]@{ Interval = [TimeSpan]::FromMilliseconds($pose.ms) }
$frameTimer.Add_Tick({
    $layers[$script:frame].Visibility = 'Hidden'
    $script:frame = ($script:frame + 1) % $layers.Count
    $layers[$script:frame].Visibility = 'Visible'
})

# Auto-close; paused while the mouse is over the popup. Click closes immediately.
$closeTimer = [Windows.Threading.DispatcherTimer]@{ Interval = [TimeSpan]::FromSeconds($Seconds) }
$closeTimer.Add_Tick({ $closeTimer.Stop(); Hide-Popup })
$window.Add_MouseEnter({ $closeTimer.Stop() })
$window.Add_MouseLeave({ if (-not $script:closing) { $closeTimer.Start() } })
$window.Add_MouseLeftButtonDown({ Hide-Popup })

[void]$window.ShowDialog()
