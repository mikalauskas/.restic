# import functions
Set-ExecutionPolicy Bypass -Scope CurrentUser -Force

if (
    (!Test-Path -Path "$PSScriptRoot\.env-ps") -or
    (!Test-Path -Path "$PSScriptRoot\includes.txt") -or
    (!Test-Path -Path "$PSScriptRoot\excludes.txt")
    ) {
    Write-Error ".env-ps file is missing."
    exit 1
}

. .env-ps

"Downloading restic"
Remove-Item -Force "$env:TEMP\restic_$($env:RESTIC_VERSION)_windows_amd64.zip" -ErrorAction SilentlyContinue

Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/restic/restic/releases/download/v$($env:RESTIC_VERSION)/restic_$($env:RESTIC_VERSION)_windows_amd64.zip" -OutFile "$env:TEMP\restic_$($env:RESTIC_VERSION)_windows_amd64.zip"

"Uncompressing restic"
if (!(Test-Path -Path "$env:RESTIC_ROOT")) {
    New-Item -ItemType Directory -Path "$env:RESTIC_ROOT" -InformationAction SilentlyContinue -ErrorAction Stop
}

Remove-Item -Recurse -Force "$env:RESTIC_ROOT\restic.exe" -ErrorAction SilentlyContinue
Expand-Archive -Force -Path "$env:TEMP\restic_$($env:RESTIC_VERSION)_windows_amd64.zip" -DestinationPath "$env:RESTIC_ROOT" -ErrorAction SilentlyContinue
Move-Item "$env:RESTIC_ROOT\restic_$($env:RESTIC_VERSION)_windows_amd64.exe" "$env:RESTIC_ROOT\restic.exe" -ErrorAction SilentlyContinue

# TASK
"Stop and unregister restic scheduled task"
Stop-ScheduledTask -TaskName "restic" -ErrorAction SilentlyContinue
Unregister-ScheduledTask -Confirm:$false -TaskName "restic" -ErrorAction SilentlyContinue

"Register a scheduled task to start restic on logon"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -windowstyle hidden -ExecutionPolicy Bypass -File `"$env:RESTIC_ROOT\restic-backup.ps1`"" -WorkingDirectory $env:RESTIC_ROOT

$trigger = @( 
    $(New-ScheduledTaskTrigger -Daily -At 12pm -RandomDelay (New-TimeSpan -Minutes 2))
    #$(New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 60) -RepetitionDuration (New-TimeSpan -Days (365 * 20)))
)

$principal = New-ScheduledTaskPrincipal -UserID "$env:COMPUTERNAME\$env:RESTIC_USERNAME" -RunLevel Highest -LogonType S4U -Principal $principal

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 60) -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 24) -MultipleInstances Parallel
Register-ScheduledTask -Force -Action $action -Trigger $trigger -Settings $settings -Principal $principal -TaskName "restic" -Description "Starts restic services on user logon" 

#"Start restic scheduled task"
#Start-ScheduledTask -TaskName "restic"