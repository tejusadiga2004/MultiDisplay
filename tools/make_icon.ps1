# Generates the Display Controller app icon:
#   windows/runner/resources/app_icon.ico   (16..256 px, PNG-compressed frames)
#   macos/Runner/Assets.xcassets/AppIcon.appiconset (16..1024 px)
#   assets/icon/app_icon.png                (512 px, used inside the Flutter UI)
#
# Run from the repository root:  powershell -File tools/make_icon.ps1
# Design: blue rounded tile, a front monitor with a "cast" ripple glyph on its
# screen and a second monitor behind it (multiple / mirrored displays).

Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$icoPath = Join-Path $root 'windows\runner\resources\app_icon.ico'
$macIconDir = Join-Path $root 'macos\Runner\Assets.xcassets\AppIcon.appiconset'
$pngPath = Join-Path $root 'assets\icon\app_icon.png'
New-Item -ItemType Directory -Force (Split-Path $icoPath), $macIconDir, (Split-Path $pngPath) | Out-Null

function New-RoundedRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

function Argb([int]$a, [string]$hex) {
  $c = [System.Drawing.ColorTranslator]::FromHtml($hex)
  return [System.Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B)
}

# ---- master artwork at 1024 x 1024 -----------------------------------------
$S = 1024
$master = New-Object System.Drawing.Bitmap $S, $S, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($master)
$g.SmoothingMode = 'AntiAlias'
$g.PixelOffsetMode = 'HighQuality'
$g.Clear([System.Drawing.Color]::Transparent)

# Tile
$tile = New-RoundedRect 40 40 944 944 230
$tileBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush ((New-Object System.Drawing.Point 0, 40), (New-Object System.Drawing.Point 0, 984), (Argb 255 '#6C97FF'), (Argb 255 '#2B3FB5'))
$g.FillPath($tileBrush, $tile)
# Soft top highlight
$hl = New-Object System.Drawing.Drawing2D.LinearGradientBrush ((New-Object System.Drawing.Point 0, 40), (New-Object System.Drawing.Point 0, 420), (Argb 70 '#FFFFFF'), (Argb 0 '#FFFFFF'))
$g.SetClip($tile)
$g.FillRectangle($hl, 40, 40, 944, 380)
$g.ResetClip()

# Back monitor (second display)
$backFrame = New-RoundedRect 430 190 410 280 34
$g.FillPath((New-Object System.Drawing.SolidBrush (Argb 95 '#FFFFFF')), $backFrame)
$backScreen = New-RoundedRect 452 212 366 236 20
$g.FillPath((New-Object System.Drawing.SolidBrush (Argb 70 '#0F1C5C')), $backScreen)

# Front monitor shadow
$shadow = New-RoundedRect 196 352 540 360 40
$g.FillPath((New-Object System.Drawing.SolidBrush (Argb 55 '#0A1250')), $shadow)

# Front monitor frame + screen
$frame = New-RoundedRect 180 320 540 360 40
$g.FillPath((New-Object System.Drawing.SolidBrush (Argb 255 '#FFFFFF')), $frame)
$screen = New-RoundedRect 210 350 480 300 22
$screenBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush ((New-Object System.Drawing.Point 0, 350), (New-Object System.Drawing.Point 0, 650), (Argb 255 '#3F6AE0'), (Argb 255 '#16226F'))
$g.FillPath($screenBrush, $screen)

# "Cast" ripple glyph on the screen (mirroring)
$white = Argb 255 '#FFFFFF'
$ox = 262; $oy = 598
$g.FillEllipse((New-Object System.Drawing.SolidBrush $white), ($ox - 17), ($oy - 17), 34, 34)
$radii = 70, 125, 180
$alphas = 255, 215, 170
for ($i = 0; $i -lt 3; $i++) {
  $r = $radii[$i]
  $pen = New-Object System.Drawing.Pen (Argb $alphas[$i] '#FFFFFF'), 22
  $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
  $g.DrawArc($pen, ($ox - $r), ($oy - $r), (2 * $r), (2 * $r), 270, 90)
}

# Stand
$neck = New-RoundedRect 420 672 80 76 10
$g.FillPath((New-Object System.Drawing.SolidBrush (Argb 255 '#E7ECFF')), $neck)
$base = New-RoundedRect 330 738 240 44 22
$g.FillPath((New-Object System.Drawing.SolidBrush (Argb 255 '#FFFFFF')), $base)

$g.Dispose()

# ---- resize helper ---------------------------------------------------------
function Resize-Png([System.Drawing.Bitmap]$src, [int]$size) {
  $b = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gg = [System.Drawing.Graphics]::FromImage($b)
  $gg.InterpolationMode = 'HighQualityBicubic'
  $gg.SmoothingMode = 'AntiAlias'
  $gg.PixelOffsetMode = 'HighQuality'
  $gg.CompositingQuality = 'HighQuality'
  $gg.Clear([System.Drawing.Color]::Transparent)
  $gg.DrawImage($src, 0, 0, $size, $size)
  $gg.Dispose()
  $ms = New-Object System.IO.MemoryStream
  $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $b.Dispose()
  return , $ms.ToArray()
}

# UI asset
$ui = Resize-Png $master 512
[System.IO.File]::WriteAllBytes($pngPath, $ui)

# macOS app icon asset catalog
$macSizes = 16, 32, 64, 128, 256, 512, 1024
foreach ($s in $macSizes) {
  $bytes = Resize-Png $master $s
  [System.IO.File]::WriteAllBytes(
    (Join-Path $macIconDir "app_icon_$s.png"),
    $bytes
  )
}

# ICO with PNG-compressed frames
$sizes = 16, 20, 24, 32, 40, 48, 64, 96, 128, 256
$frames = foreach ($s in $sizes) { , (Resize-Png $master $s) }
$out = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter $out
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $s = $sizes[$i]
  $dim = if ($s -ge 256) { 0 } else { $s }
  $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
  $bw.Write([uint16]1); $bw.Write([uint16]32)
  $bw.Write([uint32]$frames[$i].Length); $bw.Write([uint32]$offset)
  $offset += $frames[$i].Length
}
foreach ($f in $frames) { $bw.Write($f) }
$bw.Flush()
[System.IO.File]::WriteAllBytes($icoPath, $out.ToArray())
$master.Dispose()

"Wrote $icoPath ($((Get-Item $icoPath).Length) bytes)"
"Wrote $pngPath ($((Get-Item $pngPath).Length) bytes)"
