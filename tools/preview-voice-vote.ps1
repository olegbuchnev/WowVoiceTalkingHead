Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$project = Join-Path $repo 'web\voice-vote'
$config = Join-Path $repo 'config\build.env.local.ps1'
if (Test-Path -LiteralPath $config) { . $config }
& (Join-Path $PSScriptRoot 'start-voice-vote-api.ps1')
$url = 'http://127.0.0.1:5174/'
try {
    $existing = Invoke-RestMethod -Uri ($url + 'api/catalogue') -TimeoutSec 2
    if ($existing.app -eq 'talkinghead-voice-vote') { Write-Host "Prototype already running: $url"; exit 0 }
} catch { }
Push-Location $project
try {
    if (-not (Test-Path -LiteralPath 'node_modules\vite\bin\vite.js')) {
        & npm.cmd ci
        if ($LASTEXITCODE -ne 0) { throw 'Could not install prototype dependencies.' }
    }
    $logs = Join-Path $repo 'artifacts\voice-vote-preview'
    New-Item -ItemType Directory -Path $logs -Force | Out-Null
    $vite = Join-Path $project 'node_modules\vite\bin\vite.js'
    $process = Start-Process -FilePath (Get-Command node -ErrorAction Stop).Source -WindowStyle Hidden -PassThru `
        -WorkingDirectory $project -ArgumentList @(('"' + $vite + '"'), '--host', '127.0.0.1', '--port', '5174', '--strictPort') `
        -RedirectStandardOutput (Join-Path $logs 'server.log') -RedirectStandardError (Join-Path $logs 'server-error.log')
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        if ($process.HasExited) { throw "Prototype server stopped. See $logs\server-error.log" }
        try {
            $health = Invoke-RestMethod -Uri ($url + 'api/catalogue') -TimeoutSec 2
            if ($health.app -eq 'talkinghead-voice-vote') {
                Write-Host "Open in Firefox: $url"
                Write-Host "Server PID: $($process.Id). Stop with: Stop-Process -Id $($process.Id)"
                exit 0
            }
        } catch { }
        Start-Sleep -Milliseconds 300
    }
    throw "Prototype did not become ready. See $logs"
} finally { Pop-Location }
