$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$projectRoot = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $projectRoot 'backend'
$envFile = Join-Path $backend '.env'
$appExe = Join-Path $projectRoot 'citizen_app\build\windows\x64\runner\Release\citizen_app.exe'
$pythonExe = Join-Path $backend '.venv\Scripts\python.exe'
$logs = Join-Path $backend 'logs'
$stdoutLog = Join-Path $logs 'api.log'
$stderrLog = Join-Path $logs 'api-error.log'

function Show-Info([string]$message) {
    [void][System.Windows.Forms.MessageBox]::Show($message, 'InfraVision Citizen', 'OK', 'Information')
}
function Show-Error([string]$message) {
    [void][System.Windows.Forms.MessageBox]::Show($message, 'InfraVision Citizen', 'OK', 'Error')
}

if (-not (Test-Path -LiteralPath $envFile)) {
    Copy-Item -LiteralPath (Join-Path $backend '.env.example') -Destination $envFile
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 48
    $rng.GetBytes($bytes)
    $rng.Dispose()
    $jwt = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $contents = [IO.File]::ReadAllText($envFile)
    $contents = [regex]::Replace($contents, '(?m)^JWT_SECRET=.*$', "JWT_SECRET=$jwt")
    [IO.File]::WriteAllText($envFile, $contents, [System.Text.UTF8Encoding]::new($false))
    Show-Info("One-time setup: in MySQL Workbench run:`nCREATE DATABASE infravision_citizen CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;`n`nThen enter your MySQL password in backend\.env by replacing YOUR_URL_ENCODED_PASSWORD in DATABASE_URL. Add AI_API_KEY only if you want AI chat. Save the file and open InfraVision again.")
    Start-Process notepad.exe -ArgumentList "`"$envFile`""
    exit 0
}

$dbLine = Select-String -LiteralPath $envFile -Pattern '^DATABASE_URL\s*=\s*(.+)$' | Select-Object -First 1
if (-not $dbLine -or $dbLine.Matches[0].Groups[1].Value -match 'YOUR_URL_ENCODED_PASSWORD|^\s*$') {
    Show-Error("MySQL is not configured yet. Edit backend\.env and replace YOUR_URL_ENCODED_PASSWORD in DATABASE_URL with your local MySQL root password. URL-encode reserved characters. Do not send the password to anyone.")
    Start-Process notepad.exe -ArgumentList "`"$envFile`""
    exit 1
}

if (-not (Test-Path -LiteralPath $appExe)) {
    Show-Error("The desktop build is missing. Rebuild citizen_app for Windows first.`nExpected: $appExe")
    exit 1
}

New-Item -ItemType Directory -Path $logs -Force | Out-Null
Set-Location $backend
if (-not (Test-Path -LiteralPath $pythonExe)) {
    & py -3.13 -m venv (Join-Path $backend '.venv')
    if ($LASTEXITCODE -ne 0) {
        Show-Error('Python 3.13 is required to prepare the backend. Install Python 3.13, then open InfraVision again.')
        exit 1
    }
}

& $pythonExe -c 'import fastapi, uvicorn, sqlalchemy, pymysql' 2>$null
if ($LASTEXITCODE -ne 0) {
    $install = Start-Process -FilePath $pythonExe -ArgumentList @('-m', 'pip', 'install', '-r', (Join-Path $backend 'requirements.txt')) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
    if ($install.ExitCode -ne 0) {
        Show-Error("Backend packages could not be installed. Check your internet connection and inspect:`n$stderrLog")
        exit 1
    }
}

try {
    Invoke-RestMethod -Uri 'http://127.0.0.1:8000/ready' -TimeoutSec 2 | Out-Null
} catch {
    if (Test-Path $stderrLog) { Clear-Content -LiteralPath $stderrLog }
    Start-Process -FilePath $pythonExe -ArgumentList @('-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', '8000') -WorkingDirectory $backend -WindowStyle Hidden -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog | Out-Null
    $ready = $false
    for ($attempt = 0; $attempt -lt 45; $attempt++) {
        Start-Sleep -Seconds 1
        try {
            Invoke-RestMethod -Uri 'http://127.0.0.1:8000/ready' -TimeoutSec 2 | Out-Null
            $ready = $true
            break
        } catch {}
    }
    if (-not $ready) {
        $details = if (Test-Path $stderrLog) { (Get-Content $stderrLog -Tail 12) -join "`n" } else { 'No backend log was created.' }
        Show-Error("The backend could not connect to MySQL. Verify the database exists and DATABASE_URL in backend\.env has the correct root password.`n`n$details")
        exit 1
    }
}

Start-Process -FilePath $appExe -WorkingDirectory (Split-Path -Parent $appExe) | Out-Null
