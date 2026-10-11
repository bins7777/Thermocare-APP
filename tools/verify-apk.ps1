param([string]$Apk = 'build/app/outputs/flutter-apk/app-release.apk')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$apkPath = (Resolve-Path -LiteralPath $Apk).Path
$sdkPath = $env:ANDROID_HOME
if (!$sdkPath) {
  $sdkLine = Get-Content android/local.properties | Where-Object { $_ -match '^sdk.dir=' } | Select-Object -First 1
  if ($sdkLine) { $sdkPath = $sdkLine.Substring(8).Replace('\:', ':').Replace('\\', '\') }
}
if (!$sdkPath) { throw 'Set ANDROID_HOME or sdk.dir in android/local.properties.' }
$buildTools = Join-Path $sdkPath 'build-tools/36.0.0'
$javaPath = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin/java.exe' } else { (Get-Command java).Source }
$signature = & $javaPath -jar (Join-Path $buildTools 'lib/apksigner.jar') verify --verbose --print-certs $apkPath
if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
if ($signature -match 'CN=Android Debug') { throw 'APK is signed with a debug identity.' }
$badging = & (Join-Path $buildTools 'aapt.exe') dump badging $apkPath
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect APK metadata.' }
if (!($badging -match "package: name='com.thermocare.thermocare'")) { throw 'Unexpected application ID.' }
if (!($badging -match "sdkVersion:'24'")) { throw 'Unexpected minimum Android version.' }
if ($badging -match 'application-debuggable') { throw 'Release APK must not be debuggable.' }
& (Join-Path $buildTools 'zipalign.exe') -c -P 16 4 $apkPath
if ($LASTEXITCODE -ne 0) { throw 'APK alignment verification failed.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($apkPath)
try {
  $names = @($archive.Entries | ForEach-Object FullName)
  foreach ($architecture in @('armeabi-v7a', 'arm64-v8a', 'x86_64')) {
    if ($names -notcontains "lib/$architecture/libapp.so") { throw "Missing architecture: $architecture" }
  }
  if ($names -match '\.(jks|keystore)$|key\.properties|firebase-config\.json|(^|/)\.tools/') {
    throw 'Private build files must not be packaged.'
  }
} finally { $archive.Dispose() }
$digest = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLower()
"$digest  $([System.IO.Path]::GetFileName($apkPath))" | Set-Content -LiteralPath "$apkPath.sha256" -Encoding ASCII
Write-Output 'PASS: release signature, application ID, Android 7+ minimum, non-debuggable, 16 KB ZIP alignment, all three architectures, and no private build files.'
$signature | Where-Object { $_ -match 'Signer #1 certificate (DN|SHA-256 digest):' } | Write-Output
$badging | Where-Object { $_ -match '^package:|^sdkVersion:|^targetSdkVersion:|^native-code:' } | Write-Output
Write-Output "SHA-256: $digest"
