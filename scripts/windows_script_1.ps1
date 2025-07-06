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

# Script wide variables
$COMPUTERNAME = $env:COMPUTERNAME.ToLower()

# Prereqs finishes
Log-Started-Finished "Finished: Prereqs finished"
Write-Host

# Start machine script time tracking
Log-Started-Finished "Started: Starting machine script time tracking"
$start_time = [int](Get-Date -UFormat %s)
Write-Host

# Set execution policy to bypass for the system
Log-Started-Finished "Started: Setting execution policy to bypass for the system"
try {
    $arguments = '-Command "Set-ExecutionPolicy Bypass -Scope LocalMachine -Force"'
    $process = Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs -Wait -WindowStyle Hidden -PassThru

    if ($process.ExitCode -ne 0) {
        throw "ExecutionPolicy process exited with code $($process.ExitCode)"
    }

    Log-Started-Finished "Finished: Setting execution policy to bypass for the system finished"
}
catch {
    Log-Failure "Setting execution policy to bypass for the system failed: $_"
}
Write-Host

# Set file types to bypass popup when opening
Log-Started-Finished "Started: Setting file types to bypass popup when opening"
try {
    if (-not (Test-Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Associations")) {
        New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies" -Name "Associations" -Force | Out-Null
    }
    New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Associations" `
        -Name "LowRiskFileTypes" -Value ".bat;.ps1;.vbs;.reg;.exe;.xml;.iso,.msi" -Force | Out-Null
} catch {
    Log-Failure "Setting file types to bypass popup when opening failed for file types: $_"
}
Log-Started-Finished "Finished: Setting file types to bypass popup when opening finished"
Write-Host

# Copy powerplan and virtio to the desktop
Log-Started-Finished "Started: Copying powerplan and virtio to the desktop"
try {
    foreach ($folder in @("powerplan", "apps\virtio")) {
        $src = "Y:\computer\scripts\win11doafter\$folder"
        $dst = "C:\Users\Administrator\Desktop\$([System.IO.Path]::GetFileName($folder))"

        if (-not (Test-Path $src)) {
            throw "Missing source folder $folder at $src"
        }

        Copy-Item -Path $src -Destination $dst -Recurse -Force
    }
} catch {
    Log-Failure "Copying powerplan and virtio to the desktop failed: $_"
}
Log-Started-Finished "Finished: Copying powerplan and virtio to the desktop finished"
Write-Host

# Copy change after done to desktop
Log-Started-Finished "Started: Copying change after done to desktop"
try {
    $src = "Y:\computer\scripts\win11doafter\changesafterdone\${COMPUTERNAME} change after done.txt"
    $dst = "C:\Users\Administrator\Desktop\CHANGE AFTER DONE.txt"

    if (-not (Test-Path $src)) {
        throw "Missing change after done file at $src"
    }

    Copy-Item -Path $src -Destination $dst -Force
} catch {
    Log-Failure "Copying change after done to desktop failed: $_"
}
Log-Started-Finished "Finished: Copying change after done to desktop finished"
Write-Host

# Copy deploy started to desktop
Log-Started-Finished "Started: Copying deploy started to desktop"
try {
    $src = "Y:\computer\scripts\win11doafter\Z - deploy started.txt"
    $dst = "C:\Users\Administrator\Desktop\DEPLOY STARTED.txt"

    if (-not (Test-Path $src)) {
        throw "Missing deploy started marker file at $src"
    }

    Copy-Item -Path $src -Destination $dst -Recurse -Force
} catch {
    Log-Failure "Copying deploy started marker failed: $_"
}
Log-Started-Finished "Finished: Copying deploy started to desktop finished"
Write-Host

# Map network shares
Log-Started-Finished "Started: Mapping network shares"
try {
    $driveMappings = @(
        @{ Letter = "V:"; Path = "\\10.100.10.210\DeploymentShare$"; Label = "deployment_share" },
        @{ Letter = "W:"; Path = "\\10.100.10.250\flash"; Label = "flash" },
        @{ Letter = "X:"; Path = "\\10.100.10.250\cacheonly_shares"; Label = "cacheonly_shares" },
        @{ Letter = "T:"; Path = "\\10.100.10.250\mymedia"; Label = "mymedia" }
    )

    foreach ($map in $driveMappings) {
        if (-not (Test-Connection -ComputerName ($map.Path -split '\\')[2] -Count 1 -Quiet)) {
            throw "Cannot reach network host for $($map.Label): $($map.Path) so mapping failed"
        }

        Start-Process cmd.exe -ArgumentList "/c", "net use $($map.Letter) `"$($map.Path)`" /savecred /Persistent:Yes" -Wait
    }
} catch {
    Log-Failure "Mapping network shares failed: $_"
}
Log-Started-Finished "Finished: Mapping network shares finished"
Write-Host

# Drivers
# Bluetooth
Log-Started-Finished "Started: Installing bluetooth driver"
try {
    $btInstaller = "Y:\computer\scripts\win11doafter\drivers\shared\bluetooth.exe"

    if (-not (Test-Path $btInstaller)) {
        throw "Missing bluetooth driver file at $btInstaller"
    }

    Start-Process -FilePath $btInstaller -ArgumentList "/qn" -Wait
} catch {
    Log-Failure "Installing bluetooth driver failed: $_"
}
Log-Started-Finished "Finished: Installing bluetooth driver finished"
Write-Host

# Nvidia video
Log-Started-Finished "Started: Installing nvidia video driver"
try {
    $nvidiaInstaller = "Y:\computer\scripts\win11doafter\drivers\shared\video\setup.exe"

    if (-not (Test-Path $nvidiaInstaller)) {
        throw "Missing nvidia video driver file at $nvidiaInstaller"
    }

    Start-Process -FilePath $nvidiaInstaller -ArgumentList "/s Display.Driver", "/noreboot", "/clean" -Wait
    Start-Sleep -Seconds 20
} catch {
    Log-Failure "Installing nvidia video driver failed: $_"
}
Log-Started-Finished "Finished: Installing nvidia video driver finished"
Write-Host

# Import monitor config
Log-Started-Finished "Started: Importing monitor config"
try {
    $configPath = "Y:\computer\scripts\win11doafter\supportfiles\monitorconfig-kingcrab.xml"

    if (-not (Test-Path $configPath)) {
        throw "Missing monitor config file at $configPath"
    }

    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    Install-Module DisplayConfig -Force | Out-Null
    Import-Module DisplayConfig -Force | Out-Null

    $config = Import-Clixml $configPath
    $config | Use-DisplayConfig -UpdateAdapterIds
} catch {
    Log-Failure "Importing monitor config failed: $_"
}
Log-Started-Finished "Finished: Importing monitor config finished"
Write-Host

# Set network connection profile to private
Log-Started-Finished "Started: Setting network connection profile to private"
try {
    Set-NetConnectionProfile -NetworkCategory Private | Out-Null
} catch {
    Log-Failure "Setting network connection profile to private failed: $_"
}
Log-Started-Finished "Finished: Setting network connection profile to private finished"
Write-Host

# Allow file and printer sharing and network discovery through firewall
Log-Started-Finished "Started: Allowing file and printer sharing and network discovery through firewall"
try {
    $groups = @("File and Printer Sharing", "Network Discovery")

    foreach ($group in $groups) {
        $rules = Get-NetFirewallRule -DisplayGroup $group -ErrorAction Stop
        $rules | Enable-NetFirewallRule
    }

    Log-Started-Finished "Finished: Allowing file and printer sharing and network discovery through firewall finished"
}
catch {
    Log-Failure "Allowing file and printer sharing and network discovery through firewall failed: $_"
}
Write-Host

# Allow remote desktop through firewall
Log-Started-Finished "Started: Allowing remote desktop through firewall"
try {
    New-NetFirewallRule -DisplayName "Remote Desktop" -Direction Inbound -Protocol TCP `
        -LocalPort 3389 -Action Allow -Profile Any | Out-Null
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections `
        /t REG_DWORD /d 0 /f | Out-Null
    netsh advfirewall firewall set rule group="Remote Desktop" new enable=Yes | Out-Null
} catch {
    Log-Failure "Allowing remote desktop through firewall failed: $_"
}
Log-Started-Finished "Finished: Allowing remote desktop through firewall finished"
Write-Host

# Apply power plan
Log-Started-Finished "Started: Applying power plan"
try {
    $ppScript = "C:\Users\Administrator\Desktop\powerplan\powerplan.bat"

    if (-not (Test-Path $ppScript)) {
        throw "Missing power plan file at $ppScript"
    }

    & $ppScript > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Applying power plan script failed with exit code $LASTEXITCODE"
    }

} catch {
    Log-Failure "Applying power plan failed: $_"
}
Log-Started-Finished "Finished: Applying power plan finished"
Write-Host

# Add firewall allows
Log-Started-Finished "Started: Adding firewall allows"
try {
    # Microsip
    New-NetFirewallRule -DisplayName "Allow microsip full access" `
        -Direction Inbound `
        -Action Allow `
        -Program "C:\Users\Administrator\AppData\Local\MicroSIP\microsip.exe" `
        -Profile Private `
        -Enabled True | Out-Null

    # Plex
    New-NetFirewallRule -DisplayName "Allow plex full access" `
        -Direction Inbound `
        -Action Allow `
        -Program "C:\program files\plex\plex\plex.exe" `
        -Profile Private `
        -Enabled True | Out-Null

} catch {
    Log-Failure "Adding firewall allows failed: $_"
}
Log-Started-Finished "Finished: Adding firewall allows"
Write-Host

# Set defender exclusions
Log-Started-Finished "Started: Setting defender exclusions"
try {
    $exclusionPaths = @(
        "Y:\computer\test"
    )

    $exclusionProcesses = @(
        "test.exe"
    )

    foreach ($path in $exclusionPaths) {
        $proc = Start-Process powershell.exe `
            -ArgumentList "-ExecutionPolicy", "Bypass", "-NonInteractive", "-Command", "Add-MpPreference -ExclusionPath '$path'" `
            -Wait -NoNewWindow -PassThru

        if ($proc.ExitCode -ne 0) {
            throw "Failed to exclude path: $path (ExitCode: $($proc.ExitCode))"
        }
    }

    foreach ($procName in $exclusionProcesses) {
        $proc = Start-Process powershell.exe `
            -ArgumentList "-ExecutionPolicy", "Bypass", "-NonInteractive", "-Command", "Add-MpPreference -ExclusionProcess '$procName'" `
            -Wait -NoNewWindow -PassThru

        if ($proc.ExitCode -ne 0) {
            throw "Failed to exclude process: $procName (ExitCode: $($proc.ExitCode))"
        }
    }

    Log-Started-Finished "Finished: Setting defender exclusions finished"
}
catch {
    Log-Failure "Setting defender exclusions failed: $_"
}
Write-Host

# Enable notification icon
Log-Started-Finished "Started: Enabling notification icon"
try {
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "ShowNotificationIcon" -Value 1 -Force
} catch {
    Log-Failure "Enabling notification icon failed: $_"
}
Log-Started-Finished "Finished: Enabling notification icon finished"
Write-Host

# Enable location services
Log-Started-Finished "Started: Enabling location services"
try {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
    )
    foreach ($path in $regPaths) {
        if (-not (Test-Path $path)) {
            New-Item -Path (Split-Path $path) -Name (Split-Path $path -Leaf) -Force | Out-Null
        }
        Set-ItemProperty -Path $path -Name "Value" -Value "Allow" | Out-Null
    }
} catch {
    Log-Failure "Enabling location services failed: $_"
}
Log-Started-Finished "Finished: Enabling location services finished"
Write-Host

# Disable taskbar widgets
Log-Started-Finished "Started: Disabling taskbar widgets"
try {
    $path1 = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\NewsAndInterests"
    if (-not (Test-Path $path1)) { New-Item -Path $path1 -Force | Out-Null }
    Set-ItemProperty -Path $path1 -Name "value" -Value 0 | Out-Null

    $path2 = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    if (-not (Test-Path $path2)) { New-Item -Path $path2 -Force | Out-Null }
    Set-ItemProperty -Path $path2 -Name "AllowNewsAndInterests" -Value 0 | Out-Null
} catch {
    Log-Failure "Disabling taskbar widgets failed: $_"
}
Log-Started-Finished "Finished: Disabling taskbar widgets finished"
Write-Host

# Remove troubleshoot compatibility from context menu
Log-Started-Finished "Started: Removing troubleshoot compatibility from context menu"
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked"
$clsid   = "{1d27f844-3a1f-4410-85ac-14651078412d}"

try {
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    New-ItemProperty -Path $regPath -Name $clsid -Value "" -PropertyType String -Force | Out-Null
}
catch {
    Log-Failure "Removing troubleshoot compatibility from context menu failed"
}
Log-Started-Finished "Finished: Removing troubleshoot compatibility from context menu finished"
Write-Host

# Enable classic context menus
Log-Started-Finished "Started: Enabling classic context menus"
try {
    New-Item -Path "HKCU:\SOFTWARE\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Force | Out-Null
    New-Item -Path "HKCU:\SOFTWARE\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Force | Out-Null
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Name "(default)" -Value ""
} catch {
    Log-Failure "Enabling classic context menus failed: $_"
}
Log-Started-Finished "Finished: Enabling classic context menus finished"
Write-Host

# Enable dark mode
Log-Started-Finished "Started: Enabling dark mode"
try {
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0 -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0 -Force
} catch {
    Log-Failure "Enabling dark mode failed: $_"
}
Log-Started-Finished "Finished: Enabling dark mode finished"
Write-Host

# Add system icons to desktop
Log-Started-Finished "Started: Adding system icons to desktop"
try {
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
    $icons = @(
        "{20D04FE0-3AEA-1069-A2D8-08002B30309D}",  # This PC
        "{645FF040-5081-101B-9F08-00AA002F954E}",  # Recycle Bin
        "{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}",  # Control Panel
        "{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}",  # Network
        "{59031a47-3f72-44a7-89c5-5595fe6b30ee}"   # User Folder
    )
    foreach ($clsid in $icons) {
        Set-ItemProperty -Path $regPath -Name $clsid -Value 0 -Force
    }
    rundll32.exe user32.dll,UpdatePerUserSystemParameters
} catch {
    Log-Failure "Adding system icons to desktop failed: $_"
}
Log-Started-Finished "Finished: Adding system icons to desktop finished"
Write-Host

# Disable focus assist aka quiet hours
Log-Started-Finished "Started: Disabling focus assist aka quiet hours"
try {
    $focusPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\FocusAssist"
    if (-not (Test-Path $focusPath)) {
        New-Item -Path $focusPath -Force | Out-Null
    }
    Set-ItemProperty -Path $focusPath -Name "QuietHoursActive" -Value 0 -Force
    Set-ItemProperty -Path $focusPath -Name "QuietHoursEnabled" -Value 0 -Force
} catch {
    Log-Failure "Disabling focus assist aka quiet hours failed: $_"
}
Log-Started-Finished "Finished: Disabling focus assist aka quiet hours finished"
Write-Host

# Disable windows UI annoyances
Log-Started-Finished "Started: Disabling windows UI annoyances"
try {
    $regChanges = @(
        @{ Path="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"; Name="SearchBoxTaskbarMode"; Value=0 },
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="MMTaskbarEnabled"; Value=1 },
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="Start_TrackDocs"; Value=0 },
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="LaunchTo"; Value=1 },
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"; Name="ShowCloudFilesInQuickAccess"; Value=0 },
        @{ Path="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="ShowSyncProviderNotifications"; Value=0 },
        @{ Path="HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="ShowTaskViewButton"; Value=0 },
        @{ Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="SharingWizardOn"; Value=0 }
    )

    foreach ($entry in $regChanges) {
        $null = Set-ItemProperty -Path $entry.Path -Name $entry.Name -Value $entry.Value -Force
    }

    Log-Started-Finished "Finished: Disabling windows UI annoyances finished"
}
catch {
    Log-Failure "Disabling windows UI annoyances failed: $_"
}
Write-Host

# Disable quick access from file explorer home
Log-Started-Finished "Started: Disabling quick access from file explorer home"
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "HubMode" -Value 1 -Force
} catch {
    Log-Failure "Disabling quick access from file explorer home failed: $_"
}
Log-Started-Finished "Finished: Disabling quick access from file explorer home finished"
Write-Host

# Enable more details in file copy dialog
Log-Started-Finished "Started: Enabling more details in file copy dialog"
try {
    $enthusiastReg = "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager"
    $proc = Start-Process reg.exe `
        -ArgumentList "add `"$enthusiastReg`" /v EnthusiastMode /t REG_DWORD /d 1 /f" `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Setting EnthusiastMode failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Enabling more details in file copy dialog finished"
}
catch {
    Log-Failure "Enabling more details in file copy dialog failed: $_"
}
Write-Host

# Uninstall microsoft teams
Log-Started-Finished "Started: Uninstalling microsoft teams"
try {
    $teams = Get-AppxPackage -Name MicrosoftTeams
    if ($teams) { $teams | Remove-AppxPackage }
} catch {
    Log-Failure "Uninstalling microsoft teams failed: $_"
}
Log-Started-Finished "Finished: Uninstalling microsoft teams finished"
Write-Host

# Disable nvidia experience improvement program
Log-Started-Finished "Started: Disabling nvidia experience improvement program"
try {
    $nvidiaPath = "HKLM:\SOFTWARE\Policies\NVIDIA Corporation"
    if (-not (Test-Path $nvidiaPath)) {
        New-Item -Path $nvidiaPath -Force | Out-Null
    }
    Set-ItemProperty -Path $nvidiaPath -Name "ExperienceImprovementProgram" -Value 0 -Force
} catch {
    Log-Failure "Disabling nvidia experience improvement program failed: $_"
}
Log-Started-Finished "Finished: Disabling nvidia experience improvement program finished"
Write-Host

# Disable automatic installation of sponsored apps aka consumer experience
Log-Started-Finished "Started: Disabling automatic installation of sponsored apps aka consumer experience"
try {
    Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableWindowsConsumerFeatures" -Value 1 -Force
} catch {
    Log-Failure "Disabling automatic installation of sponsored apps aka consumer experience failed: $_"
}
Log-Started-Finished "Finished: Disabling automatic installation of sponsored apps aka consumer experience finished"
Write-Host

# Disable auto connect to suggested hotspots
Log-Started-Finished "Started: Disabling auto connect to suggested hotspots"
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" `
        -Name "AutoConnectAllowedOEM" -Value 0 -Force
} catch {
    Log-Failure "Disabling auto connect to suggested hotspots failed: $_"
}
Log-Started-Finished "Finished: Disabling auto connect to suggested hotspots finished"
Write-Host

# Disable auto install of suggested apps
Log-Started-Finished "Started: Disabling auto install of suggested apps"
try {
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "SilentInstalledAppsEnabled" -Value 0 -Force
} catch {
    Log-Failure "Disabling auto install of suggested apps failed: $_"
}
Log-Started-Finished "Finished: Disabling auto install of suggested apps finished"
Write-Host

# Disable cloud optimized content
Log-Started-Finished "Started: Disabling cloud optimized content"
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableCloudOptimizedContent" -Value 1 -Force
} catch {
    Log-Failure "Disabling cloud optimized content failed: $_"
}
Log-Started-Finished "Finished: Disabling cloud optimized content finished"
Write-Host

# Set feedback frequency to never
Log-Started-Finished "Started: Setting feedback frequency to never"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKCU\SOFTWARE\Microsoft\Siuf\Rules" /v "NumberOfSIUFInPeriod" /t REG_DWORD /d "0" /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Setting feedback frequency failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Setting feedback frequency to never finished"
}
catch {
    Log-Failure "Setting feedback frequency to never failed: $_"
}
Write-Host

# Disable jump list tracking
Log-Started-Finished "Started: Disabling jump list tracking"
try {
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "Start_TrackDocs" -Value 0 -Force
} catch {
    Log-Failure "Disabling jump list tracking failed: $_"
}
Log-Started-Finished "Finished: Disabling jump list tracking finished"
Write-Host

# Disable frequent folders in Quick Access
Log-Started-Finished "Started: Disabling frequent folders in Quick Access"
try {
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" `
        -Name "ShowFrequent" -Value 0 -Force
} catch {
    Log-Failure "Disabling frequent folders in Quick Access failed: $_"
}
Log-Started-Finished "Finished: Disabling frequent folders in Quick Access finished"
Write-Host

# Disable welcome screen suggestions
Log-Started-Finished "Started: Disabling welcome screen suggestions"
try {
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "EnableXamlStartMenu" -Value 0 -Force
} catch {
    Log-Failure "Disabling welcome screen suggestions failed: $_"
}
Log-Started-Finished "Finished: Disabling welcome screen suggestions finished"
Write-Host

# Disable tips and suggestions pane
Log-Started-Finished "Started: Disabling tips and suggestions pane"
try {
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" `
        -Name "SystemPaneSuggestionsEnabled" -Value 0 -Force
} catch {
    Log-Failure "Disabling tips and suggestions pane failed: $_"
}
Log-Started-Finished "Finished: Disabling tips and suggestions pane finished"
Write-Host

# Disable recent file tracking in quick access
Log-Started-Finished "Started: Disabling recent file tracking in quick access"
try {
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent" -Value 0 -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowRecent" -Value 0 -Force
} catch {
    Log-Failure "Disabling recent file tracking in quick access failed: $_"
}
Log-Started-Finished "Finished: Disabling recent file tracking in quick access finished"
Write-Host

# Disable typing insights
Log-Started-Finished "Started: Disabling typing insights"
try {
    $tiPath = "HKCU:\Software\Microsoft\Input\Settings"
    if (-not (Test-Path $tiPath)) {
        New-Item -Path $tiPath -Force | Out-Null
    }
    Set-ItemProperty -Path $tiPath -Name "InsightsEnabled" -Value 0 -Force
} catch {
    Log-Failure "Disabling Typing Insights failed: $_"
}
Log-Started-Finished "Finished: Disabling typing insights finished"
Write-Host

# Disable hotspot 2.0 online signup
Log-Started-Finished "Started: Disabling hotspot 2.0 online signup"
try {
    $osuPath = "HKLM:\SOFTWARE\Microsoft\WlanSvc\AnqpCache"
    if (-not (Test-Path $osuPath)) {
        New-Item -Path $osuPath -Force | Out-Null
    }
    Set-ItemProperty -Path $osuPath -Name "OsuRegistrationStatus" -Value 0 -Force
} catch {
    Log-Failure "Disabling hotspot 2.0 online signup failed: $_"
}
Log-Started-Finished "Finished: Disabling hotspot 2.0 online signup finished"
Write-Host

# Disable start menu recommendations
Log-Started-Finished "Started: Disabling start menu recommendations"
try {
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "Start_IrisRecommendations" -Value 0 -Force
} catch {
    Log-Failure "Disabling Start Menu recommendations failed: $_"
}
Log-Started-Finished "Finished: Disabling start menu recommendations finished"
Write-Host

# Disable fast user switching
Log-Started-Finished "Started: Disabling fast user switching"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v HideFastUserSwitching /t REG_DWORD /d 1 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Disabling fast user switching failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Disabling fast user switching finished"
}
catch {
    Log-Failure "Disabling fast user switching failed: $_"
}
Write-Host

# Disable first logon animation
Log-Started-Finished "Started: Disabling first logon animation"
try {
    $sysPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    if (-not (Test-Path $sysPath)) { New-Item -Path $sysPath -Force | Out-Null }
    Remove-ItemProperty -Path $sysPath -Name "EnableFirstLogonAnimation" -ErrorAction SilentlyContinue
    $wlPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    if (-not (Test-Path $wlPath)) { New-Item -Path $wlPath -Force | Out-Null }
    Set-ItemProperty -Path $wlPath -Name "EnableFirstLogonAnimation" -Value 0 -Force
} catch {
    Log-Failure "Disabling first logon animation failed: $_"
}
Log-Started-Finished "Finished: Disabling first logon animation finished"
Write-Host

# Disable reserved storage
Log-Started-Finished "Started: Disabling reserved storage"
try {
    Set-WindowsReservedStorageState -State Disabled | Out-Null
} catch {
    Log-Failure "Disabling Reserved Storage failed: $_"
}
Log-Started-Finished "Finished: Disabling reserved storage finished"
Write-Host

# Disable storage sense
Log-Started-Finished "Started: Disabling storage sense"
try {
    $regCommands = @(
        'add "HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense" /v "AllowStorageSenseGlobal" /t REG_DWORD /d 0 /f',
        'add "HKCU\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" /v "01" /t REG_DWORD /d 0 /f'
    )

    foreach ($cmd in $regCommands) {
        $proc = Start-Process reg.exe -ArgumentList $cmd -Wait -WindowStyle Hidden -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "Registry command failed: $cmd (ExitCode: $($proc.ExitCode))"
        }
    }

    Log-Started-Finished "Finished: Disabling storage sense finished"
}
catch {
    Log-Failure "Disabling storage sense failed: $_"
}
Write-Host

# Add control panel to file explorer
Log-Started-Finished "Started: Adding control panel to file explorer"
try {
    $regCommands = @(
        'add "HKCU\Software\Classes\CLSID\{26EE0668-A00A-44D7-9371-BEB064C98683}" /ve /t REG_SZ /d "Control Panel" /f',
        'add "HKCU\Software\Classes\CLSID\{26EE0668-A00A-44D7-9371-BEB064C98683}" /v "System.IsPinnedToNameSpaceTree" /t REG_DWORD /d 1 /f'
    )

    foreach ($cmd in $regCommands) {
        $proc = Start-Process reg.exe -ArgumentList $cmd -Wait -WindowStyle Hidden -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "Registry command failed: $cmd (ExitCode: $($proc.ExitCode))"
        }
    }

    Log-Started-Finished "Finished: Adding control panel to file explorer finished"
}
catch {
    Log-Failure "Adding control panel to file explorer failed: $_"
}
Write-Host

# Remove copy as path from context menu
Log-Started-Finished "Started: Removing copy as path from context menu"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'delete "HKLM\SOFTWARE\Classes\AllFilesystemObjects\shellex\ContextMenuHandlers\CopyAsPathMenu" /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Removing CopyAsPathMenu failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Removing copy as path from context menu finished"
}
catch {
    Log-Failure "Removing copy as path from context menu failed: $_"
}
Write-Host

# Allow auto ending of tasks for reboot
Log-Started-Finished "Started: Allowing auto ending of tasks for reboot"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKCU\Control Panel\Desktop" /v "AutoEndTasks" /t REG_SZ /d "1" /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Enabling AutoEndTasks failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Allowing auto ending of tasks for reboot finished"
}
catch {
    Log-Failure "Allowing auto ending of tasks for reboot failed: $_"
}
Write-Host

# Remove home from file explorer
Log-Started-Finished "Started: Removing home from file explorer"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}" /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Removing Home from File Explorer failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Removing home from file explorer finished"
}
catch {
    Log-Failure "Removing home from file explorer failed: $_"
}
Write-Host

# Remove gallery from file explorer
Log-Started-Finished "Started: Removing gallery from file explorer"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKCU\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}" /v System.IsPinnedToNameSpaceTree /t REG_DWORD /d 0 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Removing Gallery from File Explorer failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Removing gallery from file explorer finished"
}
catch {
    Log-Failure "Removing gallery from file explorer failed: $_"
}
Write-Host

# Dismiss popup
Log-Started-Finished "Started: Dismissing popup"
try {
    Start-Sleep -Seconds 5
    (New-Object -ComObject wscript.shell).SendKeys('{ESC}')
} catch {
    Log-Failure "Dismissing popup failed: $_"
}
Log-Started-Finished "Finished: Dismissing popup finished"
Write-Host

# Copy windhawk files
Log-Started-Finished "Started: Copying windhawk files"
try {
    $windhawkSrc = "Y:\computer\scripts\win11doafter\apps\windhawk"
    $windhawkDst = "C:\Program Files (x86)\windhawk"
    $ahkSrc = "Y:\computer\scripts\win11doafter\supportfiles\windhawkclose.ahk"
    $ahkDst = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\windhawkclose.ahk"

    if (-not (Test-Path $windhawkSrc)) {
        throw "Missing windhawk files at $windhawkSrc"
    }
    if (-not (Test-Path $ahkSrc)) {
        throw "Missing windhawk files ahk file at $ahkSrc"
    }

    Copy-Item -Path $windhawkSrc -Destination $windhawkDst -Recurse -Force
    Copy-Item -Path $ahkSrc -Destination $ahkDst -Force

    # Unhide hidden workspace files
    $paths = @(
        "$windhawkDst\appdata\editorworkspace\.vscode",
        "$windhawkDst\appdata\editorworkspace\.vscode\settings.json",
        "$windhawkDst\appdata\editorworkspace\.clang-format"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) {
            (Get-Item $path -Force).Attributes = `
                ((Get-Item $path -Force).Attributes -band -bnot [System.IO.FileAttributes]::Hidden)
        }
    }
} catch {
    Log-Failure "Copying windhawk files failed: $_"
}
Log-Started-Finished "Finished: Copying windhawk files finished"
Write-Host

# Turn off account notifications
Log-Started-Finished "Started: Turning off account notifications"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_AccountNotifications /t REG_DWORD /d 0 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Disabling account notifications in Start Menu failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Turning off account notifications finished"
}
catch {
    Log-Failure "Turning off account notifications failed: $_"
}
Write-Host

# Customize folders next to Start Menu power button
Log-Started-Finished "Started: Customizing folders next to Start Menu power button"
try {
    $regCommands = @(
        'delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Start" /v "VisiblePlaces" /f',
        'add "HKCU\Software\Microsoft\Windows\CurrentVersion\Start" /v "VisiblePlaces" /t REG_BINARY /d "86087352aa5143429f7b2776584659d4bc248a140cd68942a0806ed9bba24882448175fe0d08ae428bda34ed97b66394" /f'
    )

    foreach ($cmd in $regCommands) {
        $proc = Start-Process reg.exe -ArgumentList $cmd -Wait -WindowStyle Hidden -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "Registry command failed: $cmd (ExitCode: $($proc.ExitCode))"
        }
    }

    Log-Started-Finished "Finished: Customizing folders next to Start Menu power button finished"
}
catch {
    Log-Failure "Customizing folders next to Start Menu power button failed: $_"
}
Write-Host

# Microsoft edge tweaks
Log-Started-Finished "Started: Microsoft edge tweaks"
try {
    $regCommands = @(
        'add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v ShowHomeButton /t REG_DWORD /d 1 /f',
        'add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v HubsSidebarEnabled /t REG_DWORD /d 0 /f'
    )

    foreach ($cmd in $regCommands) {
        $proc = Start-Process reg.exe -ArgumentList $cmd -Wait -WindowStyle Hidden -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "Registry command failed: $cmd (ExitCode: $($proc.ExitCode))"
        }
    }

    Log-Started-Finished "Finished: Microsoft edge tweaks finished"
}
catch {
    Log-Failure "Microsoft edge tweaks failed: $_"
}
Write-Host

# Set screensaver config
Log-Started-Finished "Started: Setting screensaver config"
try {
    $scrPath = "HKCU:\Control Panel\Desktop"
    Set-ItemProperty -Path $scrPath -Name ScreenSaverIsSecure -Value 0 -Force
    Set-ItemProperty -Path $scrPath -Name ScreenSaveActive -Value 1 -Force
    Set-ItemProperty -Path $scrPath -Name ScreenSaveTimeOut -Value 300 -Force
    Set-ItemProperty -Path $scrPath -Name "SCRNSAVE.EXE" -Value "C:\Windows\System32\scrnsave.scr" -Force

    # Force GUI to re-read settings
    Start-Process "rundll32.exe" -ArgumentList "shell32.dll,Control_RunDLL desk.cpl,,1"

    # Optional: Trigger screensaver for testing
    # Start-Process "scrnsave.scr" -ArgumentList "/s"
} catch {
    Log-Failure "Setting screensaver config failed: $_"
}
Log-Started-Finished "Finished: Setting screensaver config finished"
Write-Host

# Import context menu registry tweaks
Log-Started-Finished "Started: Importing context menu registry tweaks"
try {
    $ctxFiles = @(
        "Add_Open_PowerShell_window_here_as_administrator_context_menu.reg",
        "Add_Open_command_window_here_as_administrator.reg"
    )

    foreach ($file in $ctxFiles) {
        $regFile = "Y:\computer\scripts\win11doafter\supportfiles\$file"

        if (-not (Test-Path $regFile)) {
            throw "Missing registry file $file at $regFile"
        }

        $proc = Start-Process -FilePath "reg.exe" `
            -ArgumentList "import `"$regFile`"" `
            -Wait -WindowStyle Hidden -PassThru

        if ($proc.ExitCode -ne 0) {
            throw "importing $file failed with exit code $($proc.ExitCode)"
        }
    }
} catch {
    Log-Failure "Importing context menu registry tweaks failed: $_"
}
Log-Started-Finished "Finished: Importing context menu registry tweaks finished"
Write-Host

# Set restart explorer to context menu
Log-Started-Finished "Started: Setting restart explorer to context menu"
try {
    Start-Process reg -ArgumentList 'add "HKCR\DesktopBackground\Shell\Restart Explorer" /v "icon" /t REG_SZ /d "explorer.exe" /f' -Wait -WindowStyle Hidden
    Start-Process reg -ArgumentList 'add "HKCR\DesktopBackground\Shell\Restart Explorer" /v "Position" /t REG_SZ /d "Bottom" /f' -Wait -WindowStyle Hidden
    Start-Process reg -ArgumentList 'add "HKCR\DesktopBackground\Shell\Restart Explorer\command" /ve /t REG_EXPAND_SZ /d "cmd.exe /c taskkill /f /im explorer.exe & start explorer.exe" /f' -Wait -WindowStyle Hidden
} catch {
    Log-Failure "Setting restart explorer to context menu failed: $_"
}
Log-Started-Finished "Finished: Setting restart explorer to context menu finished"
Write-Host

# Set restart start menu to context menu
Log-Started-Finished "Started: Setting restart start menu to context menu"
try {
    Start-Process reg -ArgumentList 'add "HKCR\DesktopBackground\Shell\RestartStart" /v "icon" /t REG_SZ /d "C:\Windows\System32\UNP\UNPUX.dll,-101" /f' -Wait -WindowStyle Hidden
    Start-Process reg -ArgumentList 'add "HKCR\DesktopBackground\Shell\RestartStart" /v "MUIVerb" /t REG_SZ /d "Restart Start menu" /f' -Wait -WindowStyle Hidden
    Start-Process reg -ArgumentList 'add "HKCR\DesktopBackground\Shell\RestartStart" /v "Position" /t REG_SZ /d "Bottom" /f' -Wait -WindowStyle Hidden
    Start-Process reg -ArgumentList 'add "HKCR\DesktopBackground\Shell\RestartStart\command" /ve /t REG_SZ /d "cmd /c taskkill /im StartMenuExperienceHost.exe /F /T" /f' -Wait -WindowStyle Hidden
} catch {
    Log-Failure "Setting restart start menu to context menu failed: $_"
}
Log-Started-Finished "Finished: Setting restart start menu to context menu finished"
Write-Host

# Turn off defender account notifications
Log-Started-Finished "Started: Turning off defender account notifications"
try {
    $accountNotif = "HKCU:\Software\Microsoft\Windows Defender Security Center\Account protection"
    if (-not (Test-Path $accountNotif)) {
        New-Item -Path $accountNotif -Force | Out-Null
    }
    Set-ItemProperty -Path $accountNotif -Name DisableNotifications -Value 1 -Force
    Set-ItemProperty -Path $accountNotif -Name DisableWindowsHelloNotifications -Value 1 -Force
    Set-ItemProperty -Path $accountNotif -Name DisableDynamiclockNotifications -Value 1 -Force
} catch {
    Log-Failure "Turning off defender account notifications failed: $_"
}
Log-Started-Finished "Finished: Turning off defender account notifications finished"
Write-Host

# Turn on show seconds in taskbar clock
Log-Started-Finished "Started: Turning on show seconds in taskbar clock"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowSecondsInSystemClock /t REG_DWORD /d 1 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Enabling taskbar seconds display failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Turning on show seconds in taskbar clock finished"
}
catch {
    Log-Failure "Turning on show seconds in taskbar clock failed: $_"
}
Write-Host

# Turn off startup sound
Log-Started-Finished "Started: Turning off startup sound"
try {
    Start-Process reg -ArgumentList 'add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" /v DisableStartupSound /t REG_DWORD /d 1 /f' -Wait -WindowStyle Hidden
    Start-Process reg -ArgumentList 'add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\EditionOverrides" /v UserSetting_DisableStartupSound /t REG_DWORD /d 1 /f' -Wait -WindowStyle Hidden
} catch {
    Log-Failure "Turning off startup sound failed: $_"
}
Log-Started-Finished "Finished: Turning off startup sound finished"
Write-Host

# Context menu removals
Log-Started-Finished "Started: Context menu removals"
$ctxChanges = @(
    # Windows UI & Explorer tweaks
    @{ Description = "Remove 'Open in Windows Terminal'"; Command = 'add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" /v "{9F156763-7844-4DC4-B2B1-901F640F5155}" /t REG_SZ /d "" /f' },
    @{ Description = "Remove Share option"; Command = 'add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" /v "{e2bf9676-5f8f-435c-97eb-11607a5bedf7}" /t REG_SZ /d "Modern Sharing" /f' },
    @{ Description = "Remove Add to Home"; Command = 'delete "HKCR\*\shell\pintohomefile" /f' },
    @{ Description = "Remove Office.com Quick Access"; Command = 'add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer" /v ShowCloudFilesInQuickAccess /t REG_DWORD /d 0 /f' },
    @{ Description = "Remove Troubleshoot Compatibility"; Command = 'add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" /v "{1d27f844-3a1f-4410-85ac-14651078412d}" /t REG_SZ /d "" /f' },

    # Offline Files
    @{ Description = "Remove 'Always available offline' (AllFilesystemObjects)"; Command = 'delete "HKCR\AllFilesystemObjects\shellex\ContextMenuHandlers\{474C98EE-CF3D-41f5-80E3-4AAB0AB04301}" /f' },
    @{ Description = "Remove 'Always available offline' (Folder context)"; Command = 'delete "HKCR\Folder\shellex\ContextMenuHandlers\Offline Files" /f' },
    @{ Description = "Remove 'Always available offline' (Directory context)"; Command = 'delete "HKCR\Directory\shellex\ContextMenuHandlers\Offline Files" /f' },

    # Print & PrintTo removal
    @{ Description = "Remove 'Print' from .txt"; Check = 'HKCR\txtfile\shell\print' },
    @{ Description = "Remove 'PrintTo' from .txt"; Check = 'HKCR\txtfile\shell\printto' },
    @{ Description = "Remove 'Print' from .pdf"; Check = 'HKCR\AcroExch.Document.DC\shell\print' },
    @{ Description = "Remove 'PrintTo' from .pdf"; Check = 'HKCR\AcroExch.Document.DC\shell\printto' },
    @{ Description = "Remove 'Print' from .bat"; Check = 'HKCR\batfile\shell\print' },
    @{ Description = "Remove 'PrintTo' from .bat"; Check = 'HKCR\batfile\shell\printto' },
    @{ Description = "Remove 'Print' from .cmd"; Check = 'HKCR\cmdfile\shell\print' },
    @{ Description = "Remove 'PrintTo' from .cmd"; Check = 'HKCR\cmdfile\shell\printto' },
    @{ Description = "Remove 'Print' from .ps1"; Check = 'HKCR\Microsoft.PowerShellScript.1\shell\print' },
    @{ Description = "Remove 'PrintTo' from .ps1"; Check = 'HKCR\Microsoft.PowerShellScript.1\shell\printto' },
    @{ Description = "Remove 'Print' from .vbs"; Check = 'HKCR\VBSFile\shell\print' },
    @{ Description = "Remove 'PrintTo' from .vbs"; Check = 'HKCR\VBSFile\shell\printto' },
    @{ Description = "Remove 'Print' from .js"; Check = 'HKCR\JSFile\shell\print' },
    @{ Description = "Remove 'PrintTo' from .js"; Check = 'HKCR\JSFile\shell\printto' },
    @{ Description = "Remove 'Print' from .py"; Check = 'HKCR\Python.File\shell\print' },
    @{ Description = "Remove 'PrintTo' from .py"; Check = 'HKCR\Python.File\shell\printto' },
    @{ Description = "Remove 'Print' from .log"; Check = 'HKCR\logfile\shell\print' },
    @{ Description = "Remove 'PrintTo' from .log"; Check = 'HKCR\logfile\shell\printto' },
	@{ Description = "Remove 'Print' from .docx (LibreOffice)"; Check = 'HKCR\LibreOffice.Docx\shell\print' },
	@{ Description = "Remove 'PrintTo' from .docx (LibreOffice)"; Check = 'HKCR\LibreOffice.Docx\shell\printto' }
)

foreach ($change in $ctxChanges) {
    try {
        if ($change.Command) {
            $proc = Start-Process reg.exe -ArgumentList $change.Command -Wait -WindowStyle Hidden -PassThru
            if ($proc.ExitCode -ne 0) {
                throw "$($change.Description) failed with exit code $($proc.ExitCode)"
            }
        }
        elseif ($change.Check) {
            $regPath = "Registry::" + $change.Check
            if (Test-Path $regPath) {
                $deleteCmd = 'delete "' + $change.Check + '" /f'
                $proc = Start-Process reg.exe -ArgumentList $deleteCmd -Wait -WindowStyle Hidden -PassThru
                if ($proc.ExitCode -ne 0) {
                    throw "$($change.Description) failed with exit code $($proc.ExitCode)"
                }
            }
            else {
                # silently skip if key not found — no log
            }
        }
    }
    catch {
        Log-Failure "Context menu removals failed: $_"
    }
}
Log-Started-Finished "Finished: Context menu removals finished"
Write-Host

# Remove edit with notepad from context menu
Log-Started-Finished "Started: Removing edit with notepad from context menu"
# New context menu
try {
    $blockedKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked"
    $guid = "{CA6CC9F1-867A-481E-951E-A28C5E4F01EA}"

    if (-not (Test-Path $blockedKey)) {
        New-Item -Path $blockedKey -Force | Out-Null
    }

    New-ItemProperty -Path $blockedKey -Name $guid -Value "" -PropertyType String -Force | Out-Null
}
catch {
    Log-Failure "Failed to remove edit with notepad from context menu: $($_.Exception.Message)"
}

# Old context menu
$classicShellKeys = @(
    "HKCR:\*\shell",
    "HKCR:\*\shellex\ContextMenuHandlers"
)

foreach ($key in $classicShellKeys) {
    try {
        if (Test-Path $key) {
            Get-ChildItem $key -ErrorAction Stop | ForEach-Object {
                $subKey = $_
                $defaultValue = (Get-ItemProperty -Path $subKey.PSPath)."(default)"
                if ($subKey.Name -like "*notepad*" -or $defaultValue -like "*notepad*") {
                    Remove-Item -Path $subKey.PSPath -Recurse -Force
                }
            }
        }
    }
    catch {
        Log-Failure "Failed to remove edit with notepad from classic context menu: $key $($_.Exception.Message)"
    }
}
Log-Started-Finished "Finished: Removing edit with notepad from context menu finished"
Write-Host

# Disable core isolation
Log-Started-Finished "Started: Disabling core isolation"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Enabled /t REG_DWORD /d 0 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Disabling Memory Integrity (Core Isolation) failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Disabling core isolation finished"
}
catch {
    Log-Failure "Disabling core isolation failed: $_"
}
Write-Host

# Disable touch keyboard sounds
Log-Started-Finished "Started: Disabling touch keyboard sounds"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKCU\Software\Microsoft\TabletTip\1.7" /v EnableKeyAudioFeedback /t REG_DWORD /d 0 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Disabling touch keyboard sounds failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Disabling touch keyboard sounds finished"
}
catch {
    Log-Failure "Disabling touch keyboard sounds failed: $_"
}
Write-Host

# Microsoft edge policy tweaks
Log-Started-Finished "Started: Microsoft edge policy tweaks"
try {
    $regCommands = @(
        'add "HKLM\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main" /v "Use FormSuggest" /t REG_SZ /d no /f',
        'add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v WebWidgetAllowed /t REG_DWORD /d 0 /f'
    )

    foreach ($cmd in $regCommands) {
        $proc = Start-Process reg.exe -ArgumentList $cmd -Wait -WindowStyle Hidden -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "Registry command failed: $cmd (ExitCode: $($proc.ExitCode))"
        }
    }

    Log-Started-Finished "Finished: Microsoft edge policy tweaks finished"
}
catch {
    Log-Failure "Microsoft edge policy tweaks failed: $_"
}
Write-Host

# Disable microsoft store look for app suggestions
Log-Started-Finished "Started: Disabling microsoft store look for app suggestions"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v NoUseStoreOpenWith /t REG_DWORD /d 1 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Disabling Store open-with prompt failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Disabling microsoft store look for app suggestions finished"
}
catch {
    Log-Failure "Disabling microsoft store look for app suggestions failed: $_"
}
Write-Host

# Remove previous versions from context menu
Log-Started-Finished "Started: Removing previous versions from context menu"
try {
    $handlers = @(
        'HKCR\AllFilesystemObjects\shellex\PropertySheetHandlers\{596AB062-B4D2-4215-9F74-E9109B0A8153}',
        'HKCR\CLSID\{450D8FBA-AD25-11D0-98A8-0800361B1103}\shellex\PropertySheetHandlers\{596AB062-B4D2-4215-9F74-E9109B0A8153}',
        'HKCR\Directory\shellex\PropertySheetHandlers\{596AB062-B4D2-4215-9F74-E9109B0A8153}',
        'HKCR\Drive\shellex\PropertySheetHandlers\{596AB062-B4D2-4215-9F74-E9109B0A8153}',
        'HKCR\AllFilesystemObjects\shellex\ContextMenuHandlers\{596AB062-B4D2-4215-9F74-E9109B0A8153}',
        'HKCR\CLSID\{450D8FBA-AD25-11D0-98A8-0800361B1103}\shellex\ContextMenuHandlers\{596AB062-B4D2-4215-9F74-E9109B0A8153}',
        'HKCR\Directory\shellex\ContextMenuHandlers\{596AB062-B4D2-4215-9F74-E9109B0A8153}',
        'HKCR\Drive\shellex\ContextMenuHandlers\{596AB062-B4D2-4215-9F74-E9109B0A8153}'
    )
    foreach ($regkey in $handlers) {
        Start-Process reg -ArgumentList "delete `"$regkey`" /f" -Wait -WindowStyle Hidden
    }
} catch {
    Log-Failure "Removing previous versions from context menu failed: $_"
}
Log-Started-Finished "Finished: Removing previous versions from context menu finished"
Write-Host

# Install chocolatey
Log-Started-Finished "Started: Installing chocolatey"
try {
    Set-ExecutionPolicy Bypass -Scope Process -Force | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $tempScript = "$env:TEMP\install_choco.ps1"
    (New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1') | Set-Content -Path $tempScript -Encoding UTF8

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tempScript *> $null

    Remove-Item $tempScript -Force -ErrorAction SilentlyContinue

    Log-Started-Finished "Finished: Installing chocolatey finished"
}
catch {
    Log-Failure "Installing Chocolatey failed: $($_.Exception.Message)"
}
Write-Host

# Install apps with chocolatey
Log-Started-Finished "Started: Installing apps with chocolatey"
$ErrorActionPreference = 'SilentlyContinue'

# Ensure chocolatey is installed
$choco = "C:\ProgramData\chocolatey\bin\choco.exe"
if (-not (Test-Path $choco)) {
    Log-Failure "Chocolatey not found at $choco. Skipping installations."
    return
}

# Update chocolatey and clear stale metadata
Log-Install-Apps "Updating chocolatey and clearing stale metadata"
& $choco upgrade chocolatey -y --force *> $null
& $choco source update -n chocolatey *> $null
Remove-Item "$env:ChocolateyInstall\lib-bad" -Recurse -Force -ErrorAction SilentlyContinue *> $null
Log-Install-Apps "Updating chocolatey and clearing stale metadata finished"

$appInstalls = @(
    @{ Name = "AutoHotKey";        Args = "install autohotkey -y" },
    @{ Name = "Bluestacks";        Args = "install bluestacks -y" },
    @{ Name = "Firefox";           Args = "install firefox -y" },
    @{ Name = "LibreOffice";       Args = "install libreoffice-still -y" },
    @{ Name = "Microsoft Edge";    Args = "upgrade microsoft-edge -y" },
    @{ Name = "Notepad++";         Args = "install notepadplusplus -y" },
    @{ Name = "NTLite-Free";       Args = "install ntlite-free -y --ignore-checksum" },
    @{ Name = "Plex";              Args = "install plex -y" },
    @{ Name = "Putty";             Args = "install putty.install -y" },
#   @{ Name = "Sandboxie-Plus";    Args = "install sandboxie-plus -y" },
#   @{ Name = "Tailscale";         Args = "install tailscale -y" },
    @{ Name = "VLC";               Args = "install vlc -y" },
    @{ Name = "WinNUT-Client";     Args = "install winnut-client -y" },
    @{ Name = "WinRAR";            Args = "install winrar -y" },
    @{ Name = "WinSCP";            Args = "install winscp -y" }
)

foreach ($app in $appInstalls) {
    Log-Install-Apps "Installing $($app.Name)"

    try {
        # Build arguments string and invoke directly
        $argsArray = $app.Args.Split(' ')
        & $choco @argsArray *> $null
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
			"$($app.Name) failed with exit code $exitCode" | Out-File -FilePath "C:\Users\Public\Desktop\SUCCESS_LOG.txt" -Append
            Log-Failure "$($app.Name) failed with exit code $exitCode"
        } else {
            Log-Install-Apps "Installed $($app.Name) successfully"
        }

    } catch {
		"$($app.Name) failed with exit code $exitCode" | Out-File -FilePath "C:\Users\Public\Desktop\SUCCESS_LOG.txt" -Append
        Log-Failure "Exception while installing $($app.Name): $_"
    }

    Start-Sleep -Seconds 2
}
Log-Started-Finished "Finished: Installing apps with chocolatey finished"
Write-Host

# Install vcredist x86 and x64
Log-Started-Finished "Started: Installing vcredist x86 and x64"
try {
    function Install-VCRedist {
        param (
            [string]$installerPath,
            [string]$description
        )

        if (-not (Test-Path $installerPath)) {
            throw "Missing vcredist install file at $installerPath"
        }

        $proc = Start-Process -FilePath $installerPath `
            -ArgumentList "/install", "/quiet", "/norestart" `
            -Wait -WindowStyle Hidden -PassThru

        if ($proc.ExitCode -ne 0) {
            throw "Installing $description failed with exit code $($proc.ExitCode)"
        }
    }

    Install-VCRedist -installerPath "Y:\computer\scripts\win11doafter\apps\vcredist_x64.exe" -description "vcredist x64"
    Install-VCRedist -installerPath "Y:\computer\scripts\win11doafter\apps\vcredist_x86.exe" -description "vcredist x86"

} catch {
    Log-Failure "Installing vcredist x86 and x64 failed: $_"
}
Log-Started-Finished "Finished: Installing vcredist x86 and x64 finished"
Write-Host

# Import winnut client settings
Log-Started-Finished "Started: Importing winnut client settings"
try {
    $regPath = "Y:\computer\scripts\win11doafter\supportfiles\winnut.reg"

    if (-not (Test-Path $regPath)) {
        throw "Missing winnut client settings file at $regPath"
    }

    $proc = Start-Process -FilePath "reg.exe" `
        -ArgumentList "import `"$regPath`"" `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Importing winnut client settings failed with exit code $($proc.ExitCode)"
    }
} catch {
    Log-Failure "Importing winnut client settings failed: $_"
}
Log-Started-Finished "Finished: Importing winnut client settings finished"
Write-Host

# Install samsung magician
Log-Started-Finished "Started: Installing samsung magician"
try {
    $ProgressPreference = 'SilentlyContinue'
    $url = "https://semiconductor.samsung.com/consumer-storage/support/tools/"
    $headers = @{ "User-Agent" = "Mozilla/5.0" }
    $ahkScriptPath = "Y:\computer\scripts\win11doafter\autohotkeys\samsung_magician.ahk"
    $ahkExe = "C:\Program Files\AutoHotkey\AutoHotkey.exe"
    $html = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -ErrorAction Stop
    $pattern = 'https://download\.semiconductor\.samsung\.com/resources/software-resources/Samsung_Magician_Installer_Official_[\d\.]+\.exe'
    $match = [regex]::Match($html.Content, $pattern)

    if (-not $match.Success) {
        throw "Could not find samsung magician download link on the page."
    }

    $downloadUrl = $match.Value
    $fileName = [System.IO.Path]::GetFileName($downloadUrl)
    $outputPath = "C:\Users\Administrator\Desktop\$fileName"

    Invoke-WebRequest -Uri $downloadUrl -OutFile $outputPath -Headers $headers -ErrorAction Stop

    if (Test-Path -Path $outputPath) {
		Start-Process -FilePath $outputPath -WindowStyle Hidden | Out-Null
	} else {
		throw "Missing rustdesk file at $outputPath"
	}
	
	if (-not (Test-Path $ahkScriptPath)) {
		throw "Missing autohotkey script file at $ahkScriptPath"
	}

	if (-not (Test-Path $ahkExe)) {
		throw "Missing autohotkey executable file at $ahkExe"
	}

	Start-Process -FilePath $ahkExe -ArgumentList "`"$ahkScriptPath`"" -WindowStyle Hidden -Wait | Out-Null
	
	Remove-Item -Path $outputPath -Force -ErrorAction SilentlyContinue
	
}
catch {
    Log-Failure = "Installing samsung magician failed: $($_.Exception.Message)"
}
Log-Started-Finished "Finished: Installing samsung magician finished"
Write-Host

# Stop samsung magician
Log-Started-Finished "Started: Stopping samsung magician"
try {
    Stop-Process -Name "samsungmagician" -Force
} catch {
    Log-Failure "Stopping samsung magician failed: $_"
}
Log-Started-Finished "Finished: Stopping samsung magician finished"
Write-Host

# Install rustdesk
Log-Started-Finished "Started: Installing rustdesk"
try {
    $ProgressPreference = 'SilentlyContinue'
    $latestReleaseUrl = "https://github.com/rustdesk/rustdesk/releases/latest"
    $response = Invoke-WebRequest -Uri $latestReleaseUrl -MaximumRedirection 0 -ErrorAction SilentlyContinue
    $redirectUrl = $response.Headers.Location

    if ($redirectUrl -match "/tag/([0-9\.]+)") {
        $version = $matches[1]
    } else {
        throw "Could not extract version number from redirect url: $redirectUrl"
    }

    $msiFileName = "rustdesk-$version-x86_64.msi"
    $downloadUrl = "https://github.com/rustdesk/rustdesk/releases/download/$version/$msiFileName"
    $outputPath = "c:\users\administrator\desktop\$msiFileName"

    Invoke-WebRequest -Uri $downloadUrl -OutFile $outputPath

    if (Test-Path -Path $outputPath) {
		Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$outputPath`" /quiet /norestart" -Wait -NoNewWindow
	} else {
		throw "Missing rustdesk file at $outputPath"
	}
	
	Remove-Item -Path $outputPath -Force -ErrorAction SilentlyContinue

}
catch {
    Log-Failure = "Installing rustdesk failed: $($_.Exception.Message)"
}
Log-Started-Finished "Finished: Installing rustdesk finished"
Write-Host

# Install microsip
Log-Started-Finished "Started: Installing microsip"
try {
    $msPath = "Y:\computer\scripts\win11doafter\apps\microsip.exe"
    $ahkPath = "Y:\computer\scripts\win11doafter\autohotkeys\firewallwindow.ahk"

    if (-not (Test-Path $msPath)) {
        throw "Missing microsip install file at $msPath"
    }
    if (-not (Test-Path $ahkPath)) {
        throw "Missing microsip firewall ahk file at $ahkPath"
    }

    Start-Process -FilePath $msPath -ArgumentList "/S"
    Start-Sleep -Seconds 10

    Stop-Process -Name "microsip" -Force
    Start-Sleep -Seconds 5

    Start-Process -FilePath $ahkPath
} catch {
    Log-Failure "Installing or stopping microsip failed: $_"
}
Log-Started-Finished "Finished: Installing microsip finished"
Write-Host

# Install openvpn
Log-Started-Finished "Started: Installing openvpn"
try {
    $ovpnPath = "Y:\computer\scripts\win11doafter\apps\openvpn-install-2.4.8-I602-Win10.exe"

    if (-not (Test-Path $ovpnPath)) {
        throw "Missing openvpn install file at $ovpnPath"
    }

    Start-Process -FilePath $ovpnPath -ArgumentList "/S" -Wait
    Start-Sleep -Seconds 5
} catch {
    Log-Failure "Installing openvpn failed: $_"
}
Log-Started-Finished "Finished: Installing openvpn finished"
Write-Host

# Copy winrar license and config
Log-Started-Finished "Started: Copying winrar license and config"
try {
    $keySrc = "Y:\computer\scripts\win11doafter\apps\winrar\rarreg.key"
    $iniSrc = "Y:\computer\scripts\win11doafter\apps\winrar\WinRAR.ini"
    $keyDst = "C:\Program Files\WinRAR\rarreg.key"
    $iniDst = "C:\Program Files\WinRAR\WinRAR.ini"

    if (-not (Test-Path $keySrc)) {
        throw "Missing rarreg.key file at $keySrc"
    }
    if (-not (Test-Path $iniSrc)) {
        throw "Missing WinRAR.ini file at $iniSrc"
    }

    Copy-Item -Path $keySrc -Destination $keyDst -Force
    Copy-Item -Path $iniSrc -Destination $iniDst -Force

} catch {
    Log-Failure "Copying winrar license and config failed: $_"
}
Log-Started-Finished "Finished: Copying winrar license and config finished"
Write-Host

# Import winscp sessions
Log-Started-Finished "Started: Importing winscp sessions"
try {
    $regFolder = "Y:\computer\scripts\win11doafter\winscpconnections"

    if (-not (Test-Path $regFolder)) {
        throw "Missing winscp sessions folder at $regFolder"
    }

    $winscpRegFiles = Get-ChildItem -Path $regFolder -Filter "*.reg"

    if ($winscpRegFiles.Count -eq 0) {
        throw "Missing winscp .reg files in $regFolder"
    }

    foreach ($file in $winscpRegFiles) {
        $proc = Start-Process -FilePath "reg.exe" `
            -ArgumentList "import `"$($file.FullName)`"" `
            -Wait -WindowStyle Hidden -PassThru

        if ($proc.ExitCode -ne 0) {
            throw "Importing winscp session from $($file.Name) failed with exit code $($proc.ExitCode)"
        }
    }

} catch {
    Log-Failure "Importing winscp sessions failed: $_"
}
Log-Started-Finished "Finished: Importing winscp sessions finished"
Write-Host

# Import putty sessions
Log-Started-Finished "Started: Importing putty sessions"
try {
    $regFolder = "Y:\computer\scripts\win11doafter\puttyconnections"

    if (-not (Test-Path $regFolder)) {
        throw "Missing putty sessions folder at $regFolder"
    }

    $puttyRegFiles = Get-ChildItem -Path $regFolder -Filter "*.reg"

    if ($puttyRegFiles.Count -eq 0) {
        throw "Missing putty .reg files in $regFolder"
    }

    foreach ($file in $puttyRegFiles) {
        $proc = Start-Process -FilePath "reg.exe" `
            -ArgumentList "import `"$($file.FullName)`"" `
            -Wait -WindowStyle Hidden -PassThru

        if ($proc.ExitCode -ne 0) {
            throw "Importing putty session from $($file.Name) failed with exit code $($proc.ExitCode)"
        }
    }

} catch {
    Log-Failure "Importing putty sessions failed: $_"
}
Log-Started-Finished "Finished: Importing putty sessions finished"
Write-Host

# Turn off xbox game bar and overlay
Log-Started-Finished "Started: Turning off xbox game bar and overlay"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" /v AppCaptureEnabled /t REG_DWORD /d 0 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Disabling gaming overlay failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Turning off xbox game bar and overlay finished"
}
catch {
    Log-Failure "Turning off xbox game bar and overlay failed: $_"
}
Write-Host

# Disable recently added apps in start
Log-Started-Finished "Started: Disabling recently added apps in start"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v HideRecentlyAddedApps /t REG_DWORD /d 1 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Hiding recently added apps failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Disabling recently added apps in start finished"
}
catch {
    Log-Failure "Disabling recently added apps in start failed: $_"
}
Write-Host

# Turn off notification sounds
Log-Started-Finished "Started: Turning off notification sounds"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" /v NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND /t REG_DWORD /d 0 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Disabling notification sounds failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Turning off notification sounds finished"
}
catch {
    Log-Failure "Turning off notification sounds failed: $_"
}
Write-Host

# Set file explorer folder view
Log-Started-Finished "Started: Setting file explorer folder view"
try {
    $regFiles = @(
        "HKCU_Software_Classes_LocalSettings_Software_Microsoft_Windows_Shell_BagMRU.reg",
        "HKCU_Software_Classes_LocalSettings_Software_Microsoft_Windows_Shell_Bags.reg",
        "HKCU_SOFTWARE_Microsoft_Windows_CurrentVersion_Explorer_Modules_NavPane.reg",
        "HKCU_Software_Microsoft_Windows_CurrentVersion_Explorer_Streams_Defaults.reg",
        "HKCU_Software_Microsoft_Windows_Shell_BagMRU.reg",
        "HKCU_Software_Microsoft_Windows_Shell_Bags.reg"
    )
    foreach ($file in $regFiles) {
        $regPath = "Y:\computer\scripts\win11doafter\foldersettings\$file"
        if (Test-Path $regPath) {
            Start-Process reg -ArgumentList @("import", $regPath) -Wait -WindowStyle Hidden
        } else {
            Log-Failure "Registry file not found: $regPath"
        }
    }
} catch {
    Log-Failure "Setting file explorer folder view failed: $_"
}
Log-Started-Finished "Finished: Setting file explorer folder view finished"
Write-Host

# Turn off show all folders in file explorer options
Log-Started-Finished "Started: Turning off show all folders in file explorer options"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v NavPaneShowAllFolders /t REG_DWORD /d 0 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Setting NavPaneShowAllFolders failed with exit code $($proc.ExitCode)"
    }

    Stop-Process -Name explorer -Force
    Start-Sleep -Seconds 5
    Start-Process explorer.exe
    Start-Sleep -Seconds 7

    & "Y:\computer\scripts\win11doafter\autohotkeys\close_file_explorer.exe" | Out-Null

    Log-Started-Finished "Finished: Turning off show all folders in file explorer options finished"
}
catch {
    Log-Failure "Turning off show all folders in file explorer options failed: $_"
}
Write-Host

# Disable xbox button and game mode
Log-Started-Finished "Started: Disabling xbox button and game mode"
try {
    $gameRegEntries = @(
        'add "HKCU\SOFTWARE\Microsoft\GameBar" /v UseNexusForGameBarEnabled /t REG_DWORD /d 0 /f',
        'add "HKCU\SOFTWARE\Microsoft\GameBar" /v AutoGameModeEnabled /t REG_DWORD /d 0 /f',
        'add "HKLM\SYSTEM\CurrentControlSet\Services\xbgm" /v Start /t REG_DWORD /d 4 /f'
    )

    foreach ($entry in $gameRegEntries) {
        $proc = Start-Process reg.exe -ArgumentList $entry -Wait -WindowStyle Hidden -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "Applying Xbox/GameBar tweak failed for: $entry (ExitCode: $($proc.ExitCode))"
        }
    }

    Log-Started-Finished "Finished: Disabling xbox button and game mode finished"
}
catch {
    Log-Failure "Disabling xbox button and game mode failed: $_"
}
Write-Host

# Enable shutdown without login
Log-Started-Finished "Started: Enabling shutdown without login"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v shutdownwithoutlogon /t REG_DWORD /d 1 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Allowing shutdown without logon failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Enabling shutdown without login finished"
}
catch {
    Log-Failure "Enabling shutdown without login failed: $_"
}
Write-Host

# Remove - shortcut when creating shortcuts
Log-Started-Finished "Started: Removing - shortcut when creating shortcuts"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer" /v "link" /t REG_BINARY /d 00000000 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Removing '- Shortcut' label failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Removing - shortcut when creating shortcuts finished"
}
catch {
    Log-Failure "Removing - shortcut when creating shortcuts failed: $_"
}
Write-Host

# Set combine taskbar buttons to never
Log-Started-Finished "Started: Setting combine taskbar buttons to never"
try {
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "TaskbarGlomLevel" -Value 2
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "MMTaskbarGlomLevel" -Value 2
} catch {
    Log-Failure "Setting combine taskbar buttons to never failed: $_"
}
Log-Started-Finished "Finished: Setting combine taskbar buttons to never finished"
Write-Host

# Disable lock screen
Log-Started-Finished "Started: Disabling lock screen"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization" /v NoLockScreen /t REG_DWORD /d 1 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Disabling lock screen failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Disabling lock screen finished"
}
catch {
    Log-Failure "Disabling lock screen failed: $_"
}
Write-Host

# Enable touch keyboard to taskbar
Log-Started-Finished "Started: Enabling touch keyboard to taskbar"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKCU\SOFTWARE\Microsoft\TabletTip\1.7" /v TipbandDesiredVisibility /t REG_DWORD /d 1 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Enabling touch keyboard toggle failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Enabling touch keyboard to taskbar finished"
}
catch {
    Log-Failure "Enabling touch keyboard to taskbar failed: $_"
}
Write-Host

# Disable most used apps from taskbar
Log-Started-Finished "Started: Disabling most used apps from taskbar"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoStartMenuMFUprogramsList /t REG_DWORD /d 1 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Disabling Most Used apps list failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Disabling most used apps from taskbar finished"
}
catch {
    Log-Failure "Disabling most used apps from taskbar failed: $_"
}
Write-Host

# Replace command prompt with windows terminal when right clicking start menu
Log-Started-Finished "Started: Replacing command prompt with windows terminal when right clicking start menu"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v DontUsePowerShellOnWinX /t REG_DWORD /d 0 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Re-enabling windows terminal with win+x failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Replacing command prompt with windows terminal when right clicking start menu finished"
}
catch {
    Log-Failure "Replacing command prompt with windows terminal when right clicking start menu failed: $_"
}
Write-Host

# Set control panel view to classic
Log-Started-Finished "Started: Setting control panel view to classic"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v ForceClassicControlPanel /t REG_DWORD /d 1 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Forcing Classic Control Panel view failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Setting control panel view to classic finished"
}
catch {
    Log-Failure "Setting control panel view to classic failed: $_"
}
Write-Host

# Disable UAC
Log-Started-Finished "Started: Disabling UAC"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA /t REG_DWORD /d 0 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Disabling UAC failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Disabling UAC finished"
}
catch {
    Log-Failure "Disabling UAC failed: $_"
}
Write-Host

# Enable file transfer details and explorer visuals
Log-Started-Finished "Started: Enabling file transfer details and explorer visuals"
try {
    $regCommands = @(
        'add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" /v EnthusiastMode /t REG_DWORD /d 1 /f',
        'add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v AlwaysShowMenus /t REG_DWORD /d 1 /f'
    )

    foreach ($cmd in $regCommands) {
        $proc = Start-Process reg.exe -ArgumentList $cmd -Wait -WindowStyle Hidden -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "Registry command failed: $cmd (ExitCode: $($proc.ExitCode))"
        }
    }

    Log-Started-Finished "Finished: Enabling file transfer details and explorer visuals finished"
}
catch {
    Log-Failure "Enabling file transfer details and explorer visuals failed: $_"
}
Write-Host

# Set desktop background to black
Log-Started-Finished "Started: Setting desktop background to black"
try {
    Start-Process reg -ArgumentList 'add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers" /v BackgroundType /t REG_DWORD /d 1 /f' -Wait -WindowStyle Hidden
    Start-Process reg -ArgumentList 'add "HKCU\Control Panel\Desktop" /v WallPaper /t REG_SZ /d "" /f' -Wait -WindowStyle Hidden
    Start-Process reg -ArgumentList 'add "HKCU\Control Panel\Colors" /v Background /t REG_SZ /d "0 0 0" /f' -Wait -WindowStyle Hidden
} catch {
    Log-Failure "Setting desktop background to black failed: $_"
}
Log-Started-Finished "Finished: Setting desktop background to black finished"
Write-Host

# Disable Windows troubleshooting
Log-Started-Finished "Started: Disabling Windows troubleshooting"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting" /v Disabled /t REG_DWORD /d 1 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Disabling Windows Troubleshooting failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Disabling Windows troubleshooting finished"
}
catch {
    Log-Failure "Disabling Windows troubleshooting failed: $_"
}
Write-Host

# Turn clipboard history on
Log-Started-Finished "Started: Turning clipboard history on"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKCU\Software\Microsoft\Clipboard" /v EnableClipboardHistory /t REG_DWORD /d 1 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Enabling Clipboard History failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Turning clipboard history on finished"
}
catch {
    Log-Failure "Turning clipboard history on failed: $_"
}
Write-Host

# Disable safe search
Log-Started-Finished "Started: Disabling safe search"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" /v SafeSearchMode /t REG_DWORD /d 0 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Disabling SafeSearch failed with exit code $($proc.ExitCode)"
    }

    Log-Started-Finished "Finished: Disabling safe search finished"
}
catch {
    Log-Failure "Disabling safe search failed: $_"
}
Write-Host

# Enable auto arrange for desktop
Log-Started-Finished "Started: Enabling auto arrange for desktop"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKCU\SOFTWARE\Microsoft\Windows\Shell\Bags\1\Desktop" /v FFLAGS /t REG_DWORD /d 1075839525 /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Enabling auto-arrange on desktop failed with exit code $($proc.ExitCode)"
    }

    Stop-Process -Name explorer -Force
    Start-Sleep -Seconds 5
    Start-Process explorer.exe
    Start-Sleep -Seconds 7

    & "Y:\computer\scripts\win11doafter\autohotkeys\close_file_explorer.exe" | Out-Null

    Log-Started-Finished "Finished: Enabling auto arrange for desktop finished"
}
catch {
    Log-Failure "Enabling auto arrange for desktop failed: $_"
}
Write-Host

# Disable all system sounds
Log-Started-Finished "Started: Disabling all system sounds"
try {
    Start-Process reg -ArgumentList 'add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" /v DisableStartupSound /t REG_DWORD /d 1 /f' -Wait -WindowStyle Hidden
    Start-Process reg -ArgumentList 'add "HKCU\AppEvents\Schemes" /ve /d ".None" /f' -Wait -WindowStyle Hidden

    $soundKeys = @(
        ".Default", "CriticalBatteryAlarm", "DeviceConnect", "DeviceDisconnect", "DeviceFail", "FaxBeep",
        "LowBatteryAlarm", "MailBeep", "MessageNudge", "Notification.Default", "Notification.IM",
        "Notification.Mail", "Notification.Proximity", "Notification.REMinder", "Notification.SMS",
        "ProximityConnection", "SystemAsterisk", "SystemExclamation", "SystemHand", "SystemNotification",
        "WindowsUAC", "sapisvr\\DisNumbersSound", "sapisvr\\HubOffSound", "sapisvr\\HubOnSound",
        "sapisvr\\HubSleepSound", "sapisvr\\MisrecoSound", "sapisvr\\PanelSound"
    )
    foreach ($key in $soundKeys) {
        Start-Process reg -ArgumentList "delete `"HKCU\AppEvents\Schemes\Apps\.Default\$key\.Current`" /ve /f" -Wait -WindowStyle Hidden
    }
} catch {
    Log-Failure "Disabling all system sounds failed: $_"
}
Log-Started-Finished "Finished: Disabling all system sounds finished"
Write-Host

# Change drive labels
Log-Started-Finished "Started: Changing drive labels"
try {
    $labelScripts = @(
        @{ Path = 'Y:\computer\scripts\win11doafter\changedrivelabels\changeosdrivelabel.vbs'; Description = 'OS drive label' },
		@{ Path = 'Y:\computer\scripts\win11doafter\changedrivelabels\changedeploymentsharedrivelabel.vbs'; Description = 'deployment_share drive label' },
        @{ Path = 'Y:\computer\scripts\win11doafter\changedrivelabels\changeflashdrivelabel.vbs'; Description = 'Unraid flash drive label' },
		@{ Path = 'Y:\computer\scripts\win11doafter\changedrivelabels\changeunraidcache_onlydrivelabel.vbs'; Description = 'Unraid unraidcache_only drive label' },
        @{ Path = 'Y:\computer\scripts\win11doafter\changedrivelabels\changedatadrivelabel.vbs'; Description = 'Unraid data drive label' },
		@{ Path = 'Y:\computer\scripts\win11doafter\changedrivelabels\changemymediadrivelabel.vbs'; Description = 'Unraid mymedia drive label' }
    )

    foreach ($script in $labelScripts) {
        $proc = Start-Process cscript.exe `
            -ArgumentList "`"$($script.Path)`"" `
            -Wait -WindowStyle Hidden -PassThru

        if ($proc.ExitCode -ne 0) {
            throw "Changing $($script.Description) failed with exit code $($proc.ExitCode)"
        }
    }

    Log-Started-Finished "Finished: Changing drive labels finished"
}
catch {
    Log-Failure "Changing drive labels failed: $_"
}
Write-Host

# Set quick access pins/unpins
Log-Started-Finished "Started: Setting quick access pins/unpins"
try {
    $quickAccessChanges = @(
        @{ Action = "unpin"; Path = "C:\Users\Administrator\Documents" },
        @{ Action = "unpin"; Path = "C:\Users\Administrator\Downloads" },
        @{ Action = "unpin"; Path = "C:\Users\Administrator\Pictures" },
        @{ Action = "unpin"; Path = "C:\Users\Administrator\Music" },
        @{ Action = "unpin"; Path = "C:\Users\Administrator\Videos" },
        @{ Action = "pin";   Path = "C:\" },
		@{ Action = "pin";   Path = "V:\" },
        @{ Action = "pin";   Path = "W:\" },
        @{ Action = "pin";   Path = "X:\" },
        @{ Action = "pin";   Path = "Y:\" },
        @{ Action = "pin";   Path = "T:\" }
    )

    $quickAccessScript = "Y:\computer\scripts\win11doafter\supportfiles\Set-QuickAccess.ps1"
    if (-not (Test-Path $quickAccessScript)) {
        throw "Missing Set-QuickAccess.ps1 file at $quickAccessScript"
    }

    foreach ($entry in $quickAccessChanges) {
        $proc = Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-noprofile", "-executionpolicy", "bypass", "-file", "`"$quickAccessScript`"", "-action", $entry.Action, "-Path", $entry.Path `
            -Wait -WindowStyle Hidden -PassThru

        if ($proc.ExitCode -ne 0) {
            throw "$($entry.Action)ning $($entry.Path) to quick access failed with exit code $($proc.ExitCode)"
        }
    }
    # Pin recycle bin to quick access
    try {
        $rbPath = "HKCU:\Software\Classes\CLSID\{645FF040-5081-101B-9F08-00AA002F954E}\shell\pintohome\command"
        if (-not (Test-Path $rbPath)) {
            New-Item -Path $rbPath -Force | Out-Null
        }
        New-ItemProperty -Path $rbPath -Name "DelegateExecute" -Value "{b455f46e-e4af-4035-b0a4-cf18d2f6f28e}" -Force | Out-Null

        $shell = New-Object -ComObject Shell.Application
        $recycle = $shell.Namespace("shell:::{645FF040-5081-101B-9F08-00AA002F954E}")
        $recycle.Self.InvokeVerb("PinToHome")

        Remove-Item -Path "HKCU:\Software\Classes\CLSID\{645FF040-5081-101B-9F08-00AA002F954E}" -Recurse -Force
    } catch {
        throw "Setting recycle bin to quick access failed: $_"
    }

} catch {
    Log-Failure "Setting quick access pins/unpins failed: $_"
}
Log-Started-Finished "Finished: Setting quick access pins/unpins finished"
Write-Host

# Create file shares
Log-Started-Finished "Started: Creating file shares"
try {
    New-SmbShare -Name "os" -Path "C:\" -ReadAccess "Everyone" -FullAccess "Administrators" | Out-Null
} catch {
    Log-Failure "Sharing C drive failed: $_"
}
Log-Started-Finished "Finished: Creating file shares finished"
Write-Host

# Import scheduled task for closing apps
Log-Started-Finished "Started: Importing scheduled task for closing apps"
try {
    $taskXml = "Y:\computer\scripts\win11doafter\supportfiles\close apps task.xml"

    if (-not (Test-Path $taskXml)) {
        throw "Missing scheduled task for closing apps xml file at $taskXml"
    }

    $proc = Start-Process -FilePath "schtasks.exe" `
        -ArgumentList "/Create", "/XML", "`"$taskXml`"", "/TN", "`"close apps task`"", "/RU", "administrator", "/RP", "321" `
        -Wait -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Importing scheduled task for closing apps failed with exit code $($proc.ExitCode)"
    }
} catch {
    Log-Failure "Importing scheduled task for closing apps failed: $_"
}
Log-Started-Finished "Finished: Importing scheduled task for closing apps finished"
Write-Host

# Enable dark mode for apps
Log-Started-Finished "Started: Enabling dark mode for apps"
try {
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0 -Force
} catch {
    Log-Failure "Enabling dark mode for apps failed: $_"
}
Log-Started-Finished "Finished: Enabling dark mode for apps finished"
Write-Host

# Enable microsoft update for other products
Log-Started-Finished "Started: Enabling microsoft update for other products"
try {
    (New-Object -ComObject Microsoft.Update.ServiceManager).AddService2("7971f918-a847-4430-9279-4a52d1efe18d", 7, "") | Out-Null
} catch {
    Log-Failure "Enabling microsoft update for other products failed: $_"
}
Log-Started-Finished "Finished: Enabling microsoft update for other products finished"
Write-Host

# Enable more details for task manager
Log-Started-Finished "Started: Enabling more details for task manager"
$taskmgr = Start-Process -FilePath "taskmgr.exe" -PassThru
Start-Sleep -Seconds 2

$preferencesPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskManager"
if (Test-Path $preferencesPath) {
    $prefs = Get-ItemProperty -Path $preferencesPath -Name Preferences
    $prefs.Preferences[28] = 0
    Set-ItemProperty -Path $preferencesPath -Name Preferences -Value $prefs.Preferences
}
Stop-Process -name "taskmgr" -Force
Log-Started-Finished "Finished: Enabling more details for task manager finished"
Write-Host

# Disable wifi sense
Log-Started-Finished "Started: Disabling wifi sense"
try {
    $wifiPaths = @(
        "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting",
        "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots",
        "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config"
    )
    foreach ($path in $wifiPaths) {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    }
    Set-ItemProperty -Path $wifiPaths[0] -Name "Value" -Value 0 -Type DWord
    Set-ItemProperty -Path $wifiPaths[1] -Name "Value" -Value 0 -Type DWord
    Set-ItemProperty -Path $wifiPaths[2] -Name "AutoConnectAllowedOEM" -Value 0 -Type DWord
    Set-ItemProperty -Path $wifiPaths[2] -Name "WiFISenseAllowed" -Value 0 -Type DWord
} catch {
    Log-Failure "Disabling wifi sense failed: $_"
}
Log-Started-Finished "Finished: Disabling wifi sense finished"
Write-Host

# Disable automatic maps updates
Log-Started-Finished "Started: Disabling automatic maps updates"
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\Maps" -Name "AutoUpdateEnabled" -Value 0 -Type DWord
} catch {
    Log-Failure "Disabling automatic maps updates failed: $_"
}
Log-Started-Finished "Finished: Disabling automatic maps updates finished"
Write-Host

# Disable wap push service
Log-Started-Finished "Started: Disabling wap push service"
try {
    Stop-Service "dmwappushservice"
    Set-Service "dmwappushservice" -StartupType Disabled
} catch {
    Log-Failure "Disabling wap push service failed: $_"
}
Log-Started-Finished "Finished: Disabling wap push service finished"
Write-Host

# Disable internet connection sharing
Log-Started-Finished "Started: Disabling internet connection sharing"
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections" `
        -Name "NC_ShowSharedAccessUI" -Value 0 -Type DWord
} catch {
    Log-Failure "Disabling internet connection sharing failed: $_"
}
Log-Started-Finished "Finished: Disabling internet connection sharing finished"
Write-Host

# Disable remote assistance
Log-Started-Finished "Started: Disabling remote assistance"
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" `
        -Name "fAllowToGetHelp" -Value 0 -Type DWord
} catch {
    Log-Failure "Disabling remote assistance failed: $_"
}
Log-Started-Finished "Finished: Disabling remote assistance finished"
Write-Host

# Disable shared experiences
Log-Started-Finished "Started: Disabling shared experiences"
try {
    $cdpPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CDP"
    if (-not (Test-Path $cdpPath)) {
        New-Item -Path $cdpPath -Force | Out-Null
    }
    Set-ItemProperty -Path $cdpPath -Name "RomeSdkChannelUserAuthzPolicy" -Value 0 -Type DWord
} catch {
    Log-Failure "Disabling shared experiences failed: $_"
}
Log-Started-Finished "Finished: Disabling shared experiences finished"
Write-Host

# Enable numLock at startup
Log-Started-Finished "Started: Enabling numLock at startup"
try {
    if (-not (Get-PSDrive -Name "HKCU")) {
        New-PSDrive -Name "HKCU" -PSProvider Registry -Root HKEY_USERS | Out-Null
    }
    Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -Value 2147483650 -Type DWord
    Add-Type -AssemblyName System.Windows.Forms
    if (-not [System.Windows.Forms.Control]::IsKeyLocked('NumLock')) {
        (New-Object -ComObject WScript.Shell).SendKeys('{NUMLOCK}')
    }
} catch {
    Log-Failure "Enabling numLock at startup failed: $_"
}
Log-Started-Finished "Finished: Enabling numLock at startup finished"
Write-Host

# Disable application suggestions and automatic installation
Log-Started-Finished "Started: Disabling application suggestions and automatic installation"
try {
    # HKCU tweaks
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "ContentDeliveryAllowed" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "OemPreInstalledAppsEnabled" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "PreInstalledAppsEnabled" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "PreInstalledAppsEverEnabled" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SilentInstalledAppsEnabled" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-310093Enabled" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-314559Enabled" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338387Enabled" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338388Enabled" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338393Enabled" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-353694Enabled" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-353696Enabled" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-353698Enabled" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Type DWord -Value 0

    # HKLM policy tweaks
    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Type DWord -Value 1

    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace" -Name "AllowSuggestedAppsInWindowsInkWorkspace" -Type DWord -Value 0

    # Clear placeholder tile collection for supported builds
    if ([System.Environment]::OSVersion.Version.Build -ge 17134) {
        $key = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount\*windows.data.placeholdertilecollection\Current"
        Set-ItemProperty -Path $key.PSPath -Name "Data" -Type Binary -Value $key.Data[0..15]
    }

    Log-Started-Finished "Finished: Disabling application suggestions and automatic installation finished"
}
catch {
    Log-Failure "Disabling application suggestions and automatic installation failed: $($_.Exception.Message)"
}
Write-Host

# Install .net 3.5
Log-Started-Finished "Started: Installing .net 3.5"
try {
    $process = Start-Process -FilePath dism.exe `
        -ArgumentList "/online", "/Enable-Feature", "/FeatureName:NetFx3", "/All", "/norestart" `
        -Wait -PassThru -WindowStyle Hidden

    if ($process.ExitCode -eq 3010) {
        Log-Started-Finished "Finished: Installing .net 3.5 finished"
    } elseif ($process.ExitCode -eq 0) {
        Log-Started-Finished "Finished: Installing .net 3.5 finished"
    } else {
        throw "Installing .net 3.5 failed: (ExitCode: $($process.ExitCode))"
    }
}
catch {
    Log-Failure "Installing .net 3.5 failed: $($_.Exception.Message)"
}
Write-Host

# Copy tdarr to program files
Log-Started-Finished "Started: Copying tdarr to program files"
try {
    $source = "Y:\computer\tdarr"
    $destination = "C:\Program Files\Tdarr"

    if (-not (Test-Path $source)) {
        throw "Missing tdarr folder at $source"
    }

    # Create destination folder if it doesn't exist
    if (-not (Test-Path $destination)) {
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
    }

    # Copy folder contents recursively
    Copy-Item -Path "$source\*" -Destination $destination -Recurse -Force -ErrorAction Stop
} catch {
    Log-Failure "Copying tdarr to program files failed: $_"
}
Log-Started-Finished "Finished: Copying tdarr to program files finished"
Write-Host

# Create desktop shortcuts
Log-Started-Finished "Started: Creating desktop shortcuts"
try {
    $shortcutScriptPath = "Y:\computer\scripts\win11doafter\desktopshortcuts"

    if (-not (Test-Path $shortcutScriptPath)) {
        throw "Missing desktop shortcuts folder at $shortcutScriptPath"
    }

    $shortcuts = @(
    "windhawkdesktopshortcut.ps1",
    "notepadplusplusdesktopshortcut.ps1",
	"plexdesktopshortcut.ps1",
	"winrardesktopshortcut.ps1",
	"winnutdesktopshortcut.ps1",
	"tdarrdesktopshortcut.ps1",
	"puttydesktopshortcut.ps1"
    )

    foreach ($file in $shortcuts) {
        $scriptFile = Join-Path -Path $shortcutScriptPath -ChildPath $file

        if (-not (Test-Path $scriptFile)) {
            throw "Missing desktop shortcuts file $file"
        }

        $proc = Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-noprofile", "-executionpolicy", "bypass", "-file", "`"$scriptFile`"" `
            -Wait -WindowStyle Hidden -PassThru

        if ($proc.ExitCode -ne 0) {
            throw "Creating desktop shortcut from $file failed with exit code $($proc.ExitCode)"
        }
    }

} catch {
    Log-Failure "Creating desktop shortcuts failed: $_"
}
Log-Started-Finished "Finished: Creating desktop shortcuts finished"
Write-Host

# Uninstall onedrive
if (!$?) {
Log-Failure "Uninstalling onedrive failed"
	} else {
		Log-Started-Finished "Started: Uninstalling onedrive"
		taskkill /f /im OneDrive.exe > $null 2>&1
	try {
		Start-Process -FilePath "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" `
			-ArgumentList "/uninstall" -WindowStyle Hidden -Wait -ErrorAction Stop | Out-Null
	} catch {
		# Suppressed error intentionally
	}

    # Take Ownership and Grant Permissions
    $paths = @(
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
        "$env:SystemRoot\SysWOW64\OneDriveSettingSyncProvider.dll",
        "$env:SystemRoot\SysWOW64\OneDrive.ico"
    )

    foreach ($path in $paths) {
        if (Test-Path $path) {
            $acl = Get-Acl -Path $path
            $group = New-Object System.Security.Principal.NTAccount("$env:UserName")
            $acl.SetOwner($group)
            Set-Acl -Path $path -AclObject $acl

            $rule = New-Object system.security.accesscontrol.filesystemaccessrule("$env:UserName","FullControl","Allow")
            $acl.SetAccessRule($rule)
            Set-Acl -Path $path -AclObject $acl
        }
    }

    # LOCALAPPDATA\Microsoft\OneDrive permissions
    $localOneDrive = "$env:LOCALAPPDATA\Microsoft\OneDrive"
    if (Test-Path $localOneDrive) {
        $acl = Get-Acl $localOneDrive
        $rule = New-Object system.security.accesscontrol.filesystemaccessrule("$env:UserName","FullControl","Allow")
        $acl.SetAccessRule($rule)
        Set-Acl -Path $localOneDrive -AclObject $acl
    }

    # Registry Cleanup
    REG Delete "HKCR\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" /f > $null 2>&1
    REG Delete "HKCR\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" /f > $null 2>&1

    # Wait and restart shell
    Start-Sleep -Seconds 10
    Stop-Process -name "explorer" -Force
    Start-Sleep -Seconds 10

    # Remove known folders
    $foldersToRemove = @(
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
        "$env:SystemRoot\SysWOW64\OneDriveSettingSyncProvider.dll",
        "$env:SystemRoot\SysWOW64\OneDrive.ico",
        "$env:USERPROFILE\OneDrive",
        "$env:LOCALAPPDATA\Microsoft\OneDrive",
        "$env:ProgramData\Microsoft OneDrive",
        "C:\ProgramData\Microsoft OneDrive",
        "C:\OneDriveTemp"
    )

    foreach ($item in $foldersToRemove) {
        if (Test-Path $item) {
            Remove-Item -Path $item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Recursively remove any remaining files or folders containing 'onedrive' in the name
    try {
        $allMatches = Get-ChildItem -Path "C:\" -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "onedrive" }

        foreach ($item in $allMatches) {
            try {
                Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
            } catch {
                Log-Failure "Failed to remove: $($item.FullName)"
            }
        }
    } catch {
        Log-Failure "Error during full sweep removal: $_"
    }
	Log-Started-Finished "Finished: Uninstalling onedrive finished"
    Write-Host
}

# Remove onedrive from file explorer
Log-Started-Finished "Started: Removing onedrive from file explorer"
try {
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    Set-ItemProperty -Path $regPath -Name "HideOneDrive" -Value 1 -Type DWord

    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

} catch {
    Log-Failure "Removing onedrive from file explorer failed: $_"
}
Log-Started-Finished "Finished: Removing onedrive from file explorer"
Write-Host

# Remove preinstalled apps
Log-Started-Finished "Started: Removing preinstalled apps"
$appsToRemove = @(
    @{ Name = "3D Builder"; Package = "Microsoft.3DBuilder" },
    @{ Name = "App Connector"; Package = "Microsoft.AppConnector" },
    @{ Name = "Bing Finance"; Package = "Microsoft.BingFinance" },
    @{ Name = "Bing Food and Drink"; Package = "Microsoft.BingFoodAndDrink" },
    @{ Name = "Bing Health and Fitness"; Package = "Microsoft.BingHealthAndFitness" },
    @{ Name = "Bing Maps"; Package = "Microsoft.BingMaps" },
    @{ Name = "Bing News"; Package = "Microsoft.BingNews" },
    @{ Name = "Bing Sports"; Package = "Microsoft.BingSports" },
    @{ Name = "Bing Translator"; Package = "Microsoft.BingTranslator" },
    @{ Name = "Bing Travel"; Package = "Microsoft.BingTravel" },
    @{ Name = "Bing Weather"; Package = "Microsoft.BingWeather" },
    @{ Name = "Comms Phone"; Package = "Microsoft.CommsPhone" },
    @{ Name = "Connectivity Store"; Package = "Microsoft.ConnectivityStore" },
    @{ Name = "Fresh Paint"; Package = "Microsoft.FreshPaint" },
    @{ Name = "Get Help"; Package = "Microsoft.GetHelp" },
    @{ Name = "Get Started"; Package = "Microsoft.Getstarted" },
    @{ Name = "Help and Tips"; Package = "Microsoft.HelpAndTips" },
    @{ Name = "PlayReady Client"; Package = "Microsoft.Media.PlayReadyClient.2" },
    @{ Name = "Messaging"; Package = "Microsoft.Messaging" },
    @{ Name = "3D Viewer"; Package = "Microsoft.Microsoft3DViewer" },
    @{ Name = "Office Hub"; Package = "Microsoft.MicrosoftOfficeHub" },
    @{ Name = "Power BI for Windows"; Package = "Microsoft.MicrosoftPowerBIForWindows" },
    @{ Name = "Sticky Notes"; Package = "Microsoft.MicrosoftStickyNotes" },
    @{ Name = "Minecraft UWP"; Package = "Microsoft.MinecraftUWP" },
    @{ Name = "Mixed Reality Portal"; Package = "Microsoft.MixedReality.Portal" },
    @{ Name = "Camera"; Package = "Microsoft.MoCamera" },
    @{ Name = "Network Speed Test"; Package = "Microsoft.NetworkSpeedTest" },
    @{ Name = "Office Lens"; Package = "Microsoft.OfficeLens" },
    @{ Name = "OneNote"; Package = "Microsoft.Office.OneNote" },
    @{ Name = "Office Sway"; Package = "Microsoft.Office.Sway" },
    @{ Name = "OneConnect"; Package = "Microsoft.OneConnect" },
    @{ Name = "People"; Package = "Microsoft.People" },
    @{ Name = "Print 3D"; Package = "Microsoft.Print3D" },
    @{ Name = "Reader"; Package = "Microsoft.Reader" },
    @{ Name = "Skype App"; Package = "Microsoft.SkypeApp" },
    @{ Name = "To-Do"; Package = "Microsoft.Todos" },
    @{ Name = "Wallet"; Package = "Microsoft.Wallet" },
    @{ Name = "Web Media Extensions"; Package = "Microsoft.WebMediaExtensions" },
    @{ Name = "Whiteboard"; Package = "Microsoft.Whiteboard" },
    @{ Name = "Windows Communication Apps"; Package = "microsoft.windowscommunicationsapps" },
    @{ Name = "Windows Feedback Hub"; Package = "Microsoft.WindowsFeedbackHub" },
    @{ Name = "Windows Maps"; Package = "Microsoft.WindowsMaps" },
    @{ Name = "Windows Photos"; Package = "Microsoft.Windows.Photos" },
    @{ Name = "Windows Reading List"; Package = "Microsoft.WindowsReadingList" },
    @{ Name = "Windows Scan"; Package = "Microsoft.WindowsScan" },
    @{ Name = "Windows Sound Recorder"; Package = "Microsoft.WindowsSoundRecorder" },
    @{ Name = "WinJS 1.0"; Package = "Microsoft.WinJS.1.0" },
    @{ Name = "WinJS 2.0"; Package = "Microsoft.WinJS.2.0" },
    @{ Name = "Zune Music"; Package = "Microsoft.ZuneMusic" },
    @{ Name = "Zune Video"; Package = "Microsoft.ZuneVideo" },
    @{ Name = "Xbox App"; Package = "Microsoft.XboxApp" },
    @{ Name = "Xbox Gaming Overlay"; Package = "Microsoft.XboxGamingOverlay" },
    @{ Name = "Screen Sketch"; Package = "Microsoft.ScreenSketch" },
    @{ Name = "Advertising.Xaml"; Package = "Microsoft.Advertising.Xaml" },
    @{ Name = "Power Automate Desktop"; Package = "Microsoft.PowerAutomateDesktop" },
    @{ Name = "Clipchamp"; Package = "Clipchamp.Clipchamp" },
    @{ Name = "Quick Assist"; Package = "MicrosoftCorporationII.QuickAssist" },
    @{ Name = "Intel Graphics Experience"; Package = "AppUp.IntelGraphicsExperience" },
    @{ Name = "Solitaire Collection"; Package = "Microsoft.MicrosoftSolitaireCollection" },
    @{ Name = "Casual Games Hub"; Package = "Microsoft.CasualGames" },
    @{ Name = "Desktop Widget Tools"; Package = "LavitaApps.WidgetTools" }
)

function Log-Result {
    param (
        [string]$Name,
        [string]$Message,
        [string]$Type = "Info"
    )

    if ($Type -eq "Info") {
        Write-Host "$Name - $Message" -ForegroundColor Yellow
    }
}

foreach ($app in $appsToRemove) {
    try {
        $pkg = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*$($app.Package)*" }
        if ($pkg) {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers | Out-Null
            Log-Result -Name $app.Name -Message "Removed per-user package"
            continue
        }

        $provPkg = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*$($app.Package)*" }
        if ($provPkg) {
            Remove-AppxProvisionedPackage -Online -PackageName $provPkg.PackageName | Out-Null
            Log-Result -Name $app.Name -Message "Removed provisioned package"
            continue
        }

        Log-Result -Name $app.Name -Message "Not installed or already removed" -Type "Warning"
    } catch {
        Log-Result -Name $app.Name -Message "Failed to uninstall: $_" -Type "Error"
    }
}
# Remove copilot and outlook new
Log-Started-Finished "Started: Removing copilot and outlook new"
try {
    Get-AppxPackage | Where-Object {$_.Name -like 'Microsoft.Copilot'} | Remove-AppxPackage
    Get-AppxPackage | Where-Object {$_.Name -like '*OutlookForWindows*'} | Remove-AppxPackage
} catch {
    Log-Failure "Removing copilot and outlook new failed: $_"
}
Log-Started-Finished "Finished: Removing copilot and outlook new finished"
Write-Host
# Remove microsoft teams
Log-Started-Finished "Started: Removing microsoft teams"
try {
    Get-AppxPackage MicrosoftTeams* | Remove-AppxPackage
    Get-AppxPackage -Name "MSTeams" | Remove-AppxPackage
} catch {
    Log-Failure "Removing microsoft teams failed: $_"
}
Log-Started-Finished "Finished: Removing microsoft teams finished"
Write-Host
# Prevent outlook from reinstalling
Log-Started-Finished "Started: Preventing outlook from reinstalling"
try {
    $provisioned = Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like "*OutlookForWindows*" }
    if ($provisioned) {
        $provisioned | Remove-AppxProvisionedPackage -Online | Out-Null
    }
    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate" -Force
} catch {
    Log-Failure "Preventing outlook from reinstalling failed: $_"
}
Log-Started-Finished "Finished: Preventing outlook from reinstalling finished"
Write-Host
Log-Started-Finished "Finished: Removing preinstalled apps finished"
Write-Host

# Dismiss popup
Log-Started-Finished "Started: Dismissing popup"
try {
    Start-Sleep -Seconds 5
    (New-Object -ComObject wscript.shell).SendKeys('{ESC}')
} catch {
    Log-Failure "Dismissing popup failed: $_"
}
Log-Started-Finished "Finished: Dismissing popup finished"
Write-Host

# Install emby theater and dismiss driver/security prompts
Log-Started-Finished "Started: Installing emby theater and dismissing driver/security prompts"

try {
    # Define paths
    $embyExe = "Y:\computer\scripts\win11doafter\apps\emby.exe"
    $ahkSecurity = "Y:\computer\scripts\win11doafter\autohotkeys\embysecuritywarning.ahk"
    $ahkCEC = "Y:\computer\scripts\win11doafter\autohotkeys\embyhdmicecdriver.ahk"
    $ahkWindowsSec = "Y:\computer\scripts\win11doafter\autohotkeys\embywindowssecurity.ahk"

    # Ensure all required files exist
    foreach ($path in @($embyExe, $ahkSecurity, $ahkCEC, $ahkWindowsSec)) {
        if (-not (Test-Path $path)) {
            throw "Required file missing: $path"
        }
    }

    # Launch emby installer
    Start-Process -FilePath $embyExe | Out-Null
    Start-Sleep -Seconds 10

    # Create wscript.shell COM object for sendkeys
    $wshell = New-Object -ComObject WScript.Shell
    if (-not $wshell) { throw "Failed to create WScript.Shell COM object" }

    # Handle application run - security warning
    Start-Process -FilePath $ahkSecurity -WindowStyle Hidden | Out-Null
    $null = $wshell.AppActivate('Application Run - Security Warning')
    Start-Sleep -Seconds 5
    for ($i = 0; $i -lt 4; $i++) {
        $null = $wshell.SendKeys('{TAB}')
        Start-Sleep -Seconds 5
    }
    $null = $wshell.SendKeys(' ')
    Start-Sleep -Seconds 15

    # Handle HDMI CEC driver prompt
    Start-Process -FilePath $ahkCEC -WindowStyle Hidden | Out-Null
    $null = $wshell.AppActivate('HDMI CEC Driver')
    Start-Sleep -Seconds 5
    $null = $wshell.SendKeys(' ')
    Start-Sleep -Seconds 10

    # Handle windows security prompt
    Start-Process -FilePath $ahkWindowsSec -WindowStyle Hidden | Out-Null
    $null = $wshell.AppActivate('Windows Security')
    Start-Sleep -Seconds 5
    for ($i = 0; $i -lt 3; $i++) {
        $null = $wshell.SendKeys('{TAB}')
        Start-Sleep -Seconds 5
    }
    $null = $wshell.SendKeys(' ')
    Start-Sleep -Seconds 5

    # Clean up emby processes if they remain
    Stop-Process -Name "emby.theater" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    Stop-Process -Name "electron" -Force -ErrorAction SilentlyContinue

} catch {
    Log-Failure "Installing emby theater and dismissing prompts failed: $_"
}
Log-Started-Finished "Finished: Installing emby theater and dismissing prompts finished"
Write-Host

# Import microsoft edge registry settings
Log-Started-Finished "Started: Importing microsoft edge registry settings"
try {
    $edgeRegFile = "Y:\computer\scripts\win11doafter\supportfiles\edgeregistry.reg"

    if (-not (Test-Path $edgeRegFile)) {
        throw "edge registry file not found at $edgeRegFile"
    }

    $proc = Start-Process -FilePath "reg.exe" `
        -ArgumentList "import `"$edgeRegFile`"" `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Importing microsoft edge registry settings failed with exit code $($proc.ExitCode)"
    }

} catch {
    Log-Failure "Importing microsoft edge registry settings failed: $_"
}
Log-Started-Finished "Finished: Importing microsoft edge registry settings finished"
Write-Host

# Copy appdata
# Bluestacks
Log-Started-Finished "Started: Removing bluestacks shortcuts"
try {
	$exe = "C:\Program Files\BlueStacks_nxt\HD-Player.exe"
	
	if (-not (Test-Path $exe)) {
        throw "Missing bluestacks executable at $exe"
	}
	
    $bluestacksTargets = @(
        "C:\Users\Public\Desktop\BlueStacks 5.lnk",
        "C:\Users\Public\Desktop\BlueStacks X.lnk",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\BlueStacks X",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\BlueStacks 5.lnk"
    )

    foreach ($target in $bluestacksTargets) {
        if (Test-Path $target) {
            Remove-Item -Path $target -Recurse -Force -ErrorAction Stop
        }
    }

} catch {
    Log-Failure "Removing bluestacks shortcuts failed: $_"
}
Log-Started-Finished "Finished: Removing bluestacks shortcuts finished"
Write-Host

# Emby
Log-Started-Finished "Started: Copying emby appdata from backup"
try {
    $exe = "C:\Users\Administrator\AppData\Roaming\Emby-Theater\system\Emby.Theater.exe"
    $src = "Y:\computer\backups\vms appdata\emby backup"
    $dst = "C:\Users\Administrator\AppData\Roaming\Emby-Theater"

    if (-not (Test-Path $exe)) {
        throw "Missing emby executable at $exe"
    }
    if (-not (Test-Path $src)) {
        throw "Missing emby appdata backup folder at $src"
    }

    Start-Process -FilePath $exe
    Start-Sleep -Seconds 7

    Stop-Process -Name "Emby.Theater", "electron" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5

    Remove-Item -Path $dst -Recurse -Force
    Copy-Item -Path $src -Destination $dst -Recurse -Force

} catch {
    Log-Failure "Copying emby appdata failed: $_"
}
Log-Started-Finished "Finished: Copying emby appdata finished"
Write-Host

# Firefox
Log-Started-Finished "Started: Copying firefox appdata"
try {
    $exe = "C:\Program Files\Mozilla Firefox\firefox.exe"
    $src = "Y:\computer\backups\vms appdata\firefox backup"
    $dst = "C:\Users\Administrator\AppData\Roaming\Mozilla\Firefox"

    if (-not (Test-Path $exe)) {
        throw "Missing firefox executable at $exe"
    }
    if (-not (Test-Path $src)) {
        throw "Missing firefox appdata backup folder at $src"
    }

    Start-Process -FilePath $exe
    Start-Sleep -Seconds 7

    Stop-Process -Name "firefox" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5

    Remove-Item -Path $dst -Recurse -Force
    Copy-Item -Path $src -Destination $dst -Recurse -Force

    Remove-Item -Path "$dst\Profiles\friul4wx.default-release\places.sqlite" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$dst\Profiles\friul4wx.default-release\bookmarkbackups" -Recurse -Force -ErrorAction SilentlyContinue

} catch {
    Log-Failure "Copying firefox appdata failed: $_"
}
Log-Started-Finished "Finished: Copying firefox appdata finished"
Write-Host

# Microsip
Log-Started-Finished "Started: Copying microsip appdata"
try {
    $exe = "C:\Users\Administrator\AppData\Local\MicroSIP\microsip.exe"
    $src = "Y:\computer\backups\vms appdata\microsip backup"
    $dst = "C:\Users\Administrator\AppData\Roaming\MicroSIP"

    if (-not (Test-Path $exe)) {
        throw "Missing microsip executable at $exe"
    }
    if (-not (Test-Path $src)) {
        throw "Missing microsip appdata backup folder at $src"
    }

    Start-Process -FilePath $exe
    Start-Sleep -Seconds 7

    Stop-Process -Name "microsip" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5

    Remove-Item -Path $dst -Recurse -Force
    Copy-Item -Path $src -Destination $dst -Recurse -Force

} catch {
    Log-Failure "Copying microsip appdata failed: $_"
}
Log-Started-Finished "Finished: Copying microsip appdata finished"
Write-Host

# Microsoft edge
Log-Started-Finished "Started: Copying microsoft edge appdata"
try {
    $exe = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    $src = "Y:\computer\backups\vms appdata\edge backup"
    $dst = "C:\Users\Administrator\AppData\Local\Microsoft\Edge\User Data"

    if (-not (Test-Path $exe)) {
        throw "Missing microsoft edge executable at $exe"
    }
    if (-not (Test-Path $src)) {
        throw "Missing microsoft edge appdata backup folder at $src"
    }

    Start-Process -FilePath $exe
    Start-Sleep -Seconds 7

    Stop-Process -Name "msedge" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5

    Remove-Item -Path $dst -Recurse -Force
    Copy-Item -Path $src -Destination $dst -Recurse -Force

} catch {
    Log-Failure "Copying microsoft edge appdata failed: $_"
}
Log-Started-Finished "Finished: Copying microsoft edge appdata finished"
Write-Host

# Notepad++
Log-Started-Finished "Started: Copying notepad++ appdata"
try {
    $exe = "C:\Program Files\Notepad++\Notepad++.exe"
    $src = "Y:\computer\backups\vms appdata\notepadplusplus backup"
    $dst = "C:\Users\Administrator\AppData\Roaming\Notepad++"

    if (-not (Test-Path $exe)) {
        throw "Missing notepad++ executable at $exe"
    }
    if (-not (Test-Path $src)) {
        throw "Missing notepad++ appdata backup folder at $src"
    }

    Start-Process -FilePath $exe
    Start-Sleep -Seconds 7

    Stop-Process -Name "notepad++" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5

    Remove-Item -Path $dst -Recurse -Force
    Copy-Item -Path $src -Destination $dst -Recurse -Force

} catch {
    Log-Failure "Copying notepad++ appdata failed: $_"
}
Log-Started-Finished "Finished: Copying notepad++ appdata finished"
Write-Host

# Ntlite
Log-Started-Finished "Started: Copying ntlite appdata"
try {
    $exe = "C:\Program Files\NTLite\NTLite.exe"
    $presetDst = "C:\Program Files\NTLite\Presets"
    $presetSrc1 = "Y:\computer\scripts\win11doafter\ntlitestuff\win11 pro base changes ntlite preset.xml"
    $presetSrc2 = "Y:\computer\scripts\win11doafter\ntlitestuff\win11 home base changes ntlite preset.xml"

    if (-not (Test-Path $exe)) {
        throw "Missing ntlite executable at $exe"
    }
    if (-not (Test-Path $presetSrc1)) {
        throw "Missing win11 pro base changes ntlite preset at $presetSrc1"
    }
    if (-not (Test-Path $presetSrc2)) {
        throw "Missing win11 home base changes ntlite preset file at $presetSrc2"
    }

    Start-Process -FilePath $exe
    Start-Sleep -Seconds 7

    Stop-Process -Name "NTLite" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5

    if (Test-Path $presetDst) {
        Remove-Item -Path $presetDst -Recurse -Force
    }
    New-Item -Path $presetDst -ItemType Directory -Force | Out-Null

    Copy-Item -Path $presetSrc1 -Destination (Join-Path $presetDst "win11 pro base changes.xml") -Force
    Copy-Item -Path $presetSrc2 -Destination (Join-Path $presetDst "win11 home base changes.xml") -Force

} catch {
    Log-Failure "Copying ntlite appdata failed: $_"
}
Log-Started-Finished "Finished: Copying ntlite appdata finished"
Write-Host

# Openvpn
Log-Started-Finished "Started: Copying openvpn appdata"
try {
	$exe = "C:\Program Files\OpenVPN\bin\openvpn-gui.exe"
    $src = "Y:\computer\scripts\win11doafter\apps\vpn config"
    $dst = "C:\Program Files\OpenVPN\config"

    if (-not (Test-Path $exe)) {
        throw "Missing openvpn executable at $exe"
	}
    if (-not (Test-Path $src)) {
        throw "Missing openvpn appdata backup folder at $src"
    }

    if (Test-Path $dst) {
        Remove-Item -Path $dst -Recurse -Force
    }

    Copy-Item -Path $src -Destination $dst -Recurse -Force
    Start-Sleep -Seconds 5

} catch {
    Log-Failure "Copying openvpn appdata failed: $_"
}
Log-Started-Finished "Finished: Copying openvpn appdata finished"
Write-Host

# Plex
Log-Started-Finished "Started: Copying Plex appdata"
try {
    $exe = "C:\Program Files\Plex\Plex\Plex.exe"
    $src = "Y:\computer\backups\vms appdata\plex backup"
    $dst = "C:\Users\Administrator\AppData\Local\Plex"
    $fwAHK = "Y:\computer\scripts\win11doafter\autohotkeys\firewallwindow.ahk"

    if (-not (Test-Path $exe)) {
        throw "Missing plex executable at $exe"
    }
    if (-not (Test-Path $src)) {
        throw "Missing plex appdata backup folder at $src"
    }
    if (-not (Test-Path $fwAHK)) {
        throw "Missing plex firewall ahk file at $fwAHK"
    }

    Start-Process -FilePath $exe
    Start-Sleep -Seconds 7

    Stop-Process -Name "Plex" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 15

    Start-Process -FilePath $fwAHK

    Remove-Item -Path $dst -Recurse -Force
    Copy-Item -Path $src -Destination $dst -Recurse -Force

} catch {
    Log-Failure "Copying Plex appdata failed: $_"
}
Log-Started-Finished "Finished: Copying Plex appdata finished"
Write-Host

<#
# Sandboxie
Log-Started-Finished "Started: Copying sandboxie appdata"
try {
    $exe = "C:\Program Files\Sandboxie-Plus\SandMan.exe"
    $iniSrc = "Y:\computer\backups\vms appdata\sandboxie backup\Sandboxie-Plus.ini"
    $iniDst = "C:\Users\Administrator\AppData\Local\Xanasoft\Sandboxie-Plus\Sandboxie-Plus.ini"

    if (-not (Test-Path $exe)) {
        throw "Missing sandboxie executable at $exe"
    }
    if (-not (Test-Path $iniSrc)) {
        throw "Missing sandboxie appdata backup ini file at $iniSrc"
    }

    Start-Process -FilePath $exe
    Start-Sleep -Seconds 7

    Stop-Process -Name "SandMan" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5

    Remove-Item -Path $iniDst -Force -ErrorAction SilentlyContinue
    Copy-Item -Path $iniSrc -Destination $iniDst -Force

} catch {
    Log-Failure "Copying sandboxie appdata failed: $_"
}
Log-Started-Finished "Finished: Copying sandboxie appdata finished"
Write-Host
#>

# Vlc
Log-Started-Finished "Started: Copying vlc appdata"
try {
    $exe = "C:\Program Files\VideoLAN\VLC\vlc.exe"
    $src = "Y:\computer\backups\vms appdata\vlc backup"
    $dst = "C:\Users\Administrator\AppData\Roaming\vlc"

    if (-not (Test-Path $exe)) {
        throw "Missing vlc executable at $exe"
    }
    if (-not (Test-Path $src)) {
        throw "Missing vlc appdata backup folder at $src"
    }

    Start-Process -FilePath $exe
    Start-Sleep -Seconds 7

    Stop-Process -Name "vlc" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5

    Remove-Item -Path $dst -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -Path $src -Destination $dst -Recurse -Force

} catch {
    Log-Failure "Copying vlc appdata failed: $_"
}
Log-Started-Finished "Finished: Copying vlc appdata finished"
Write-Host

# Install bitwarden for microsoft edge extension
Log-Started-Finished "Started: Installing bitwarden for microsoft edge extension"
try {
    $installScript = "Y:\computer\scripts\win11doafter\supportfiles\installextensions.ps1"
    $extensionId = "jbkfoedolllekgbhcbcoahefnbanhhlh"

    if (-not (Test-Path $installScript)) {
        throw "Missing bitwarden for microsoft edge extension file at $installScript"
    }

    $proc = Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-noprofile", "-executionpolicy", "bypass", "-file", "`"$installScript`"", "-extensionId", $extensionId `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Installing bitwarden for microsoft edge extension failed with exit code $($proc.ExitCode)"
    }

} catch {
    Log-Failure "Installing bitwarden for microsoft edge extension failed: $_"
}
Log-Started-Finished "Finished: Installing bitwarden for microsoft edge extension finished"
Write-Host

# Remove scan with microsoft defender from context menu
Log-Started-Finished "Started: Removing scan with microsoft defender from context menu"
try {
    $proc = Start-Process reg.exe `
        -ArgumentList 'add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked" /v {09A47860-11B0-4DA5-AFA5-26D86198A780} /t REG_SZ /d "Scan with Microsoft Defender" /f' `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Removing scan with microsoft defender from context menu failed with exit code $($proc.ExitCode)"
    }

	Stop-Process -Name explorer -Force
	Start-Sleep -Seconds 5
	Start-Process explorer.exe
	Start-Sleep -Seconds 7

	& "Y:\computer\scripts\win11doafter\autohotkeys\close_file_explorer.exe" | Out-Null

    Log-Started-Finished "Finished: Removing scan with microsoft defender from context menu"
}
catch {
    Log-Failure "Removing scan with microsoft defender from context menu failed: $_"
}
Write-Host

# Remove desktop and context menu file
Log-Started-Finished "Started: Removing desktop and context menu files"
$itemsToRemove = @(
    "C:\Users\Administrator\Desktop\powerplan",
    "C:\Users\Administrator\Desktop\virtio",
    "C:\Users\Administrator\AppData\Roaming\Microsoft\Windows\SendTo\Bluetooth file Transfer.lnk",
    "C:\Users\Administrator\AppData\Roaming\Microsoft\Windows\SendTo\Compressed (zipped) Folder.ZFSendToTarget",
    "C:\Users\Administrator\AppData\Roaming\Microsoft\Windows\SendTo\Mail Recipient.MAPIMail",
    "C:\Users\Administrator\AppData\Roaming\Microsoft\Windows\SendTo\Documents.mydocs"
)
foreach ($item in $itemsToRemove) {
    try {
        Remove-Item -LiteralPath $item -Recurse -Force
    } catch {
        Log-Failure "Removing $item failed: $_"
    }
}
Log-Started-Finished "Finished: Removing desktop and context menu files finished"
Write-Host

# Set runonfirstboot script to run after reboot
Log-Started-Finished "Started: Setting runonfirstboot script to run after reboot"
try {
	Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
		-Name "NextRun" `
		-Value 'cmd.exe /c "timeout /t 20 /nobreak && Y:\computer\scripts\win11doafter\runonfirstboot\kingcrab-runonfirstboot.bat"'
} catch {
    Log-Failure "Setting runonfirstboot script to run after reboot failed: $_"
}
Log-Started-Finished "Finished: Setting runonfirstboot script to run after reboot finished"
Write-Host

# Add jons wifi profile
Log-Started-Finished "Started: Adding jons wifi profile"
try {
    $wifiScript = "Y:\computer\scripts\win11doafter\supportfiles\Add_WiFi_Profile.ps1"
    $wifiXml = "Y:\computer\scripts\win11doafter\supportfiles\JONSWIFI.xml"

    if (-not (Test-Path $wifiScript)) {
        throw "Missing add wifi profile file at $wifiScript"
    }
    if (-not (Test-Path $wifiXml)) {
        throw "Missing jons wifi profile xml file at $wifiXml"
    }

    $proc = Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$wifiScript`" `"$wifiXml`"" `
        -Wait -WindowStyle Hidden -PassThru

    if ($proc.ExitCode -ne 0) {
        throw "Adding jons wifi profile failed with exit code $($proc.ExitCode)"
    }

} catch {
    Log-Failure "Adding jons wifi profile failed: $_"
}
Log-Started-Finished "Finished: Adding jons wifi profile finished"
Write-Host

<#
# Copy runafterdeploy script to desktop
Log-Started-Finished "Started: Copying runafterdeploy script to desktop"
try {
    $runSrc = "Y:\computer\scripts\win11doafter\supportfiles\runafterdeploy.ps1"
    $runDst = "C:\Users\Administrator\Desktop\RUNAFTERDEPLOY.ps1"

    if (-not (Test-Path $runSrc)) {
        throw "Missing runafterdeploy script file at $runSrc"
    }

    Copy-Item -Path $runSrc -Destination $runDst -Force

} catch {
    Log-Failure "Copying runafterdeploy script to desktop failed: $_"
}
Log-Started-Finished "Finished: Copying runafterdeploy script to desktop finished"
Write-Host
#>

# Stop machine script time tracking
Log-Started-Finished "Started: Stopping machine script time tracking"
$end_time = [int](Get-Date -UFormat %s)
Write-Host

# Calculate, build, contruct, and log length of time machine script ran
Log-Started-Finished "Started: Calculating, building, contructing, and logging length of time machine script ran"
# Calculate duration
$duration = $end_time - $start_time
$hours = [int]($duration / 3600)
$minutes = [int](($duration % 3600) / 60)
$seconds = $duration % 60

# Build a friendly duration message
if ($hours -gt 0) {
    $DURATION_MSG = "$hours hours, $minutes minutes, and $seconds seconds"
} elseif ($minutes -gt 0) {
    $DURATION_MSG = "$minutes minutes, and $seconds seconds"
} else {
    $DURATION_MSG = "$seconds seconds"
}

# Construct deployment summary
$DEPLOYMENT_SUMMARY = @"
Machine script has finished taking $DURATION_MSG
"@

# Log to file
$DEPLOYMENT_SUMMARY | Tee-Object -FilePath "C:\Users\Public\Desktop\TIME_LOG.txt" -Append | Out-Null
Log-Started-Finished "Finished: Calculating, building, contructing, and logging length of time machine script ran finished"
Write-Host

#Read-Host -Prompt "Press Enter to continue"

# Set system to reboot so runonfirstboot can run
Log-Started-Finished "Started: Setting system to reboot so runonfirstboot can run"
Log-Started-Finished "Finished: Machine script finished"
try {
    Restart-Computer -Force
} catch {
    Log-Failure "Setting system to reboot so runonfirstboot can run failed: $_"
	Log-Started-Finished "Finished: Machine script finished but reboot failed"
}
