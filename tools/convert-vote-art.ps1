# Repackage the site's unchanged pixels as a WoW-compatible texture.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'web/voice-vote/public/welcome-adventurers.png'
$destination = Join-Path $root 'src/Media/VoteAdventurers.tga'
$bitmap = [System.Drawing.Bitmap]::new($source)
try {
    if ($bitmap.Width -ne 346 -or $bitmap.Height -ne 290) { throw 'Unexpected source artwork dimensions' }
    # Transparent power-of-two padding; no resampling or colour changes.
    $bytes = [byte[]]::new(18 + 512 * 512 * 4)
    $bytes[2] = 2
    $bytes[13] = 2
    $bytes[15] = 2
    $bytes[16] = 32
    $bytes[17] = 40 # Top-left origin, eight alpha bits.
    for ($y = 0; $y -lt $bitmap.Height; $y++) {
        for ($x = 0; $x -lt $bitmap.Width; $x++) {
            $pixel = $bitmap.GetPixel($x, $y)
            $offset = 18 + ($y * 512 + $x) * 4
            $bytes[$offset] = $pixel.B
            $bytes[$offset + 1] = $pixel.G
            $bytes[$offset + 2] = $pixel.R
            $bytes[$offset + 3] = $pixel.A
        }
    }
    [System.IO.File]::WriteAllBytes($destination, $bytes)
} finally {
    $bitmap.Dispose()
}
