# Runs the Flutter test suite with the local JDK / Android SDK toolchain.
# Usage:  & .\tool\run_tests.ps1

$ErrorActionPreference = 'Continue'
$env:JAVA_HOME = 'C:\Users\ACER\fishguard-setup\jdk\jdk-17.0.20.1+1'
$env:ANDROID_HOME = 'C:\Users\ACER\fishguard-setup\android-sdk'
$env:PATH = 'C:\Users\ACER\flutter-sdk\flutter\bin;' +
    (Join-Path $env:JAVA_HOME 'bin') + ';' +
    (Join-Path $env:ANDROID_HOME 'platform-tools') + ';' + $env:PATH

Set-Location (Split-Path -Parent $PSScriptRoot)
flutter test 2>&1
exit $LASTEXITCODE
