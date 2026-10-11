param(
  [ValidateSet('Web', 'Android', 'AppBundle', 'Ios')][string]$Target = 'Web',
  [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutterPath = if ($flutterCommand) { $flutterCommand.Source } else { Join-Path (Split-Path -Parent $projectRoot) 'flutter/bin/flutter.bat' }
if (!(Test-Path -LiteralPath $flutterPath)) { throw 'Flutter was not found. Add Flutter to PATH.' }
$configPath = Join-Path $projectRoot 'firebase-config.json'
if (!(Test-Path -LiteralPath $configPath)) { throw 'firebase-config.json is required for a release with family accounts.' }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$requiredKeys = @('FIREBASE_PROJECT_ID', 'FIREBASE_MESSAGING_SENDER_ID')
switch ($Target) {
  'Web' { $requiredKeys += @('FIREBASE_API_KEY', 'FIREBASE_APP_ID', 'FIREBASE_AUTH_DOMAIN') }
  { $_ -in @('Android', 'AppBundle') } { $requiredKeys += @('FIREBASE_ANDROID_API_KEY', 'FIREBASE_ANDROID_APP_ID') }
  'Ios' { $requiredKeys += @('FIREBASE_IOS_API_KEY', 'FIREBASE_IOS_APP_ID', 'FIREBASE_IOS_BUNDLE_ID') }
}
foreach ($key in $requiredKeys) {
  if ([string]::IsNullOrWhiteSpace($config.$key)) { throw "Missing release configuration: $key" }
}
foreach ($property in $config.PSObject.Properties) {
  if ($property.Name -match 'DEMO|EMULATOR' -and "$($property.Value)" -notin @('', 'false', 'False', '0')) {
    throw 'Development modes must be disabled for a release.'
  }
}
if ($config.FIREBASE_PROJECT_ID -like 'demo-*') { throw 'Use the production Firebase project for a release.' }
if ($Target -eq 'Ios' -and $config.FIREBASE_IOS_BUNDLE_ID -ne 'com.thermocare.thermocare') {
  throw 'The iOS Firebase bundle ID must match com.thermocare.thermocare.'
}
if ($Target -in @('Android', 'AppBundle')) {
  $missing = @()
  if (!(Test-Path -LiteralPath (Join-Path $projectRoot 'android/key.properties'))) {
    $missing += 'Configure android/key.properties with your private release signing key.'
  }
  $sdkPaths = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android/Sdk'))
  $localProperties = Join-Path $projectRoot 'android/local.properties'
  if (Test-Path -LiteralPath $localProperties) {
    $sdkLine = Get-Content -LiteralPath $localProperties | Where-Object { $_ -match '^sdk.dir=' } | Select-Object -First 1
    if ($sdkLine) { $sdkPaths += $sdkLine.Substring(8).Replace('\:', ':').Replace('\\', '\') }
  }
  $sdkFound = $sdkPaths | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'platform-tools/adb.exe')) }
  if (!$sdkFound) { $missing += 'Install the Android SDK and verify flutter doctor.' }
  if ($missing.Count -gt 0) { throw ($missing -join [Environment]::NewLine) }
}
if ($Target -eq 'Ios' -and $env:OS -eq 'Windows_NT') { throw 'An iOS release must be built on macOS with Xcode and Apple signing.' }
$versionMatch = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*([^+\s]+)\+(\d+)')
if (!$versionMatch.Success) { throw 'Set the release version and build number in pubspec.yaml.' }
$version = $versionMatch.Groups[1].Value
$build = $versionMatch.Groups[2].Value
Write-Output "Release configuration ready: ThermoCare $version ($build), $Target."
if ($ValidateOnly) { exit 0 }
function Invoke-FlutterChecked([string[]]$Arguments) {
  $savedDebug = $env:DEBUG
  try {
    # Gradle's Windows wrapper otherwise echoes all build configuration values.
    $env:DEBUG = $null
    & $flutterPath @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Flutter failed: $($Arguments[0])" }
  } finally {
    $env:DEBUG = $savedDebug
  }
}
Invoke-FlutterChecked -Arguments @('analyze')
Invoke-FlutterChecked -Arguments @('test', '--reporter', 'expanded')
$buildArguments = @('build', $(switch ($Target) { 'Web' { 'web' }; 'Android' { 'apk' }; 'AppBundle' { 'appbundle' }; 'Ios' { 'ipa' } }), '--release', '--dart-define-from-file=firebase-config.json', "--dart-define=APP_VERSION=$version", "--dart-define=APP_BUILD=$build")
Invoke-FlutterChecked -Arguments $buildArguments
$releasePath = Join-Path $projectRoot 'artifacts/release'
New-Item -ItemType Directory -Path $releasePath -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'USER_GUIDE.md') -Destination $releasePath -Force
if ($Target -in @('Android', 'AppBundle')) {
  Copy-Item -LiteralPath (Join-Path $projectRoot 'ANDROID_INSTALL.md') -Destination $releasePath -Force
}
switch ($Target) {
  'Web' {
    $archive = Join-Path $releasePath "ThermoCare-$version-web.zip"
    Compress-Archive -Path (Join-Path $projectRoot 'build/web/*') -DestinationPath $archive -Force
    Write-Output "Web release: $archive"
  }
  'Android' {
    $apkReleasePath = Join-Path $releasePath "ThermoCare-$version.apk"
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Destination $apkReleasePath -Force
    & (Join-Path $PSScriptRoot 'verify-apk.ps1') -Apk $apkReleasePath
    Write-Output "Android release: $apkReleasePath"
  }
  'AppBundle' { Copy-Item -LiteralPath 'build/app/outputs/bundle/release/app-release.aab' -Destination (Join-Path $releasePath "ThermoCare-$version.aab") -Force }
  'Ios' { Write-Output 'Signed iOS archive: build/ios/ipa' }
}
@{ name = 'ThermoCare'; version = $version; build = $build; target = $Target; builtAtUtc = [DateTime]::UtcNow.ToString('o'); firebaseProject = $config.FIREBASE_PROJECT_ID } |
  ConvertTo-Json | Set-Content -LiteralPath (Join-Path $releasePath 'release-info.json') -Encoding UTF8
