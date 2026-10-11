$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$versionMatch = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*([^+\s]+)\+(\d+)')
if (!$versionMatch.Success) { throw 'Set the app version in pubspec.yaml.' }
$version = $versionMatch.Groups[1].Value
$stage = Join-Path $projectRoot ('.tools/ios-package-' + [Guid]::NewGuid().ToString('N') + '/ThermoCare')
New-Item -ItemType Directory -Path $stage -Force | Out-Null
foreach ($directory in @('lib', 'assets', 'test', 'ios')) {
  foreach ($source in (Get-ChildItem -LiteralPath (Join-Path $projectRoot $directory) -File -Recurse -Force)) {
    $relative = $source.FullName.Substring($projectRoot.Length + 1).Replace('\', '/')
    if ($relative -match '(^|/)(Pods|\.symlinks|ephemeral|xcuserdata|DerivedData)(/|$)' -or
        $relative -match '^ios/Flutter/(Generated\.xcconfig|flutter_export_environment\.sh)$' -or
        $relative -match '^ios/Runner/GeneratedPluginRegistrant\.[mh]$') { continue }
    $destination = Join-Path $stage $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source.FullName -Destination $destination
  }
}
foreach ($relative in @('pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.metadata', '.gitignore', 'USER_GUIDE.md', 'IPHONE_BUILD.md', 'IOS_CLOUD_BUILD.md', '.github/workflows/ios.yml', 'tools/build-ios.sh', 'tools/cloud-ios.sh', 'tools/create-ios-signing-key.cjs', 'tools/ios_preflight.dart')) {
  $destination = Join-Path $stage $relative
  New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $projectRoot $relative) -Destination $destination
}
$config = Get-Content firebase-config.json -Raw | ConvertFrom-Json
$iosConfig = [ordered]@{}
foreach ($key in @('FIREBASE_PROJECT_ID', 'FIREBASE_MESSAGING_SENDER_ID', 'FIREBASE_AUTH_DOMAIN', 'FIREBASE_STORAGE_BUCKET', 'FIREBASE_IOS_APP_ID', 'FIREBASE_IOS_API_KEY', 'FIREBASE_IOS_BUNDLE_ID')) {
  $iosConfig[$key] = $config.$key
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $stage 'firebase-config.json'), (($iosConfig | ConvertTo-Json) + "`n"), $utf8)
$metadata = @{ name = 'ThermoCare'; version = $version; build = $versionMatch.Groups[2].Value; type = 'iOS source project - not an installer'; signedIpa = $false; builtOnMac = $false; preparedAtUtc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path $stage 'package-info.json'), ($metadata + "`n"), $utf8)
$releasePath = Join-Path $projectRoot 'artifacts/release'
New-Item -ItemType Directory -Path $releasePath -Force | Out-Null
$archivePath = Join-Path $releasePath "ThermoCare-$version-ios-project.zip"
Compress-Archive -LiteralPath $stage -DestinationPath $archivePath -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
try {
  $names = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
  foreach ($required in @('lib/main.dart', 'ios/Runner/Info.plist', 'firebase-config.json', 'tools/build-ios.sh', 'tools/cloud-ios.sh', '.github/workflows/ios.yml', 'IPHONE_BUILD.md', 'IOS_CLOUD_BUILD.md')) {
    if ($names -notcontains "ThermoCare/$required") { throw "Package is missing $required" }
  }
  if ($names -match '\.(jks|keystore|p12|p8|pem|mobileprovision)$|key\.properties|arduino_secrets\.h|Generated\.xcconfig|flutter_export_environment\.sh|(^|/)\.tools/') {
    throw 'Private or machine-generated build files found in iOS package.'
  }
} finally { $archive.Dispose() }
$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLower()
"$hash  $([IO.Path]::GetFileName($archivePath))" | Set-Content -LiteralPath "$archivePath.sha256" -Encoding ASCII
Copy-Item -LiteralPath IPHONE_BUILD.md -Destination $releasePath -Force
Write-Output "iOS source package verified: $archivePath"
Write-Output 'This archive needs a macOS build and Apple signing; it is not an iPhone installer.'
