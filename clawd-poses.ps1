# Clawd poses: pixel data shared by clawd-popup.ps1 and tools/render-poses.ps1.
# Dot-source it:  . "$PSScriptRoot\clawd-poses.ps1"
#
# Field is 20x14 pixels. Base Clawd: body x5..14, arms x4/x15 (rows 8-9), eyes x7/x12 (rows 7-8), legs at the bottom.
$ClawdWidth  = 20
$ClawdHeight = 14
$ClawdBase = @(
    '....................',
    '....................',
    '....................',
    '....................',
    '....................',
    '.....##########.....',
    '.....##########.....',
    '.....##E####E##.....',
    '....###E####E###....',
    '....############....',
    '.....##########.....',
    '.....##########.....',
    '......#.#..#.#......',
    '......#.#..#.#......'
)
$ClawdPalette = [ordered]@{
    '#' = '#D97757'  # Clawd orange
    'E' = '#111111'  # eyes
    'W' = '#FFFFFF'
    'S' = '#C9C9CE'  # light gray
    'D' = '#5C5D63'  # dark gray
    'Y' = '#F5C542'  # yellow / gold
    'O' = '#D9A12B'  # dark gold
    'R' = '#F27A9B'  # pink
    'P' = '#9B7BF0'  # purple
    'C' = '#5CC8F0'  # light blue
    'N' = '#7A4A2E'  # brown
    'L' = '#6BCB77'  # light green
    'G' = '#3DAA55'  # check green
}

# A frame is the base sprite plus edits:
#   "x,y=c"            one pixel of palette color c
#   "x1-x2,y1-y2=c"    a filled rectangle
#   "_"                as a color erases the pixel
#   "dx=N"             shifts the whole base sprite horizontally first
# Pixels outside the 20x14 field are ignored, so a typo in a pose never crashes the popup.
function Get-ClawdFrame([string]$spec) {
    $dx = 0
    if ($spec -match 'dx=(-?\d+)') { $dx = [int]$Matches[1] }
    $grid = foreach ($row in $ClawdBase) {
        $line = New-Object char[] $ClawdWidth
        for ($x = 0; $x -lt $ClawdWidth; $x++) {
            $sx = $x - $dx
            $line[$x] = if ($sx -ge 0 -and $sx -lt $ClawdWidth) { $row[$sx] } else { '.' }
        }
        , $line
    }
    foreach ($tok in ($spec -split '\s+')) {
        if ($tok -notmatch '^(\d+)(?:-(\d+))?,(\d+)(?:-(\d+))?=(.)$') { continue }
        $x1 = [int]$Matches[1]; $x2 = if ($Matches[2]) { [int]$Matches[2] } else { $x1 }
        $y1 = [int]$Matches[3]; $y2 = if ($Matches[4]) { [int]$Matches[4] } else { $y1 }
        $c  = if ($Matches[5] -eq '_') { '.' } else { [char]$Matches[5] }
        for ($y = $y1; $y -le [Math]::Min($y2, $ClawdHeight - 1); $y++) {
            for ($x = $x1; $x -le [Math]::Min($x2, $ClawdWidth - 1); $x++) { $grid[$y][$x] = $c }
        }
    }
    , $grid
}

# Spec helpers
function Get-HeartSpec([int]$x, [int]$y, [switch]$Small) {   # 5x4 heart, or 3x3 with -Small
    if ($Small) { return "$x,$y=R $($x+2),$y=R $x-$($x+2),$($y+1)=R $($x+1),$($y+2)=R" }
    "$($x+1),$y=R $($x+3),$y=R $x-$($x+4),$($y+1)=R $($x+1)-$($x+3),$($y+2)=R $($x+2),$($y+3)=R"
}
function Get-FlagSpec([switch]$Wave) {   # 5x4 checkered flag at x15-19; -Wave ripples the far half
    $t = for ($x = 15; $x -le 19; $x++) {
        $dy = if ($Wave -and $x -ge 17) { 1 } else { 0 }
        for ($r = 0; $r -lt 4; $r++) { "$x,$($r + $dy)=" + $(if (($x + $r) % 2) { 'W' } else { 'D' }) }
    }
    $t -join ' '
}

# Reusable pieces
$armsUp    = '4,8-9=_ 15,8-9=_ 4,7=# 3,5-6=# 15,7=# 16,5-6=#'
$cheerLeft = '2,8-9=_ 2,7=# 1,5-6=#'               # left arm up, for poses shifted with dx=-2
$happyEyes = '7,8=# 12,8=# 6,8=E 8,8=E 11,8=E 13,8=E'
$blush     = '6,9=R 13,9=R'
$laptop    = '3-16,10-12=D 9-10,11=W 2-17,13=S'   # laptop lid seen from behind
$mug       = '16-18,8=N 16-18,9-11=W 19,9-10=W'
$hat       = '7-12,4=P 8-11,3=P 9-10,2=P 9-10,1=Y 8,4=Y 11,4=Y 10,3=Y'
$trophy    = '13-17,0=Y 11-12,1=O 13-17,1=Y 14,1=W 18-19,1=O 11,2=O 13-17,2=Y 19,2=O 12-13,3=O 14-16,3=Y 17-18,3=O 14,4=O 15,4=Y 16,4=O 15,5=O 14-16,6=O'
$check     = '19,0=G 18-19,1=G 13,2=G 17-18,2=G 13-14,3=G 16-17,3=G 14-16,4=G 15,5=G'
$bang      = '17,0-2=Y 17,4=Y'
$qmark     = '15-17,0=C 17,1=C 16,2=C 16,4=C'

# kinds: which events use the pose (done = task finished, attention = Claude needs you)
# ms: frame duration; hop: bounce when the popup appears
$ClawdPoses = @(
    @{ name = 'cheer';    kinds = 'done';           ms = 260; hop = $true;  frames = @($armsUp, '') }
    @{ name = 'wave';     kinds = 'done,attention'; ms = 230; hop = $true;  frames = @('15,8-9=_ 15,7=# 16,5-6=#', '15,9=_ 16,7-8=#') }
    @{ name = 'laptop';   kinds = 'done';           ms = 170; hop = $false; frames = @("$laptop 4,8=_ 4,7=#", "$laptop 15,8=_ 15,7=#") }
    @{ name = 'coffee';   kinds = 'done';           ms = 380; hop = $false; frames = @("$mug 16,6=S 17,5=S 16,4=S", "$mug 18,6=S 17,5=S 18,4=S") }
    @{ name = 'party';    kinds = 'done';           ms = 300; hop = $true;  frames = @("$hat $armsUp 1,1=Y 17,2=R 1,6=C 18,6=L 1,10=R 18,11=Y", "$hat 2,2=R 16,1=C 1,5=L 18,5=Y 2,11=Y 18,9=R") }
    @{ name = 'love';     kinds = 'done';           ms = 320; hop = $true;  frames = @("$happyEyes $blush $(Get-HeartSpec 15 2) $(Get-HeartSpec 1 5 -Small)", "$happyEyes $blush $(Get-HeartSpec 15 1) $(Get-HeartSpec 1 4 -Small)", "$happyEyes $blush $(Get-HeartSpec 15 0) $(Get-HeartSpec 1 3 -Small)") }
    @{ name = 'dance';    kinds = 'done';           ms = 260; hop = $false; frames = @('dx=-1 3,8-9=_ 3,7=# 2,5-6=# 17,1-3=Y 16,3=Y 18,1=Y', 'dx=1 16,8-9=_ 16,7=# 17,5-6=# 2,1-3=Y 1,3=Y 3,1=Y') }
    @{ name = 'trophy';   kinds = 'done';           ms = 320; hop = $true;  frames = @("dx=-2 $cheerLeft 13,9=_ 14,7=# $trophy 9,1=W 0,2=W 19,5=W", "dx=-2 $cheerLeft 13,9=_ 14,7=# $trophy 10,3=W 3,1=W 18,7=W") }
    @{ name = 'check';    kinds = 'done';           ms = 450; hop = $true;  frames = @("dx=-2 $cheerLeft $check", "dx=-2 $cheerLeft $check 11,0=W 19,4=W 17,6=W") }
    @{ name = 'finish';   kinds = 'done';           ms = 280; hop = $true;  frames = @("dx=-2 $cheerLeft 14,0-11=S $(Get-FlagSpec)", "dx=-2 $cheerLeft 14,0-11=S $(Get-FlagSpec -Wave)") }
    @{ name = 'alert';    kinds = 'attention';      ms = 320; hop = $true;  frames = @($bang, '') }
    @{ name = 'confused'; kinds = 'attention';      ms = 520; hop = $false; frames = @($qmark, "$qmark 7,8=# 12,8=# 7,6=E 12,6=E") }
)
