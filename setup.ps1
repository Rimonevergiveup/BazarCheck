<#
  BazarCheck — one-command setup for Windows PowerShell.

  Usage, from the repo root:

      .\setup.ps1              install deps, analyze, test, then run on Chrome
      .\setup.ps1 -SkipTests   faster: skip analyze/test
      .\setup.ps1 -NoRun       set everything up but don't launch

  This does NOT touch your database. Apply database/COMPLETE_SETUP.sql in the
  Supabase SQL Editor first — see the reminder printed at the end.
#>

param(
    [switch]$SkipTests,
    [switch]$NoRun,
    [string]$Device = "chrome"
)

$ErrorActionPreference = "Stop"
$repo = $PSScriptRoot
$app  = Join-Path $repo "bazarcheck_app"

function Say($msg, $colour = "Cyan") { Write-Host "`n=== $msg ===" -ForegroundColor $colour }
function Ok($msg)   { Write-Host "  [ok]   $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  [warn] $msg" -ForegroundColor Yellow }
function Die($msg)  { Write-Host "  [fail] $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Say "Checking prerequisites"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Die "Flutter is not on PATH. Install from https://docs.flutter.dev/get-started/install/windows"
}
Ok "flutter  $((flutter --version 2>&1 | Select-Object -First 1))"

$hasPython = [bool](Get-Command python -ErrorAction SilentlyContinue)
if ($hasPython) { Ok "python   $((python --version 2>&1))" }
else            { Warn "python not found - the optional price service will be skipped" }

# ---------------------------------------------------------------------------
Say "Flutter dependencies"

Push-Location $app
try {
    flutter clean | Out-Null
    Ok "cleaned stale build output"

    flutter pub get
    if ($LASTEXITCODE -ne 0) { Die "flutter pub get failed" }
    Ok "dependencies resolved"

    if (-not $SkipTests) {
        Say "Static analysis"
        flutter analyze
        if ($LASTEXITCODE -ne 0) {
            Warn "flutter analyze reported problems (see above)"
            $reply = Read-Host "  Continue anyway? [y/N]"
            if ($reply -ne "y") { exit 1 }
        } else {
            Ok "no analyzer issues"
        }

        Say "Tests"
        flutter test
        if ($LASTEXITCODE -ne 0) { Warn "some Flutter tests failed (see above)" }
        else { Ok "Flutter tests passed" }
    }
}
finally { Pop-Location }

# ---------------------------------------------------------------------------
if ($hasPython) {
    Say "Price service (optional)"
    $svc = Join-Path $repo "ai_service"
    $envFile = Join-Path $svc ".env"
    if (-not (Test-Path $envFile)) {
        Copy-Item (Join-Path $svc ".env.example") $envFile
        Ok "created ai_service\.env from the example"
    } else {
        Ok "ai_service\.env already exists"
    }
    Write-Host "  Start it later with:  cd ai_service ; python main.py" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
Say "Database reminder" "Yellow"
Write-Host "
  The app needs its schema before it will show anything.

  1. Open  https://supabase.com/dashboard/project/fhctcrasoesugarhxuco/sql/new
  2. Paste ALL of  database\COMPLETE_SETUP.sql
  3. Run it

  Then sign up in the app and make yourself admin:

     UPDATE public.profiles SET role='admin' WHERE email='YOUR@EMAIL.COM';

  Without step 2 the app runs fine but every list shows ""Nothing here yet"".
" -ForegroundColor Yellow

# ---------------------------------------------------------------------------
if ($NoRun) {
    Say "Done" "Green"
    Write-Host "  Launch later with:  cd bazarcheck_app ; flutter run -d $Device" -ForegroundColor DarkGray
    exit 0
}

Say "Launching BazarCheck on $Device" "Green"
Write-Host "  r = hot reload   R = hot restart   q = quit`n" -ForegroundColor DarkGray
Push-Location $app
try { flutter run -d $Device }
finally { Pop-Location }
