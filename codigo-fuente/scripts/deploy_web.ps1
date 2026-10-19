Set-Location $PSScriptRoot/..

Write-Host "Building Flutter web app..."
flutter build web --release
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host "Deploying to Firebase Hosting..."
firebase deploy --only hosting
exit $LASTEXITCODE
