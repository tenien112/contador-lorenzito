Add-Type -AssemblyName System.Drawing
$source = "C:\Users\tenie\.gemini\antigravity\brain\66a8a931-0fc9-4cde-872d-5ff7d5eebe79\play_store_banner_wide_1772142543425.png"
$dest = "c:\basura\antigravity\contador_series_lorenzito\store_assets\banner.png"

$img = [System.Drawing.Image]::FromFile($source)
$targetWidth = 1024
$targetHeight = 500

# Calculate cropping coordinates to get the center
$srcWidth = $img.Width
$srcHeight = $img.Height

# First, resize the image so that its width matches 1024, maintaining aspect ratio
# Assuming the generated image is square (1024x1024)
# If we want 1024x500, we crop 262 pixels from top and bottom.
$cropY = ($srcHeight - $targetHeight) / 2
$cropX = 0

$bmp = New-Object System.Drawing.Bitmap($targetWidth, $targetHeight)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

$srcRect = New-Object System.Drawing.RectangleF($cropX, $cropY, $targetWidth, $targetHeight)
$destRect = New-Object System.Drawing.RectangleF(0, 0, $targetWidth, $targetHeight)

$g.DrawImage($img, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)

$img.Dispose()
$bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$g.Dispose()
Write-Host "Banner cropped successfully to 1024x500 without stretching."
