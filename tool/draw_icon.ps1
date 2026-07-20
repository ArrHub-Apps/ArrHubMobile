# Draws the app launcher icon: a Spotify-green clapperboard with a play
# triangle on a black background. Outputs 1024x1024 PNGs:
#   assets/icon/icon_legacy.png     - full-bleed black bg (legacy launchers)
#   assets/icon/icon_foreground.png - transparent bg (adaptive foreground)
Add-Type -AssemblyName System.Drawing

$green = [System.Drawing.Color]::FromArgb(255, 0x1D, 0xB9, 0x54)
$black = [System.Drawing.Color]::FromArgb(255, 0, 0, 0)

function New-RoundedRectPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $path.AddArc($x, $y, $d, $d, 180, 90)
  $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  return $path
}

function Draw-Glyph([System.Drawing.Graphics]$g) {
  $greenBrush = New-Object System.Drawing.SolidBrush($green)
  $blackBrush = New-Object System.Drawing.SolidBrush($black)

  # Clapper top bar with diagonal stripes
  $bar = New-RoundedRectPath 292 322 440 100 24
  $g.FillPath($greenBrush, $bar)
  # Black diagonal stripes across the bar (clipped to the bar shape)
  $g.SetClip($bar)
  for ($i = 0; $i -lt 5; $i++) {
    $x = 292 + 30 + ($i * 88)
    $pts = @(
      (New-Object System.Drawing.PointF ($x), 422),
      (New-Object System.Drawing.PointF ($x + 34), 322),
      (New-Object System.Drawing.PointF ($x + 72), 322),
      (New-Object System.Drawing.PointF ($x + 38), 422)
    )
    $g.FillPolygon($blackBrush, $pts)
  }
  $g.ResetClip()

  # Clapper body
  $body = New-RoundedRectPath 292 446 440 256 36
  $g.FillPath($greenBrush, $body)

  # Play triangle cut into the body (optically centered)
  $tri = @(
    (New-Object System.Drawing.PointF 458, 514),
    (New-Object System.Drawing.PointF 458, 634),
    (New-Object System.Drawing.PointF 578, 574)
  )
  $g.FillPolygon($blackBrush, $tri)

  $greenBrush.Dispose()
  $blackBrush.Dispose()
}

function New-Icon([string]$outPath, [bool]$blackBackground) {
  $bmp = New-Object System.Drawing.Bitmap 1024, 1024
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  if ($blackBackground) {
    $g.Clear($black)
  } else {
    $g.Clear([System.Drawing.Color]::Transparent)
  }
  Draw-Glyph $g
  $g.Dispose()
  $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output "wrote $outPath"
}

$dir = "C:\Users\dpbre\Projects\RadarrSonarrApp\assets\icon"
New-Item -ItemType Directory -Force $dir | Out-Null
New-Icon "$dir\icon_legacy.png" $true
New-Icon "$dir\icon_foreground.png" $false
