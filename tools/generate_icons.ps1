$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectPath = Split-Path $PSScriptRoot -Parent
function Write-AppIcon([string]$relativePath, [int]$size) {
    $bitmap = New-Object System.Drawing.Bitmap($size, $size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#6D4ED0'))
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $mint = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#6D4ED0'))
    $graphics.FillEllipse($white, [single]($size * .385), [single]($size * .23), [single]($size * .23), [single]($size * .23))
    $graphics.FillRectangle($white, [single]($size * .385), [single]($size * .34), [single]($size * .23), [single]($size * .31))
    $graphics.FillEllipse($white, [single]($size * .32), [single]($size * .53), [single]($size * .36), [single]($size * .36))
    $graphics.FillRectangle($mint, [single]($size * .475), [single]($size * .33), [single]($size * .05), [single]($size * .35))
    $graphics.FillEllipse($mint, [single]($size * .43), [single]($size * .64), [single]($size * .14), [single]($size * .14))
    $destinationPath = Join-Path $projectPath $relativePath
    $bitmap.Save($destinationPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $white.Dispose(); $mint.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
}
@{ 'mdpi' = 48; 'hdpi' = 72; 'xhdpi' = 96; 'xxhdpi' = 144; 'xxxhdpi' = 192 }.GetEnumerator() | ForEach-Object {
    Write-AppIcon "android/app/src/main/res/mipmap-$($_.Key)/ic_launcher.png" $_.Value
}
$icons = Get-Content (Join-Path $projectPath 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json') -Raw | ConvertFrom-Json
foreach ($icon in $icons.images) {
    $size = [double]($icon.size.Split('x')[0]) * [double]($icon.scale.TrimEnd('x'))
    Write-AppIcon "ios/Runner/Assets.xcassets/AppIcon.appiconset/$($icon.filename)" ([int]$size)
}
Write-AppIcon 'web/favicon.png' 32
Write-AppIcon 'web/icons/Icon-192.png' 192
Write-AppIcon 'web/icons/Icon-512.png' 512
Write-AppIcon 'web/icons/Icon-maskable-192.png' 192
Write-AppIcon 'web/icons/Icon-maskable-512.png' 512
Write-AppIcon 'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png' 96
Write-AppIcon 'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png' 192
Write-AppIcon 'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png' 288
