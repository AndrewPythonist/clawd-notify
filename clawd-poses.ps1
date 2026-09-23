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
    'K' = '#111111'  # sunglasses
    'W' = '#FFFFFF'
    'S' = '#C9C9CE'  # light gray
    'D' = '#5C5D63'  # laptop lid
    'Y' = '#F5C542'  # yellow / gold
    'O' = '#D9A12B'  # dark gold
    'R' = '#F27A9B'  # pink
    'P' = '#9B7BF0'  # purple
    'C' = '#5CC8F0'  # light blue
    'N' = '#7A4A2E'  # coffee
    'L' = '#6BCB77'  # green
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

# Reusable pieces
$armsUp  = '4,8-9=_ 15,8-9=_ 4,7=# 3,5-6=# 15,7=# 16,5-6=#'
$laptop  = '3-16,10-12=D 9-10,11=W 2-17,13=S'
$mug     = '16-18,8=N 16-18,9-11=W 19,9-10=W'
$hat     = '7-12,4=P 8-11,3=P 9-10,2=P 9-10,1=Y 8,4=Y 11,4=Y 10,3=Y'
$glasses = '6-8,7-8=K 11-13,7-8=K 9-10,7=K'
$cup     = '6-13,0-1=Y 5,1=O 14,1=O 7-12,2=Y 9-10,3=O 6-13,4=O 4,8-9=_ 15,8-9=_ 4,5-7=# 15,5-7=# 5,4=# 14,4=#'
$blush   = '6,9=R 13,9=R'
$sleepy  = '7,7=# 12,7=# 6,8=E 11,8=E'
$bang    = '17,0-2=Y 17,4=Y'
$qmark   = '15-17,0=C 17,1=C 16,2=C 16,4=C'

# kinds: which events use the pose (done = task finished, attention = Claude needs you)
# ms: frame duration; hop: bounce when the popup appears
$ClawdPoses = @(
    @{ name = 'cheer';    kinds = 'done';           ms = 260; hop = $true;  frames = @($armsUp, '') }
    @{ name = 'wave';     kinds = 'done,attention'; ms = 230; hop = $true;  frames = @('15,8-9=_ 15,7=# 16,5-6=#', '15,9=_ 16,7-8=#') }
    @{ name = 'laptop';   kinds = 'done';           ms = 170; hop = $false; frames = @("$laptop 4,8=_ 4,7=#", "$laptop 15,8=_ 15,7=#") }
    @{ name = 'sleepy';   kinds = 'done';           ms = 650; hop = $false; frames = @("$sleepy 14-17,1=W 16,2=W 15,3=W 14-17,4=W", "$sleepy 15-18,0=W 17,1=W 16,2=W 15-18,3=W") }
    @{ name = 'coffee';   kinds = 'done';           ms = 380; hop = $false; frames = @("$mug 16,6=S 17,5=S 16,4=S", "$mug 18,6=S 17,5=S 18,4=S") }
    @{ name = 'party';    kinds = 'done';           ms = 300; hop = $true;  frames = @("$hat $armsUp 1,1=Y 17,2=R 1,6=C 18,6=L 1,10=R 18,11=Y", "$hat 2,2=R 16,1=C 1,5=L 18,5=Y 2,11=Y 18,9=R") }
    @{ name = 'love';     kinds = 'done';           ms = 380; hop = $true;  frames = @("$blush 9,1=R 11,1=R 8-12,2=R 9-11,3=R 10,4=R", "$blush 8-9,0=R 11-12,0=R 7-13,1=R 8-12,2=R 9-11,3=R 10,4=R") }
    @{ name = 'cool';     kinds = 'done';           ms = 550; hop = $true;  frames = @("$glasses 7,7=W", "$glasses 12,7=W") }
    @{ name = 'dance';    kinds = 'done';           ms = 260; hop = $false; frames = @('dx=-1 3,8-9=_ 3,7=# 2,5-6=# 17,1-3=Y 16,3=Y 18,1=Y', 'dx=1 16,8-9=_ 16,7=# 17,5-6=# 2,1-3=Y 1,3=Y 3,1=Y') }
    @{ name = 'trophy';   kinds = 'done';           ms = 320; hop = $true;  frames = @("$cup 2,1=W 17,3=W 1,6=W", "$cup 3,3=W 17,0=W 18,6=W") }
    @{ name = 'alert';    kinds = 'attention';      ms = 320; hop = $true;  frames = @($bang, '') }
    @{ name = 'confused'; kinds = 'attention';      ms = 520; hop = $false; frames = @($qmark, "$qmark 7,8=# 12,8=# 7,6=E 12,6=E") }
)
