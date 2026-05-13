# auto-push.ps1
# Watches index.html for changes and automatically commits + pushes to GitHub.
# Run with: powershell -ExecutionPolicy Bypass -File .\auto-push.ps1
# Stop with: Ctrl+C

$ErrorActionPreference = "Stop"
$repoPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$file = "index.html"
$debounceSeconds = 5
$lastChange = [DateTime]::MinValue

# Find git.exe — try PATH first, then GitHub Desktop's bundled copy
$gitExe = $null
$gitOnPath = Get-Command git -ErrorAction SilentlyContinue
if ($gitOnPath) {
    $gitExe = $gitOnPath.Source
} else {
    $candidates = @(
        "$env:LOCALAPPDATA\GitHubDesktop\app-*\resources\app\git\cmd\git.exe",
        "$env:LOCALAPPDATA\GitHubDesktop\app-*\resources\app\git\bin\git.exe",
        "$env:LOCALAPPDATA\Programs\GitHub Desktop\resources\app\git\cmd\git.exe",
        "$env:PROGRAMFILES\Git\cmd\git.exe",
        "${env:PROGRAMFILES(X86)}\Git\cmd\git.exe"
    )
    foreach ($pattern in $candidates) {
        $match = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($match) { $gitExe = $match.FullName; break }
    }
}

if (-not $gitExe) {
    Write-Host "Could not find git.exe." -ForegroundColor Red
    Write-Host "Looked on PATH and in common GitHub Desktop locations." -ForegroundColor Red
    Write-Host "Install Git from https://git-scm.com/download/win and re-run this script." -ForegroundColor Yellow
    exit 1
}

Set-Location $repoPath

Write-Host ""
Write-Host "Using git at: $gitExe" -ForegroundColor DarkCyan
Write-Host "Watching for changes to $file in $repoPath" -ForegroundColor Cyan
Write-Host "Auto-push is live. Leave this window open. Press Ctrl+C to stop." -ForegroundColor Cyan
Write-Host ""

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $repoPath
$watcher.Filter = $file
$watcher.IncludeSubdirectories = $false
$watcher.EnableRaisingEvents = $true

$action = { $global:lastChange = Get-Date }

Register-ObjectEvent -InputObject $watcher -EventName "Changed" -Action $action | Out-Null
Register-ObjectEvent -InputObject $watcher -EventName "Created" -Action $action | Out-Null

try {
    while ($true) {
        Start-Sleep -Seconds 1
        if ($lastChange -ne [DateTime]::MinValue) {
            $idleSeconds = ((Get-Date) - $lastChange).TotalSeconds
            if ($idleSeconds -ge $debounceSeconds) {
                $lastChange = [DateTime]::MinValue
                $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Write-Host "[$stamp] Change detected. Checking..." -ForegroundColor Yellow
                try {
                    & $gitExe add $file 2>&1 | Out-Null
                    & $gitExe diff --cached --quiet
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[$stamp] Nothing to commit." -ForegroundColor DarkGray
                    } else {
                        $msg = "auto: update $file ($stamp)"
                        & $gitExe commit -m $msg 2>&1 | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "[$stamp] Committed. Pushing..." -ForegroundColor Yellow
                            & $gitExe push 2>&1 | Out-Host
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "[$stamp] Pushed to origin." -ForegroundColor Green
                                Write-Host "[$stamp] Live in ~30s at https://jackmandall.github.io/bigchange-demo/" -ForegroundColor Green
                            } else {
                                Write-Host "[$stamp] Push failed. See output above." -ForegroundColor Red
                            }
                        } else {
                            Write-Host "[$stamp] Commit failed." -ForegroundColor Red
                        }
                    }
                } catch {
                    Write-Host "[$stamp] Error: $_" -ForegroundColor Red
                }
                Write-Host ""
            }
        }
    }
} finally {
    Get-EventSubscriber | Unregister-Event
    $watcher.Dispose()
}
