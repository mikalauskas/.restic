# set Priotity of a Process to BelowNormal
$process = Get-Process -Id $pid
$process.PriorityClass = "BelowNormal"

Start-Transcript -Path restic.log -Append -Force -IncludeInvocationHeader

# read .env file
. (Join-Path $PSScriptRoot .env.ps1)

New-LockFile -LockFile "restic" | Out-Null

# self-update

Set-Location $PSScriptRoot
git config --global --add safe.directory $PSScriptRoot
git pull

. $env:RESTIC_EXEC self-update

function New-LockFile () {
    [CmdletBinding()]
    param (
        [string]
        $Path = $PSScriptRoot,

        [string] $LockFile
    )
    # Check if lock file is present and has LastModifTime less than 15 mins
    if (Test-Path -Path "$Path\$LockFile.lockfile") {
        $lockFileTest = Get-Item -Path "$Path\$LockFile.lockfile" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddSeconds(-30) }
        if ($lockFileTest) {
            Write-Host "$(Get-Date): $LockFile lockfile is old"
            $PID | Out-File -Force -NoNewline -Encoding default -FilePath "$Path\$LockFile.lockfile"
            Return $true
        } else {
            Write-Host "$(Get-Date): $LockFile lockfile is new"
            Exit
        }
    } else {
        $PID | Out-File -Force -NoNewline -Encoding default -FilePath "$Path\$LockFile.lockfile"
        Return $true
    }
}

function Start-BackroundJob () {
    param (
        [Scriptblock] $ScriptBlock,

        [string] $Name = $(Get-Random),

        [Scriptblock] $Init,

        [string] $Path = $PSScriptRoot,

        [string] $LockFile
    )

    $Job = Start-Job -Name $Name -InitializationScript $init -ScriptBlock $scriptBlock
    while ($true) {
        $JobCount = (Get-Job -Name $Name | Where-Object -Property State -EQ Running).Count
        if ($JobCount -gt 0) {
            $PID | Out-File -Force -NoNewline -Encoding default -FilePath "$Path\$LockFile.lockfile"
            Start-Sleep 2
        } else {
            Receive-Job -Job $Job
            break
        }
    }
}

Start-BackroundJob -LockFile "restic" -ScriptBlock {
    # read .env file
    . (Join-Path $PSScriptRoot .env.ps1)

    function Invoke-ResticUnlock () {
        Write-Output "**********"
        Write-Output "Unlock job: Begin"
        Write-Output "**********"
        
        do {
            Start-Sleep 5
            Write-Output "$(Get-Date) Unlock job: Unlocking..."
            . $env:RESTIC_EXEC unlock --cleanup-cache
        } while (. $env:RESTIC_EXEC -q list locks --no-lock)
        Write-Output "**********"
        Write-Output "Unlock job: End"
        Write-Output "**********"
    }

    function Invoke-ResticCheck () {
        Write-Output "**********"
        Write-Output "Check Errors job: Begin"
        Write-Output "**********"
        
        . $env:RESTIC_EXEC check --read-data-subset '2%' --cleanup-cache
        
        Write-Output "**********"
        Write-Output "Check Errors job: End"
        Write-Output "**********"
        # if (!$?) {
        #     Write-Output "**********"
        #     Write-Output "Rebuild-index job: Begin"
        #     Write-Output "**********"
        #     . $env:RESTIC_EXEC rebuild-index --cleanup-cache
        #     Write-Output "**********"
        #     Write-Output "Rebuild-index job: End"
        #     Write-Output "**********"
        # }
    }

    function Invoke-RegistryDump {
        $dateBegin = Get-Date
        Write-Output "**********"
        Write-Output "Registry backup job: Begin"
        Write-Output "**********"
        Remove-Item -Force -Recurse -Path "$($env:RESTIC_ROOT)\RegBack\*"
        $Code = {
            param ($path)
            if (-not (Test-Path -Path "$($env:RESTIC_ROOT)\RegBack\$path")) { New-Item -Force -ItemType Directory -Path "$($env:RESTIC_ROOT)\RegBack\$path" }
            Get-ChildItem -Recurse -Depth 1 -Path Registry::$path -ErrorAction Continue | ForEach-Object {
                $fullRegPath = $_.Name
                $registryFileName = $_ -replace '_','' -replace '\\','_' -replace ' ','_'
                reg export $fullRegPath "$($env:RESTIC_ROOT)\RegBack\${path}\${registryFileName}.reg" /y
            }
        }
        $jobs = @()
        ("HKEY_CURRENT_USER","HKEY_LOCAL_MACHINE","HKEY_USERS","HKEY_CURRENT_CONFIG") | ForEach-Object { $jobs += Start-Job -ArgumentList $_ -ScriptBlock $Code }

        Wait-Job -Job $jobs | Out-Null
        # Receive-Job -Job $jobs

        # registry -path "HKEY_CLASSES_ROOT" -depth 0
        Compress-Archive -Path "$($env:RESTIC_ROOT)\RegBack\*" -DestinationPath "$($env:RESTIC_ROOT)\RegBack\RegBack.zip"
        Remove-Item -Force -Recurse -Exclude "RegBack.zip" -Path "$($env:RESTIC_ROOT)\RegBack\*"

        $dateTimespan = New-TimeSpan -Start $dateBegin -End (Get-Date)
        $dateEndMinutes = $dateTimespan.Minutes
        $dateEndSeconds = $dateTimespan.Seconds
        Write-Output "**********"
        Write-Output "Registry backup job: Done in ${dateEndMinutes}:${dateEndSeconds}"
        Write-Output "**********"
    }

    function Invoke-EventLogDump {
        $ExportFileSuffix = "_" + (Get-Date).ToString("yyyy-MM-dd-hh-mm-ss") + ".csv"
        Write-Output "**********"
        Write-Output "Event logs backup job: Begin"
        Write-Output "**********"
        Remove-Item -Force -Recurse -Path "$($env:RESTIC_ROOT)\EventLogs\*"

        if (-not (Test-Path -Path "$($env:RESTIC_ROOT)\EventLogs")) { New-Item -Force -ItemType Directory -Path "$($env:RESTIC_ROOT)\EventLogs" }
        Get-EventLog -LogName "Application" -EntryType "Error","Warning" -After (Get-Date).AddDays(-2) | Sort-Object TimeGenerated | Select-Object EntryType, TimeGenerated, Source, EventID, Message | Export-CSV "$($env:RESTIC_ROOT)\EventLogs\Application${ExportFileSuffix}" -NoTypeInfo
        Get-EventLog -LogName "System" -EntryType "Error","Warning" -After (Get-Date).AddDays(-2) | Sort-Object TimeGenerated | Select-Object EntryType, TimeGenerated, Source, EventID, Message | Export-CSV "$($env:RESTIC_ROOT)\EventLogs\System${ExportFileSuffix}" -NoTypeInfo
        
        Compress-Archive -Path "$($env:RESTIC_ROOT)\EventLogs\*" -DestinationPath "$($env:RESTIC_ROOT)\EventLogs\EventLogs.zip"
        Remove-Item -Force -Recurse -Exclude "EventLogs.zip" -Path "$($env:RESTIC_ROOT)\EventLogs\*"
        
        Write-Output "**********"
        Write-Output "Event logs backup job: End"
        Write-Output "**********"
    }

    function Invoke-ResticBackup () {
        Write-Output "**********"
        Write-Output "Backup job: Begin"
        Write-Output "**********"
        . $env:RESTIC_EXEC backup -v --compression auto --use-fs-snapshot --host $env:RESTIC_HOSTNAME --exclude-file $env:RESTIC_EXCLUDE_FILE --files-from $env:RESTIC_INCLUDE_FILE --cleanup-cache
        Write-Output "**********"
        Write-Output "Backup job: End"
        Write-Output "**********"
    }

    function Invoke-ResticForget () {
        Write-Output "**********"
        Write-Output "Forget job: Begin"
        Write-Output "**********"
        . $env:RESTIC_EXEC forget -v --compression auto --prune -d $env:RESTIC_PRUNE_DAYS -w $env:RESTIC_PRUNE_WEEKS -m $env:RESTIC_PRUNE_MONTHS -y $env:RESTIC_PRUNE_YEARS --host $env:RESTIC_HOSTNAME --group-by host --cleanup-cache
        Write-Output "**********"
        Write-Output "Forget job: End"
        Write-Output "**********"
    }
    if ($env:RESTIC_DO_REGISTRY_DUMP -eq 1) { Invoke-RegistryDump }
    if ($env:RESTIC_DO_EVENTLOG_DUMP -eq 1) { Invoke-EventLogDump }
    
    Invoke-ResticUnlock
    Invoke-ResticBackup

    Invoke-ResticUnlock
    Invoke-ResticForget
}

Remove-Item -Force -Path "restic.lockfile"

Stop-Transcript