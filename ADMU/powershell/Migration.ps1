[CmdletBinding(DefaultParameterSetName = "cmd")]
Param (
    [Parameter(ParameterSetName = "cmd", Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)][ValidateNotNullOrEmpty()][string]$DomainUserName ,
    [Parameter(ParameterSetName = "cmd", Mandatory = $true, Position = 1, ValueFromPipelineByPropertyName = $true)][ValidateNotNullOrEmpty()][string]$JumpCloudUserName ,
    [Parameter(ParameterSetName = "cmd", Mandatory = $true, Position = 2, ValueFromPipelineByPropertyName = $true)][ValidateNotNullOrEmpty()][string]$TempPassword ,
    [Parameter(ParameterSetName = "cmd", Mandatory = $true, Position = 3, ValueFromPipelineByPropertyName = $true)][ValidateNotNullOrEmpty()][ValidateLength(40, 40)][string]$JumpCloudConnectKey ,
    [Parameter(ParameterSetName = "cmd", Mandatory = $false, Position = 4, ValueFromPipelineByPropertyName = $true)][ValidateNotNullOrEmpty()][string]$AcceptEULA = $false ,
    [Parameter(ParameterSetName = "cmd", Mandatory = $false, Position = 5, ValueFromPipelineByPropertyName = $true)][ValidateNotNullOrEmpty()][string]$InstallJCAgent = $false,
    [Parameter(ParameterSetName = "cmd", Mandatory = $false, Position = 6, ValueFromPipelineByPropertyName = $true)][ValidateNotNullOrEmpty()][string]$LeaveDomain = $false ,
    [Parameter(ParameterSetName = "cmd", Mandatory = $false, Position = 7, ValueFromPipelineByPropertyName = $true)][ValidateNotNullOrEmpty()][string]$ForceReboot = $false ,
    [Parameter(ParameterSetName = "cmd", Mandatory = $false, Position = 8, ValueFromPipelineByPropertyName = $true)][ValidateNotNullOrEmpty()][string]$AzureADProfile = $false ,
    #TODO ,[Parameter(ParameterSetName="cmd",Mandatory = $true, Position = 9, ValueFromPipelineByPropertyName = $true)][ValidateNotNullOrEmpty()][ValidateLength(40, 40)][string]$JumpCloudApiKey
    [Parameter(ParameterSetName = "form")][Object]$inputObject
)
Begin
{
    # Define misc static variables
    $adkSetupLink = 'https://go.microsoft.com/fwlink/?linkid=2086042'
    $jcAdmuTempPath = 'C:\Windows\Temp\JCADMU\'
    $jcAdmuLogFile = 'C:\Windows\Temp\jcAdmu.log'
    $UserStateMigrationToolx64Path = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\User State Migration Tool\'
    $UserStateMigrationToolx86Path = 'C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\User State Migration Tool\'

    $profileStorePath = $jcAdmuTempPath + 'store'
    $adksetupfile = 'adksetup.exe'
    $adkSetupPath = $jcAdmuTempPath + $adksetupfile
    $adkSetupArguments = ' /features OptionId.UserStateMigrationTool'
    $adkSetupArgumentsQuiet = '/quiet ' + $adkSetupArguments
    $msvc2013x64File = 'vc_redist.x64.exe'
    $msvc2013x86File = 'vc_redist.x86.exe'
    $msvc2013x86Link = 'http://download.microsoft.com/download/0/5/6/056dcda9-d667-4e27-8001-8a0c6971d6b1/vcredist_x86.exe'
    $msvc2013x64Link = 'http://download.microsoft.com/download/0/5/6/056dcda9-d667-4e27-8001-8a0c6971d6b1/vcredist_x64.exe'
    $msvc2013x86Install = "$jcAdmuTempPath$msvc2013x86File /install /quiet /norestart"
    $msvc2013x64Install = "$jcAdmuTempPath$msvc2013x64File /install /quiet /norestart"
    $CommandScanStateTemplate = 'cd "{0}amd64\"; .\ScanState.exe "{1}" /config:"{0}config.xml" /i:"{0}miguser.xml" /i:"{0}migapp.xml" /l:"{1}\scan.log" /progress:"{1}\scan_progress.log" /o /ue:"*\*" /ui:"{2}\{3}" /c' # $UserStateMigrationToolVersionPath, $profileStorePath, $netBiosName, $DomainUserName
    $CommandLoadStateTemplate = 'cd "{0}amd64\"; .\LoadState.exe "{1}" /config:"{0}config.xml" /i:"{0}miguser.xml" /i:"{0}migapp.xml" /l:"{1}\load.log" /progress:"{1}\load_progress.log" /ue:"*\*" /ui:"{2}\{3}" /laC:"{4}" /lae /c /mu:"{2}\{3}:{5}\{6}"' # $UserStateMigrationToolVersionPath, $profileStorePath, $netBiosName, $DomainUserName, $TempPassword, $localComputerName, $JumpCloudUserName

    # JumpCloud Agent Installation Variables
    $AGENT_PATH = "${env:ProgramFiles}\JumpCloud"
    $AGENT_CONF_FILE = "\Plugins\Contrib\jcagent.conf"
    $AGENT_BINARY_NAME = "JumpCloud-agent.exe"
    $AGENT_SERVICE_NAME = "JumpCloud-agent"
    $AGENT_INSTALLER_URL = "https://s3.amazonaws.com/jumpcloud-windows-agent/production/JumpCloudInstaller.exe"
    $AGENT_INSTALLER_PATH = "C:\windows\Temp\JCADMU\JumpCloudInstaller.exe"
    $AGENT_UNINSTALLER_NAME = "unins000.exe"
    $EVENT_LOGGER_KEY_NAME = "hklm:\SYSTEM\CurrentControlSet\services\eventlog\Application\JumpCloud-agent"
    $INSTALLER_BINARY_NAMES = "JumpCloudInstaller.exe,JumpCloudInstaller.tmp"
    # Load functions
    . ((Split-Path -Path:($MyInvocation.MyCommand.Path)) + '\Functions.ps1')
    # Start script
    Write-Log -Message:('Script starting; Log file location: ' + $jcAdmuLogFile)
    Write-Log -Message:('Gathering system & profile information')
    $WmiComputerSystem = Get-WmiObject -Class:('Win32_ComputerSystem')
    $WmiProduct = Get-WmiObject -Class:('Win32_Product') | Where-Object -FilterScript {$_.Name -like "User State Migration Tool*"}
    $WmiOperatingSystem = Get-WmiObject -Class:('Win32_OperatingSystem')
    $localComputerName = $WmiComputerSystem.Name
    $UserStateMigrationToolVersionPath = Switch ($WmiOperatingSystem.OSArchitecture)
    {
        '64-bit' {$UserStateMigrationToolx64Path}
        '32-bit' {$UserStateMigrationToolx86Path}
        Default {Write-Log -Message:('Unknown OSArchitecture') -Level:('Error')}
    }
}
Process
{
    # Conditional ParameterSet logic
    If ($PSCmdlet.ParameterSetName -eq "form")
    {
        $DomainUserName = $inputObject.DomainUserName
        $JumpCloudUserName = $inputObject.JumpCloudUserName
        $TempPassword = $inputObject.TempPassword
        $JumpCloudConnectKey = $inputObject.JumpCloudConnectKey
        $AcceptEULA = $inputObject.AcceptEula
        $InstallJCAgent = $inputObject.InstallJCAgent
        $LeaveDomain = $InputObject.LeaveDomain
        $ForceReboot = $InputObject.ForceReboot
    }

    #region Check Domain Join Status, Netbiosname & $AzureADProfile param
    If ($WmiComputerSystem.partOfDomain -eq $true)
    {
        if ($AzureADProfile -eq '$false'){
            $DomainName = $WmiComputerSystem.Domain
            $netBiosName = GetNetBiosName
            Write-Log -Message:($localComputerName + ' is currently Domain joined to ' + $DomainName)
        }
        elseif($AzureADProfile -eq '$true')
        {
            $DomainName = 'AzureAD'
            $netBiosName = 'AzureAD'
            Write-Log -Message:($localComputerName + ' is currently Domain joined and $AzureADProfile = $true')
        }
    }
    elseif ($WmiComputerSystem.partOfDomain -eq $false)
    {
        if ($AzureADProfile -eq '$false')
        {
            Write-Log -Message:('System is NOT joined to a domain and $AzureADProfile = $false.') -Level:('Error')
            exit
        }
        elseif ($AzureADProfile -eq '$true')
        {
            $DomainName = 'AzureAD'
            $netBiosName = 'AzureAD'
            Write-Log -Message:($localComputerName + ' is currently Not Domain joined and $AzureADProfile = $true')

        }
    }

    #endregion Check Domain Join Status & Netbiosname

    # Start Of Console Output
    Write-Log -Message:('Windows Profile "' + $DomainName + '\' + $DomainUserName + '" going to be duplicated and converted to "' + $localComputerName + '\' + $JumpCloudUserName + '"')

    #region User State Migration Tool Install & EULA Check
    If (-not $WmiProduct -and -not (Test-Path -Path:($UserStateMigrationToolVersionPath + '\amd64')))
    {
        # Remove existing jcAdmu folder
        If (Test-Path -Path:($jcAdmuTempPath))
        {
            Write-Log -Message:('Removing Temp Files & Folders')
            Remove-ItemIfExists -Path:($jcAdmuTempPath) -Recurse
        }
        # Create jcAdmu folder
        If (!(Test-Path -Path:($jcAdmuTempPath)))
        {
            New-Item -Path:($jcAdmuTempPath) -ItemType:('Directory') | Out-Null
        }
        # Download WindowsADK
        DownloadLink -Link:($adkSetupLink) -Path:($adkSetupPath)
        # Test Path
        If (Test-Path -Path:($adkSetupPath))
        {
            Write-Log -Message:('Download of Windows ADK Setup file completed successfully')
        }
        Else
        {
            Write-Log -Message:('Failed To Download Windows ADK Setup') -Level:('Error')
            Exit;
        }
        # Not Installed & Not In Right Dir
        If ($AcceptEULA -eq '$false')
        {
            Write-Log -Message:('Installing Windows ADK, please complete GUI prompts & accept EULA within 5 mins or it will Exit.')
            Start-NewProcess -pfile:($adkSetupPath) -arguments:($adkSetupArguments)
        }
        ElseIf ($AcceptEULA -eq '$true')
        {
            Write-Log -Message:('Installing Windows ADK, silently. By using "$AcceptEULA = "true" you are accepting the "Microsoft Windows ADK EULA". This process could take up to 3 mins if .net is required to be installed, it will timeout if it takes longer than 5 mins.')
            Start-NewProcess -pfile:($adkSetupPath) -arguments:($adkSetupArgumentsQuiet)
        }
    }
    ElseIf ($WmiProduct -and (-not (Test-Path -Path:($UserStateMigrationToolVersionPath + '\amd64'))))
    {
        # Installed But Not In Right Dir
        Write-Log -Message:('Microsoft Windows ADK is installed but User State Migration Tool cant be found - Please correct and Try again.') -Level:('Error')
        Exit;
    }
    # Test User State Migration Tool install path & build config.xml
    If (Test-Path -Path:($UserStateMigrationToolVersionPath + '\amd64')) {
        Write-Log -Message:('Microsoft Windows ADK - User State Migration Tool ready to be used.')

        if (-Not (Test-Path -Path:($UserStateMigrationToolVersionPath + '\config.xml')) -or (-Not (Test-Path -Path:($UserStateMigrationToolVersionPath + '\MigUser.xml')) -or (-Not (Test-Path -Path:($UserStateMigrationToolVersionPath + '\MigApp.xml'))))) {
            try {
                $usmtconfig.save($UserStateMigrationToolVersionPath + '\config.xml')
                $usmtmiguser.save($UserStateMigrationToolVersionPath + '\MigUser.xml')
                $usmtmigapp.save($UserStateMigrationToolVersionPath + '\MigApp.xml')
            }
            catch {
                Write-Log -Message:('Unable to create custom USMT xml files') -Level:('Error')
                Exit;
            }
        }

    }
    Else {
        Write-Log -Message:('Microsoft Windows ADK - User State Migration Tool not found. Make sure it is installed correctly and in the required location.') -Level:('Error')
        Exit;
    }

    #endregion User State Migration Tool Install & EULA Check

    #region ScanState Step
        Try
        {
            $CommandScanState = $CommandScanStateTemplate -f $UserStateMigrationToolVersionPath, $profileStorePath, $netBiosName, $DomainUserName
            Write-Log -Message:('Starting ScanState tool on user "' + $netBiosName + '\' + $DomainUserName + '"')
            Write-Log -Message:('ScanState tool is in progress. Command: ' + $CommandScanState)
            Invoke-Expression -command:($CommandScanState)
            Write-Log -Message:('ScanState tool completed for user "' + $netBiosName + '\' + $DomainUserName + '"')
        }
        Catch
        {
            Write-Log -Message:('ScanState tool failed for user "' + $netBiosName + '\' + $DomainUserName + '"') -Level:('Error')
            Exit;
        }
    #endregion ScanState Step

    #region LoadState Step
    Try
    {
        $CommandLoadState = $CommandLoadStateTemplate -f $UserStateMigrationToolVersionPath, $profileStorePath, $netBiosName, $DomainUserName, $TempPassword, $localComputerName, $JumpCloudUserName
        Write-Log -Message:('Starting LoadState tool on user "' + $netBiosName + '\' + $DomainUserName + '"' + ' converting to "' + $localComputerName + '\' + $JumpCloudUserName + '"')
        Write-Log -Message:('LoadState tool is in progress. Command: ' + $CommandLoadState)
        Invoke-Expression -Command:($CommandLoadState)
        Write-Log -Message:('LoadState tool completed for user "' + $netBiosName + '\' + $DomainUserName + '"' + ' converting to "' + $localComputerName + '\' + $JumpCloudUserName + '"')
    }
    Catch
    {
        Write-Log -Message:('LoadState tool failed for user "' + $netBiosName + '\' + $DomainUserName + '"' + ' converting to "' + $localComputerName + '\' + $JumpCloudUserName + '"') -Level:('Error')
        Exit;
    }
    #endregion LoadState Step

    #region Add To Local Users Group
    Try
    {
        Write-Log -Message:('Adding new user "' + $JumpCloudUserName + '" to Users group')
        Add-LocalUser -computer:($localComputerName) -group:('Users') -localusername:($JumpCloudUserName)
    }
    Catch
    {
        Write-Log -Message:('Failed To add new user "' + $JumpCloudUserName + '" to Users group') -Level:('Error')
        Exit;
    }
    #endregion Add To Local Users Group

    #region SilentAgentInstall
        if($InstallJCAgent -eq '$true'){
            # Agent Installer Loop
            [int]$InstallReTryCounter = 0
            Do
            {
                $ConfirmInstall = DownloadAndInstallAgent -msvc2013x64link:($msvc2013x64Link) -msvc2013path:($jcAdmuTempPath) -msvc2013x64file:($msvc2013x64File) -msvc2013x64install:($msvc2013x64Install) -msvc2013x86link:($msvc2013x86Link) -msvc2013x86file:($msvc2013x86File) -msvc2013x86install:($msvc2013x86Install)
                $InstallReTryCounter++
                If ($InstallReTryCounter -eq 3)
                {
                    Write-Log -Message:('JumpCloud agent installation failed') -Level:('Error')
                    Exit;
                }
            } While ($ConfirmInstall -ne $true -and $InstallReTryCounter -le 3)
        }

        if ($LeaveDomain -eq '$true'){
            Write-Log -Message:('Leaving Domain')
            Try
            {
                $WmiComputerSystem.UnJoinDomainOrWorkGroup($null, $null, 0)
            }
            Catch
            {
                Write-Log -Message:('Unable to leave domain, JumpCloud agent will not start until resolved') -Level:('Error')
                Exit;
            }
        }

        # Cleanup Folders Again Before Reboot
        Write-Log -Message:('Removing Temp Files & Folders.')
        Start-Sleep -s 10
        Remove-ItemIfExists -Path:($jcAdmuTempPath) -Recurse

        if ($ForceReboot -eq '$true'){
            Write-Log -Message:('Forcing reboot of the PC now')
            Restart-Computer -ComputerName $env:COMPUTERNAME -Force
        }
    #endregion SilentAgentInstall
}
End
{
    Write-Log -Message:('Script finished successfully; Log file location: ' + $jcAdmuLogFile)
    Write-Log -Message:('Tool options chosen were : ' + 'Install JC Agent = ' + $InstallJCAgent + ', Leave Domain = ' + $LeaveDomain + ', Force Reboot = ' + $ForceReboot + ', AzureADProfile = ' + $AzureADProfile)
}
