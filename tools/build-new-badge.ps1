# Inline text badge: high-resolution UI lettering using the invitation's font.
param([string]$PreviewPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$fonts = [System.Drawing.Text.PrivateFontCollection]::new()
$fonts.AddFontFile((Join-Path $root 'src/Media/Fonts/frizqt___cyr.ttf'))
$bitmap = [System.Drawing.Bitmap]::new(256, 64)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$font = [System.Drawing.Font]::new($fonts.Families[0], 56, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 242, 194, 97))
$format = [System.Drawing.StringFormat]::GenericTypographic.Clone()
try {
    $graphics.Clear([System.Drawing.Color]::FromArgb(31, 242, 194, 97))
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $graphics.DrawString('NEW', $font, $brush, [System.Drawing.RectangleF]::new(0, 0, 256, 64), $format)
    $bytes = [byte[]]::new(18 + 256 * 64 * 4)
    $bytes[2] = 2
    $bytes[13] = 1
    $bytes[14] = 64
    $bytes[16] = 32
    $bytes[17] = 40 # Top-left origin, eight alpha bits.
    for ($y = 0; $y -lt 64; $y++) {
        for ($x = 0; $x -lt 256; $x++) {
            $pixel = $bitmap.GetPixel($x, $y)
            $offset = 18 + ($y * 256 + $x) * 4
            $bytes[$offset] = $pixel.B
            $bytes[$offset + 1] = $pixel.G
            $bytes[$offset + 2] = $pixel.R
            $bytes[$offset + 3] = $pixel.A
        }
    }
    [System.IO.File]::WriteAllBytes((Join-Path $root 'src/Media/NewBadge.tga'), $bytes)
    if ($PreviewPath) { $bitmap.Save($PreviewPath, [System.Drawing.Imaging.ImageFormat]::Png) }
} finally {
    $format.Dispose(); $brush.Dispose(); $font.Dispose()
    $graphics.Dispose(); $bitmap.Dispose(); $fonts.Dispose()
}
