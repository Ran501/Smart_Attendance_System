# Fixes Kotlin "different roots" build errors on Windows (C: Pub cache + D: project).
# Run from project root: .\scripts\fix_android_build.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Write-Host "Stopping Gradle daemons..."
if (Test-Path "android\gradlew.bat") {
    Push-Location android
    .\gradlew.bat --stop 2>$null
    Pop-Location
}

Write-Host "Cleaning Flutter build..."
flutter clean
flutter pub get

Write-Host "Done. Rebuild with:"
Write-Host "  flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1"
Write-Host ""
Write-Host "Optional (recommended on D: drive): set Pub cache on same drive:"
Write-Host '  [System.Environment]::SetEnvironmentVariable("PUB_CACHE", "D:\pub-cache", "User")'
