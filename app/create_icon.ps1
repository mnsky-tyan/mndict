Add-Type -AssemblyName System.Drawing

$size = 512
$bmp = New-Object System.Drawing.Bitmap $size, $size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(255, 33, 150, 243)) # Blue

$font = New-Object System.Drawing.Font "Arial", 250, [System.Drawing.FontStyle]::Bold
$brush = [System.Drawing.Brushes]::White
$format = New-Object System.Drawing.StringFormat
$format.Alignment = [System.Drawing.StringAlignment]::Center
$format.LineAlignment = [System.Drawing.StringAlignment]::Center

$g.DrawString("D", $font, $brush, $size/2, $size/2 + 30, $format) # +30 offset for visual centering

$bmp.Save("c:\Users\tyanw\work\dict\app\app_icon.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()
Write-Host "Icon created at c:\Users\tyanw\work\dict\app\app_icon.png"
