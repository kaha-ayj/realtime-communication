# Menjalankan aplikasi POS Sederhana.
#
# Default: memakai API MiomiPay sandbox asli (butuh internet).
#
# Pemakaian:
#   powershell -ExecutionPolicy Bypass -File .\run-dev.ps1
#   powershell -ExecutionPolicy Bypass -File .\run-dev.ps1 -Device windows
#   powershell -ExecutionPolicy Bypass -File .\run-dev.ps1 -UseMock
#   powershell -ExecutionPolicy Bypass -File .\run-dev.ps1 -Defines dart_defines.live.json

param(
    [string]$Device = "chrome",
    [switch]$UseMock,
    [string]$Defines = "dart_defines.sandbox.json"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$serverDir = Join-Path $root "server"

$flutterArgs = @("run", "-d", $Device)

if ($UseMock) {
    if (-not (Test-Path (Join-Path $serverDir "node_modules"))) {
        Write-Host "[setup] Memasang dependency mock server..." -ForegroundColor Cyan
        Push-Location $serverDir
        npm install --silent
        Pop-Location
    }

    Write-Host "[server] Menjalankan MiomiPay mock server di http://localhost:4000" -ForegroundColor Cyan
    $server = Start-Process -FilePath "node" `
        -ArgumentList "miomipay-mock.js" `
        -WorkingDirectory $serverDir `
        -PassThru `
        -WindowStyle Hidden

    Start-Sleep -Seconds 2

    $flutterArgs += @(
        "--dart-define=MIOMIPAY_BASE_URL=http://localhost:4000/api/v1",
        "--dart-define=MIOMIPAY_API_KEY=miomipay_sandbox_key",
        "--dart-define=MIOMIPAY_SANDBOX=true"
    )
}
else {
    $definesPath = Join-Path $root $Defines
    if (-not (Test-Path $definesPath)) {
        Write-Host "[error] File '$Defines' tidak ditemukan." -ForegroundColor Red
        Write-Host "        Salin dart_defines.example.json menjadi $Defines lalu isi API key." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "[config] Memakai $Defines" -ForegroundColor Cyan
    $flutterArgs += "--dart-define-from-file=$Defines"
}

Write-Host ""
Write-Host "[app] Menjalankan Flutter pada device: $Device" -ForegroundColor Cyan
Write-Host "      Akun demo -> admin@pos.id / Admin123!  |  kasir@pos.id / Kasir123!" -ForegroundColor DarkGray
Write-Host ""

try {
    Push-Location $root
    flutter @flutterArgs
    Pop-Location
}
finally {
    if ($UseMock -and $server -and -not $server.HasExited) {
        Write-Host "[server] Menghentikan mock server..." -ForegroundColor Cyan
        Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
    }
}
