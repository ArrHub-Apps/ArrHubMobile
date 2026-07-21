# Draws the ArrHub launcher icon: the triangular "spoke-cut" brand mark (the same mark as
# the in-app logo in lib/widgets/arrhub_logo.dart and the desktop AppLogo.vue), centered in
# a 1024x1024 canvas within the adaptive-icon safe zone. Outputs three layers:
#   assets/icon/icon_legacy.png     - green mark on black, full-bleed (legacy launchers)
#   assets/icon/icon_foreground.png - green mark, transparent bg (adaptive foreground)
#   assets/icon/icon_monochrome.png - white mark, transparent bg (Android 13+ themed icon)
#
# Regenerate the platform icons after running this:  dart run flutter_launcher_icons
Add-Type -AssemblyName System.Drawing

$green = [System.Drawing.Color]::FromArgb(255, 0x1D, 0xB9, 0x54)
$white = [System.Drawing.Color]::FromArgb(255, 0xFF, 0xFF, 0xFF)
$black = [System.Drawing.Color]::FromArgb(255, 0, 0, 0)

# Mark geometry in the desktop SVG's design space (viewBox "20 -10 240 200").
$apex = New-Object System.Drawing.PointF(140, 4.5)
$left = New-Object System.Drawing.PointF(40, 177.7)
$right = New-Object System.Drawing.PointF(240, 177.7)
$hub = New-Object System.Drawing.PointF(140, 120)

# Centre the triangle's bounding box (x 40..240, y 4.5..177.7 -> centre 140,91.1) on the
# canvas centre, scaled to sit comfortably inside the circular safe zone (~341px radius).
$designCx = 140.0
$designCy = 91.1
$scale = 2.55
# An upward triangle is bottom-heavy (its centroid sits 1/3 up from the base), so centring
# the bounding box leaves it looking low. Nudge up so the visual mass reads centred.
$vShift = 45.0

function Draw-Glyph([System.Drawing.Color]$fill) {
  $bmp = New-Object System.Drawing.Bitmap 1024, 1024
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

  # Map design space -> centred canvas box (with the optical up-nudge).
  $g.TranslateTransform(512, 512 - $vShift)
  $g.ScaleTransform($scale, $scale)
  $g.TranslateTransform(-$designCx, -$designCy)

  $fillBrush = New-Object System.Drawing.SolidBrush($fill)
  $g.FillPolygon($fillBrush, @($apex, $right, $left))

  # Clear the three spokes + hub so they read as cut-outs (matches the SVG mask / the
  # BlendMode.clear used in arrhub_logo.dart). SourceCopy makes drawing replace alpha.
  $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
  $clear = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)
  $pen = New-Object System.Drawing.Pen($clear, 14)
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $g.DrawLine($pen, $hub, $apex)
  $g.DrawLine($pen, $hub, $right)
  $g.DrawLine($pen, $hub, $left)
  $clearBrush = New-Object System.Drawing.SolidBrush($clear)
  $g.FillEllipse($clearBrush, $hub.X - 10.5, $hub.Y - 10.5, 21, 21)

  $pen.Dispose()
  $fillBrush.Dispose()
  $clearBrush.Dispose()
  $g.Dispose()
  return $bmp
}

function New-Icon([string]$outPath, [System.Drawing.Color]$fill, [bool]$blackBackground) {
  $canvas = New-Object System.Drawing.Bitmap 1024, 1024
  $g = [System.Drawing.Graphics]::FromImage($canvas)
  if ($blackBackground) { $g.Clear($black) } else { $g.Clear([System.Drawing.Color]::Transparent) }
  $glyph = Draw-Glyph $fill
  $g.DrawImage($glyph, 0, 0)
  $glyph.Dispose()
  $g.Dispose()
  $canvas.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $canvas.Dispose()
  Write-Output "wrote $outPath"
}

$dir = Join-Path $PSScriptRoot "..\assets\icon"
New-Item -ItemType Directory -Force $dir | Out-Null
New-Icon (Join-Path $dir "icon_legacy.png") $green $true
New-Icon (Join-Path $dir "icon_foreground.png") $green $false
New-Icon (Join-Path $dir "icon_monochrome.png") $white $false
