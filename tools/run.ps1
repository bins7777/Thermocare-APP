param(
  [string]$Device = 'web-server',
  [int]$Port = 8080
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutterPath = if ($flutterCommand) { $flutterCommand.Source } else { Join-Path (Split-Path -Parent $projectRoot) 'flutter/bin/flutter.bat' }
if (!(Test-Path -LiteralPath $flutterPath)) { throw 'Flutter was not found. Add Flutter to PATH.' }
$runArguments = @('run', '-d', $Device)
if (Test-Path -LiteralPath (Join-Path $projectRoot 'firebase-config.json')) {
  $runArguments += '--dart-define-from-file=firebase-config.json'
}
if ($Device -eq 'web-server') { $runArguments += @('--web-hostname', '127.0.0.1', '--web-port', "$Port") }
& $flutterPath @runArguments
