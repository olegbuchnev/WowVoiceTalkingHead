Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $repo 'server\voice-vote'
$logs = Join-Path $repo 'artifacts\voice-vote-preview'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
& node (Join-Path $repo 'web\voice-vote\export-vote-catalogue.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Could not export the voting catalogue.' }
try {
    $health = Invoke-RestMethod 'http://127.0.0.1:8081/api/votes/health' -TimeoutSec 2
    if ($health.app -eq 'talkinghead-vote-server') { Write-Host 'Java voting server already running on 8081.'; return }
} catch { }
$java = (Get-Command java -ErrorAction Stop).Source
$admin = Join-Path $backend 'admin'
$adminIndex = Join-Path $backend 'src\main\resources\static\admin\index.html'
$adminSources = @(Get-ChildItem -LiteralPath (Join-Path $admin 'src'), (Join-Path $admin 'public') -Recurse -File)
$adminSources += Get-ChildItem -LiteralPath $admin -File
$adminNewest = ($adminSources | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
if (-not (Test-Path -LiteralPath $adminIndex) -or (Get-Item -LiteralPath $adminIndex).LastWriteTimeUtc -lt $adminNewest) {
    & npm.cmd ci --prefix $admin
    if ($LASTEXITCODE -ne 0) { throw 'Admin dependency installation failed.' }
    & npm.cmd run build --prefix $admin
    if ($LASTEXITCODE -ne 0) { throw 'Admin interface build failed.' }
}
$jar = Join-Path $backend 'target\voice-vote-server-0.1.0.jar'
$sources = @(Get-ChildItem -LiteralPath (Join-Path $backend 'src') -Recurse -File)
$sources += Get-Item -LiteralPath (Join-Path $backend 'pom.xml')
$newest = ($sources | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
if (-not (Test-Path -LiteralPath $jar) -or (Get-Item -LiteralPath $jar).LastWriteTimeUtc -lt $newest) {
    Push-Location $backend
    try {
        & .\mvnw.cmd -B -q verify
        if ($LASTEXITCODE -ne 0) { throw 'Java server build failed. JDK 25 or newer is required.' }
    } finally { Pop-Location }
}
# Run a separate copy so the next Maven build can replace its output on Windows.
$runtimeJar = Join-Path $logs 'voice-vote-server.jar'
Copy-Item -LiteralPath $jar -Destination $runtimeJar -Force
$process = Start-Process -FilePath $java -WindowStyle Hidden -PassThru -WorkingDirectory $backend `
    -ArgumentList @('--enable-native-access=ALL-UNNAMED', '-jar', ('"' + $runtimeJar + '"')) `
    -RedirectStandardOutput (Join-Path $logs 'java-server.log') -RedirectStandardError (Join-Path $logs 'java-server-error.log')
for ($attempt=0; $attempt -lt 40; $attempt++) {
    if ($process.HasExited) { throw "Java server stopped. See $logs\java-server.log" }
    try {
        $health=Invoke-RestMethod 'http://127.0.0.1:8081/api/votes/health' -TimeoutSec 2
        if ($health.app -eq 'talkinghead-vote-server') {
            Write-Host "Java voting server PID: $($process.Id). Stop with: Stop-Process -Id $($process.Id)"
            return
        }
    } catch { }
    Start-Sleep -Milliseconds 300
}
throw "Java voting server did not become ready. See $logs"
