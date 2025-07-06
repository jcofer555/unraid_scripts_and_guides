$ProgressPreference = 'SilentlyContinue'
# Define log path and logging function for errors
$log = "C:\Users\Public\Desktop\LOG.txt"
function Log-Failure {
    param ($error_message)
    Out-File -FilePath $log -InputObject $error_message -Append
    Write-Host $error_message -ForegroundColor Red
}

# Define log path and logging function for started/finished
$started_finished_log = "C:\Users\Public\Desktop\SUCCESS_LOG.txt"
function Log-Started-Finished {
    param ($started_finished_message)
    Out-File -FilePath $started_finished_log -InputObject $started_finished_message -Append
    Write-Host $started_finished_message -ForegroundColor Green
}

# Define log path and logging function for install apps
$install_apps_log = "C:\Users\Public\Desktop\SUCCESS_LOG.txt"
function Log-Install-Apps {
    param ($install_apps_message)
    Out-File -FilePath $install_apps_log -InputObject $install_apps_message -Append
    Write-Host $install_apps_message -ForegroundColor Yellow
}

# Start runonfirstboot script
Log-Started-Finished "Started: Starting runonfirstboot script"
Write-Host

# Discord function
$env:DISCORD_WEBHOOK_URL = 'https://discord.com/api/webhooks/asdfasdf'
function send_discord_message {
    param (
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Message,

        [int]$Color = 3447003,  # Default blue-ish color
        [string]$WebhookUrl = $env:DISCORD_WEBHOOK_URL  # Optional: set this as an environment variable
    )

    if (-not $WebhookUrl) {
        throw "Discord Webhook URL not provided. Set it via -WebhookUrl or the DISCORD_WEBHOOK_URL environment variable."
    }

    $payload = @{
        embeds = @(@{
            title = $Title
            description = $Message
            color = $Color
            timestamp = (Get-Date).ToString("o")
        })
    }

    Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body ($payload | ConvertTo-Json -Depth 4) -ContentType 'application/json'
}

# Start runonfirstboot script time tracking
Log-Started-Finished "Started: Starting runonfirstboot script time tracking"
$start_time = [int](Get-Date -UFormat %s)
Write-Host

# Restart openvpn
Log-Started-Finished "Started: Restarting openvpn"
try {
    # Kill any running instance
    Stop-Process -Name "openvpn-gui" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # Launch it
    Start-Process -FilePath "C:\Program Files\OpenVPN\bin\openvpn-gui.exe" -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 5

    # Close it again
    Stop-Process -Name "openvpn-gui" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

} catch {
    Log-Failure "Restarting openvpn failed: $_"
}
Log-Started-Finished "Finished: Restarting openvpn"
Write-Host

# Set openvpn gui show balloon to never
Log-Started-Finished "Started: Setting openvpn gui show balloon to never"
try {
    $regPath = "HKCU:\Software\OpenVPN-GUI"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    Set-ItemProperty -Path $regPath -Name "show_balloon" -Value 0 -Type DWord -Force

} catch {
    Log-Failure "Setting openvpn gui show balloon to never failed: $_"
}
Log-Started-Finished "Finished: Setting openvpn gui show balloon to never finished"
Write-Host

# Enable silent connection for openvpn gui
Log-Started-Finished "Started: Enabling silent connection for openvpn gui"
try {
    $regPath = "HKCU:\Software\OpenVPN-GUI"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    Set-ItemProperty -Path $regPath -Name "silent_connection" -Value 1 -Type DWord -Force

} catch {
    Log-Failure "Enabling silent connection for openvpn gui failed: $_"
}
Log-Started-Finished "Finished: Enabling silent connection for openvpn gui finished"
Write-Host

# Install microsoft to-do via winget
Log-Started-Finished "Started: Installing microsoft to-do via winget"
try {
    Start-Process winget -ArgumentList 'install', '--id', '9NBLGGH5R558', '--accept-source-agreements', '--accept-package-agreements' -Wait -WindowStyle Hidden
} catch {
    Log-Failure "Installing microsoft to-do via winget failed: $_"
}
Log-Started-Finished "Finished: Installing microsoft to-do via winget finished"
Write-Host

# Install snipping tool via winget
Log-Started-Finished "Started: Installing snipping tool via winget"
try {
	Start-Process winget -ArgumentList 'install', '--id', '9MZ95KL8MR0L', '--accept-source-agreements', '--accept-package-agreements' -Wait -WindowStyle Hidden
} catch {
    Log-Failure "Installing snipping tool via winget failed: $_"
}
Log-Started-Finished "Finished: Installing snipping tool via winget finished"
Write-Host

# Install discord via winget
Log-Started-Finished "Started: Installing discord via winget"
try {
    Start-Process winget -ArgumentList 'install', '--id', 'Discord.Discord', '--accept-source-agreements', '--accept-package-agreements' -Wait -WindowStyle Hidden
} catch {
    Log-Failure "Installing discord via winget failed: $_"
}
Log-Started-Finished "Finished: Installing discord via winget finished"
Write-Host

# Copy appdata
# Discord
Log-Started-Finished "Started: Copying discord appdata"
try {
    $discordSrc = "Y:\computer\backups\vms appdata\discord backup"
    $discordDst = "C:\Users\Administrator\AppData\Roaming\discord"

    if (-not (Test-Path $discordSrc)) {
        throw "Missing Discord backup folder at $discordSrc"
    }

    Stop-Process -Name "discord" -Force
    Start-Sleep -Seconds 5

    Remove-Item -LiteralPath $discordDst -Recurse -Force
    Copy-Item -Path $discordSrc -Destination $discordDst -Recurse -Force
} catch {
    Log-Failure "Copying discord appdata failed: $_"
}
Log-Started-Finished "Finished: Copying discord appdata finished"
Write-Host

# Rustdesk
Log-Started-Finished "Started: Copying rustdesk appdata"
try {
    $rustdeskExe = "C:\Program Files\RustDesk\rustdesk.exe"
    $rustdeskSrc = "Y:\computer\backups\vms appdata\rustdesk backup"
    $rustdeskDst = "C:\Users\Administrator\AppData\Roaming\RustDesk\config"
	$ahkPath = "Y:\computer\scripts\win11doafter\supportfiles\rustdeskservicestart.ahk"
    $ahkDst = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\rustdeskservicestart.ahk"

    if (-not (Test-Path $rustdeskSrc)) {
        throw "Missing rustdesk backup folder at $rustdeskSrc"
    }

    Start-Process $rustdeskExe
    Start-Sleep -Seconds 7
    Stop-Process -Name "rustdesk" -Force
    Start-Sleep -Seconds 5

    Remove-Item -LiteralPath $rustdeskDst -Recurse -Force
    Copy-Item -Path $rustdeskSrc -Destination $rustdeskDst -Recurse -Force
	Copy-Item -Path $ahkPath -Destination $ahkDst -Force
} catch {
    Log-Failure "Copying rustdesk appdata failed: $_"
}
Log-Started-Finished "Finished: Copying rustdesk appdata finished"
Write-Host

# Remove widgets and windows web experience pack
Log-Started-Finished "Started: Removing widgets and windows web experience pack"
try {
    Get-AppxPackage *WebExperience* | Remove-AppxPackage
} catch {
    Log-Failure "Removing widgets and windows web experience pack failed: $_"
}
Log-Started-Finished "Finished: Removing widgets and windows web experience pack finished"
Write-Host

# Apply taskbar xml layout
Log-Started-Finished "Started: Applying taskbar xml layout"
try {
    $layoutXml = "Y:\computer\scripts\win11doafter\supportfiles\taskbar.xml"
    if (-not (Test-Path $layoutXml)) {
        throw "Missing taskbar xml layout file at $layoutXml"
    }

    $explorerPol = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
    New-Item -Path $explorerPol -Force | Out-Null
    Set-ItemProperty -Path $explorerPol -Name "LockedStartLayout" -Value 1 -Type DWord
    Set-ItemProperty -Path $explorerPol -Name "StartLayoutFile" -Value $layoutXml -Type ExpandString

    Stop-Process -Name explorer -Force
    Start-Sleep -Seconds 5
    Start-Process explorer.exe
    Start-Sleep -Seconds 7

    & "Y:\computer\scripts\win11doafter\autohotkeys\close_file_explorer.exe" | Out-Null

    # Cleanup layout lockdown after first reload
    Remove-ItemProperty -Path $explorerPol -Name "LockedStartLayout" -Force
    Remove-ItemProperty -Path $explorerPol -Name "StartLayoutFile" -Force

    # Clear NoPinningToTaskbar
    Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "NoPinningToTaskbar" -Value 0 -Type DWord
    Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\Explorer" -Name "NoPinningToTaskbar" -Value 0 -Type DWord

    Stop-Process -Name explorer -Force
    Start-Sleep -Seconds 5
    Start-Process explorer.exe
    Start-Sleep -Seconds 7

    & "Y:\computer\scripts\win11doafter\autohotkeys\close_file_explorer.exe" | Out-Null
} catch {
    Log-Failure "Applying taskbar xml layout failed: $_"
}
Log-Started-Finished "Finished: Applying taskbar xml layout finished"
Write-Host

# Replace start menu pin layout
Log-Started-Finished "Started: Replacing start menu pin layout"
try {
    $startBinPath = "C:\Users\Administrator\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2.bin"
    $customBinPath = "Y:\computer\scripts\win11doafter\supportfiles\start2.bin"

    if (-not (Test-Path $customBinPath)) {
        throw "Missing start menu pin layout file at $customBinPath"
    }

    Remove-Item -Path $startBinPath -Force -ErrorAction Stop
    Copy-Item -Path $customBinPath -Destination $startBinPath -Force
} catch {
    Log-Failure "Replacing start menu pin layout failed: $_"
}
Log-Started-Finished "Finished: Replacing start menu pin layout finished"
Write-Host

# Disable windows defender antispyware
Log-Started-Finished "Started: Disabling windows defender antispyware"
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 1 -Force
} catch {
    Log-Failure "Disabling windows defender antispyware failed: $_"
}
Log-Started-Finished "Finished: Disabling windows defender antispyware finished"
Write-Host

# Set file associations
Log-Started-Finished "Started: Setting file associations"
try {
    # Define paths
    $SetFTAPath = "Y:\computer\scripts\win11doafter\apps\SetUserFTA\SetUserFTA.exe"
    $NotepadPPPath = "C:\Program Files\Notepad++\notepad++.exe"
    $AHKPath = "Y:\computer\scripts\win11doafter\autohotkeys\setuserfta.exe"

    # Validate dependencies
    if (-not (Test-Path $SetFTAPath)) {
        throw "SetUserFTA.exe not found at $SetFTAPath."
    }
    if (-not (Test-Path $NotepadPPPath)) {
        throw "Notepad++ not found at $NotepadPPPath."
    }
    if (-not (Test-Path $AHKPath)) {
        throw "AHK automation executable not found at $AHKPath."
    }

    # Start AHK helper in background
    $ahkProcess = Start-Process -FilePath $AHKPath -PassThru -WindowStyle Hidden

    # Define ProgID and register if missing
    $ProgID = "Applications\\notepad++.exe"
    $ProgIDRegPath = "Registry::HKEY_CLASSES_ROOT\$ProgID"

    if (-not (Test-Path $ProgIDRegPath)) {
        New-Item -Path $ProgIDRegPath -Force | Out-Null
        New-ItemProperty -Path $ProgIDRegPath -Name "FriendlyAppName" -Value "Notepad++" -Force | Out-Null

        $commandPath = Join-Path $ProgIDRegPath "shell\open\command"
        New-Item -Path $commandPath -Force | Out-Null
        Set-ItemProperty -Path $commandPath -Name "(default)" -Value "`"$NotepadPPPath`" `"%1`"" -Force | Out-Null
    }

    # Grouped extension batches
    $groups = @(
        @(".txt", ".json", ".yaml", ".yml", ".ini"),
        @(".js", ".php", ".xml", ".old", ".bak"),
        @(".log", ".css", ".reg", ".ps1", ".vbs"),
        @(".toml", ".sh", ".bash", ".cfg", ".sample")
    )

    foreach ($group in $groups) {
        foreach ($ext in $group) {
            & $SetFTAPath $ext $ProgID
        }
        Start-Sleep -Seconds 3
    }

    # Done — stop the AHK popup-clicker
    if ($ahkProcess -and !$ahkProcess.HasExited) {
        $ahkProcess | Stop-Process
    }

} catch {
    Log-Failure "Setting file associations failed: $_"
}
Log-Started-Finished "Finished: Setting file associations finished"
Write-Host

# Remove deploy started marker
Log-Started-Finished "Started: Removing deploy started marker"
try {
    Remove-Item -LiteralPath "C:\Users\Administrator\Desktop\DEPLOY STARTED.txt" -Recurse -Force
} catch {
    Log-Failure "Removing deploy started marker failed: $_"
}
Log-Started-Finished "Finished: Removing deploy started marker finished"
Write-Host

# Copy final deploy completed marker
Log-Started-Finished "Started: Copying final deploy completed marker"
try {
    $src = "Y:\computer\scripts\win11doafter\Z - deploy done.txt"
    $dst = "C:\Users\Administrator\Desktop\DEPLOY DONE.txt"

    if (-not (Test-Path $src)) {
        throw "Missing final deploy completed marker file at $src"
    }

    Copy-Item -Path $src -Destination $dst -Force
} catch {
    Log-Failure "Copying final deploy completed marker failed: $_"
}
Log-Started-Finished "Finished: Copying final deploy completed marker finished"
Write-Host

# Delete start scripts
Log-Started-Finished "Started: Deleting start scripts"
try {
    Remove-Item 'C:\Users\Public\Desktop\win11-startscripts.ps1' -ErrorAction SilentlyContinue
} catch {
    Log_Failure "Deleting start scripts failed: $_"
}
Log-Started-Finished "Finished: Deleting start scripts finished"
Write-Host

# Stop runonfirstboot script time tracking
Log-Started-Finished "Started: Stopping runonfirstboot script time tracking"
try {
    $end_time = [int](Get-Date -UFormat %s)
    Write-Host

    # Calculate, build, construct, and log length of time runonfirstboot script ran
    Log-Started-Finished "Started: Calculating, building, constructing, and logging length of time runonfirstboot script ran"

    $duration = $end_time - $start_time
    $hours = [int]($duration / 3600)
    $minutes = [int](($duration % 3600) / 60)
    $seconds = $duration % 60

    if ($hours -gt 0) {
        $DURATION_MSG = "$hours hours, $minutes minutes, and $seconds seconds"
    } elseif ($minutes -gt 0) {
        $DURATION_MSG = "$minutes minutes, and $seconds seconds"
    } else {
        $DURATION_MSG = "$seconds seconds"
    }

    $COMPUTERNAME = $env:COMPUTERNAME.ToLower()
    $DEPLOYMENT_SUMMARY = @"
Runonfirstboot script has finished taking $DURATION_MSG
"@

    $DEPLOYMENT_SUMMARY | Tee-Object -FilePath "C:\Users\Public\Desktop\TIME_LOG.txt" -Append | Out-Null

    Log-Started-Finished "Finished: Calculating, building, constructing, and logging length of time runonfirstboot script ran finished"
}
catch {
    Log-Failure "Tracking runonfirstboot script duration failed: $_"
}
Write-Host

# Copy contents of TIME_LOG to LOG
Log-Started-Finished "Started: Copying contents of TIME_LOG to LOG"
try {
    $sourcePath = 'C:\Users\Public\Desktop\TIME_LOG.txt'
    $destPath = 'C:\Users\Public\Desktop\LOG.txt'

    if (-not (Test-Path $sourcePath)) {
        throw "Missing TIME_LOG file at $sourcePath"
    }

    Get-Content -Path $sourcePath -ErrorAction Stop | Add-Content -Path $destPath -ErrorAction Stop

    Log-Started-Finished "Finished: Copying contents of TIME_LOG to LOG finished"
}
catch {
    Log-Failure "Copying contents of TIME_LOG to LOG failed: $_"
}
Write-Host

# Delete TIME_LOG
Log-Started-Finished "Started: Deleting TIME_LOG"
try {
    Remove-Item 'C:\Users\Public\Desktop\TIME_LOG.txt' -ErrorAction SilentlyContinue
} catch {
    Log_Failure "Deleting TIME_LOG failed: $_"
}
Log-Started-Finished "Finished: Deleting TIME_LOG finished"
Write-Host

# Calculate total time and send discord message of LOG
Log-Started-Finished "Started: Calculating total time and send discord message of LOG"
try {
    if (-not (Test-Path $log)) {
        throw "Missing LOG file at $log"
    }

    $lines = Get-Content -Path $log -ErrorAction Stop
    $totalSeconds = 0

    foreach ($line in $lines) {
        if ($line -match 'taking (\d+)\s+hours?,\s+(\d+)\s+minutes?,\s+and\s+(\d+)\s+seconds?') {
            $totalSeconds += ([int]$matches[1] * 3600 + [int]$matches[2] * 60 + [int]$matches[3])
        }
        elseif ($line -match 'taking (\d+)\s+minutes?,\s+and\s+(\d+)\s+seconds?') {
            $totalSeconds += ([int]$matches[1] * 60 + [int]$matches[2])
        }
        elseif ($line -match 'taking (\d+)\s+seconds?') {
            $totalSeconds += [int]$matches[1]
        }
    }

    $totalHours = [math]::Floor($totalSeconds / 3600)
    $remainder = $totalSeconds % 3600
    $totalMinutes = [math]::Floor($remainder / 60)
    $remainingSeconds = $remainder % 60

    $resultParts = @()
    if ($totalHours -gt 0) { $resultParts += "$totalHours hours" }
    if ($totalMinutes -gt 0) { $resultParts += "$totalMinutes minutes" }
    if ($remainingSeconds -gt 0 -or $resultParts.Count -eq 0) { $resultParts += "$remainingSeconds seconds" }
    Add-Content -Path $log -Value ("Total time taken to deploy was " + ($resultParts -join ", "))

	# Deploy done for $COMPUTERNAME
	Log-Started-Finished "Started: Deploy done for $COMPUTERNAME"
	Add-Content -Path $log -Value "Deploy done for $COMPUTERNAME"

    $FINAL_DEPLOYMENT_SUMMARY = Get-Content -Path $log -Raw -ErrorAction Stop
    send_discord_message -Title "Deployment Status:" -Message $FINAL_DEPLOYMENT_SUMMARY -Color 65280

    Log-Started-Finished "Finished: Calculating total time and send discord message of LOG finished"
	
}
catch {
    Log-Failure "Calculating total time and sending discord message failed: $_"
}

#Read-Host -Prompt "Press Enter to continue"

Log-Started-Finished "Finished: Runonfirstboot script finished"

# Reboot system
Log-Started-Finished "Started: Rebooting $COMPUTERNAME after deploy finished"
try {
    Restart-Computer -Force
} catch {
    Log-Failure "Rebooting failed: $_"
}
