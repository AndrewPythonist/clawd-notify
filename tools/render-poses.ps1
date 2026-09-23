# Renders every Clawd pose into poses/ (animated GIF + static PNG) and popup previews into docs/.
# Re-run after editing clawd-poses.ps1:  powershell -ExecutionPolicy Bypass -File tools\render-poses.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root 'clawd-poses.ps1')
Add-Type -AssemblyName System.Drawing

$posesDir = Join-Path $root 'poses'
$docsDir  = Join-Path $root 'docs'
[void](New-Item -ItemType Directory -Force $posesDir, $docsDir)

$scale = 8   # screen pixels per sprite pixel
$pad   = 1   # empty sprite pixels around the field
$bg    = '#262624'

# --- Palette: index 0 = background, then the pose colors; GIF needs exactly 16 entries ---
$keys = @($ClawdPalette.Keys)
$colors = @($bg) + @($keys | ForEach-Object { $ClawdPalette[$_] })
while ($colors.Count -lt 16) { $colors += '#000000' }
$index = @{}
for ($i = 0; $i -lt $keys.Count; $i++) { $index[[string]$keys[$i]] = [byte]($i + 1) }

function Get-FramePixels([string]$spec) {
    $grid = Get-ClawdFrame $spec
    $w = ($ClawdWidth + 2 * $pad) * $scale; $h = ($ClawdHeight + 2 * $pad) * $scale
    $pixels = New-Object byte[] ($w * $h)
    for ($y = 0; $y -lt $ClawdHeight; $y++) {
        for ($x = 0; $x -lt $ClawdWidth; $x++) {
            $c = [string]$grid[$y][$x]
            if ($c -eq '.') { continue }
            $v = $index[$c]
            for ($dy = 0; $dy -lt $scale; $dy++) {
                $row = (($y + $pad) * $scale + $dy) * $w + ($x + $pad) * $scale
                for ($dx = 0; $dx -lt $scale; $dx++) { $pixels[$row + $dx] = $v }
            }
        }
    }
    , $pixels
}

# --- Minimal GIF89a writer ---
# LZW is emitted "uncompressed": a clear code every 12 pixels keeps the code width fixed at 5 bits,
# which every decoder accepts. Files stay small because the sprites are tiny.
function Get-LzwBlocks([byte[]]$pixels) {
    $codes = New-Object System.Collections.Generic.List[int]
    $codes.Add(16)   # clear
    $n = 0
    foreach ($p in $pixels) {
        if ($n -eq 12) { $codes.Add(16); $n = 0 }
        $codes.Add($p); $n++
    }
    $codes.Add(17)   # end of information

    $out = New-Object System.Collections.Generic.List[byte]
    $acc = 0; $nbits = 0
    foreach ($code in $codes) {
        $acc = $acc -bor ($code -shl $nbits); $nbits += 5
        while ($nbits -ge 8) { $out.Add([byte]($acc -band 0xFF)); $acc = $acc -shr 8; $nbits -= 8 }
    }
    if ($nbits -gt 0) { $out.Add([byte]($acc -band 0xFF)) }

    $blocks = New-Object System.Collections.Generic.List[byte]
    $blocks.Add(4)   # LZW minimum code size
    for ($i = 0; $i -lt $out.Count; $i += 255) {
        $len = [Math]::Min(255, $out.Count - $i)
        $blocks.Add([byte]$len)
        $blocks.AddRange($out.GetRange($i, $len))
    }
    $blocks.Add(0)
    , $blocks.ToArray()
}

function Save-Gif([string]$path, $frames, [int]$delayMs) {
    $w = ($ClawdWidth + 2 * $pad) * $scale; $h = ($ClawdHeight + 2 * $pad) * $scale
    $fs = [IO.File]::Create($path)
    $bw = New-Object IO.BinaryWriter $fs
    $bw.Write([Text.Encoding]::ASCII.GetBytes('GIF89a'))
    $bw.Write([uint16]$w); $bw.Write([uint16]$h)
    $bw.Write([byte]0xF3); $bw.Write([byte]0); $bw.Write([byte]0)       # 16-color global table
    foreach ($c in $colors) { $col = [Drawing.ColorTranslator]::FromHtml($c); $bw.Write([byte[]]@($col.R, $col.G, $col.B)) }
    $bw.Write([byte[]]@(0x21, 0xFF, 0x0B)); $bw.Write([Text.Encoding]::ASCII.GetBytes('NETSCAPE2.0'))
    $bw.Write([byte[]]@(3, 1, 0, 0, 0))                                  # loop forever
    foreach ($f in $frames) {
        $bw.Write([byte[]]@(0x21, 0xF9, 4, 0x04)); $bw.Write([uint16]([int]($delayMs / 10))); $bw.Write([byte[]]@(0, 0))
        $bw.Write([byte]0x2C); $bw.Write([uint16]0); $bw.Write([uint16]0); $bw.Write([uint16]$w); $bw.Write([uint16]$h); $bw.Write([byte]0)
        $bw.Write((Get-LzwBlocks $f))
    }
    $bw.Write([byte]0x3B)
    $bw.Close()
}

function Save-Png([string]$path, [string]$spec) {
    $grid = Get-ClawdFrame $spec
    $s = 10
    $bmp = New-Object Drawing.Bitmap ($ClawdWidth * $s), ($ClawdHeight * $s)
    $g = [Drawing.Graphics]::FromImage($bmp)
    for ($y = 0; $y -lt $ClawdHeight; $y++) {
        for ($x = 0; $x -lt $ClawdWidth; $x++) {
            $c = [string]$grid[$y][$x]
            if ($c -eq '.') { continue }
            $br = New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml($ClawdPalette[$c]))
            $g.FillRectangle($br, $x * $s, $y * $s, $s, $s)
            $br.Dispose()
        }
    }
    $g.Dispose(); $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}

foreach ($pose in $ClawdPoses) {
    $frames = @($pose.frames | ForEach-Object { , (Get-FramePixels $_) })
    Save-Gif (Join-Path $posesDir "$($pose.name).gif") $frames $pose.ms
    Save-Png (Join-Path $posesDir "$($pose.name).png") $pose.frames[0]
    Write-Host "  $($pose.name)"
}

# --- Popup previews for the README ---
$popup = Join-Path $root 'clawd-popup.ps1'
$shots = @(
    @{ file = 'popup-en.png';           args = @('-Lang', 'en', '-Variant', 'laptop') }
    @{ file = 'popup-ru.png';           args = @('-Lang', 'ru', '-Variant', 'laptop') }
    @{ file = 'popup-attention-en.png'; args = @('-Lang', 'en', '-Kind', 'attention', '-Variant', 'alert') }
    @{ file = 'popup-attention-ru.png'; args = @('-Lang', 'ru', '-Kind', 'attention', '-Variant', 'alert') }
)
foreach ($s in $shots) {
    & powershell -NoProfile -ExecutionPolicy Bypass -STA -File $popup @($s.args) -Snapshot (Join-Path $docsDir $s.file)
    Write-Host "  docs/$($s.file)"
}
