Param (
    [Parameter(Mandatory = $true)]
    [string]
    $AzureUserName,

    [string]
    $AzurePassword,

    [string]
    $AzureTenantID,

    [string]
    $AzureSubscriptionID,

    [string]
    $ODLID,

    [string]
    $DeploymentID,

    [string]
    $InstallCloudLabsShadow,

    [string]
    $vmAdminUsername,

    [string]
    $jvmadminUsername,

    [string]
    $jvmadminPassword,

    [string]
    $trainerUserName,

    [string]
    $trainerUserPassword,

    [string]
    $AppId,

    [string]
    $AppSecret,

    [string]
    $azuserobjectid
)

$Inputstring = $AzureUserName
$CharArray = $InputString.Split("@")
$CharArray[1]
$tenantName = $CharArray[1]

Start-Transcript -Path C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt -Append
[Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
Write-Output "TLS setting: $([Net.ServicePointManager]::SecurityProtocol)"

[System.Environment]::SetEnvironmentVariable('AppID', $AppID, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('AppSecret', $AppSecret, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('azuserobjectid', $azuserobjectid, [System.EnvironmentVariableTarget]::Machine)

#Import Common Functions
$path = pwd
$path = $path.Path
$commonscriptpath = "$path" + "\cloudlabs-common\cloudlabs-windows-functions.ps1"
. $commonscriptpath

#Use the commonfunction to install the required files for cloudlabsagent service 
CloudlabsManualAgent Install

# Run Imported functions from cloudlabs-windows-functions.ps1
if (-not (Get-Command Update-AzConfig -ErrorAction SilentlyContinue)) {
    function global:Update-AzConfig {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            $Arguments
        )

        Write-Warning "Update-AzConfig is not available in this Az.Accounts version. Skipping Update-AzConfig call."
    }
}

WindowsServerCommon
InstallAzPowerShellModule
InstallChocolatey

Sleep 20

choco install az.powershell

#ENABLE VM SHADOW
CreateCredFile $AzureUserName $AzurePassword $AzureTenantID $AzureSubscriptionID $DeploymentID
#Enable Cloudlabs Embedded Shadow Feature
Enable-CloudLabsEmbeddedShadow $vmAdminUsername $trainerUserName $trainerUserPassword

#Install AzureAD Module

Install-PackageProvider -Name NuGet -RequiredVersion 2.8.5.208 -Force
Install-Module Microsoft.Graph -Force

#  sleep 20

Install-Module -Name Az.ADDomainServices -Force

sleep 10

if (-not (Test-Path -Path C:\LabFiles)) {
    New-Item -ItemType Directory -Path C:\LabFiles | Out-Null
}

$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/aiw-avd-v3/new-lab-file/logon.ps1", "C:\LabFiles\logontask.ps1")
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/aiw-avd-v3/new-lab-file/vlc.vhdx", "C:\LabFiles\vlc.vhdx")
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/aiw-avd-v3/new-lab-file/msix.cer", "C:\LabFiles\msix.cer")
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/aiw-avd-v3/lab-files/Azure-Virtual-Desktop-Autoscale.json", "C:\LabFiles\AzureVirtualDesktopAutoscale.json")
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/aiw-avd-v3/scripts/PasswordReset.ps1", "C:\LabFiles\PasswordReset.ps1")

#InstallMSAccess
choco install access2016runtime
sleep 5

#Downloadfslogix files
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/aiw-avd-v3/lab-files/FSLogix_Apps.zip", "C:\LabFiles\fslogix.zip")
#unzip files
Expand-Archive c:\LabFiles\fslogix.zip -DestinationPath c:\LabFiles\fslogix
#installing files
Start-Process -Wait -FilePath "C:\LabFiles\fslogix\FSLogix_Apps_2.9.8612.60056\x64\Release\FSLogixAppsRuleEditorSetup.exe" -ArgumentList "/S" -PassThru
Start-Process -Wait -FilePath "C:\LabFiles\fslogix\FSLogix_Apps_2.9.8612.60056\x64\Release\FSLogixAppsSetup.exe" -ArgumentList "/S" -PassThru

# Create folder for FSLogix Rule editor and add rule sets

if (-not (Test-Path -Path C:\LabFiles\Documents\FSLogixRuleSets)) {
    New-Item -ItemType Directory -Path C:\LabFiles\Documents\FSLogixRuleSets -Force | Out-Null
}

$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/aiw-avd-v3/lab-files/hidechrome.fxa", "C:\LabFiles\Documents\FSLogixRuleSets\hidechrome.fxa")
$WebClient.DownloadFile("https://experienceazure.blob.core.windows.net/templates/aiw-avd-v3/lab-files/hidechrome.fxr", "C:\LabFiles\Documents\FSLogixRuleSets\hidechrome.fxr")

#reg key entries
New-Item -Path "HKLM:\SOFTWARE\Microsoft" -Name "MSRDC" -Force
New-Item -Path "HKLM:\SOFTWARE\Microsoft\MSRDC" -Name "Policies" -Force
New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\MSRDC\Policies" -Name "ReleaseRing" -Value "insider" -PropertyType "String"

$LabFilesDirectory = "C:\LabFiles"

. C:\LabFiles\AzureCreds.ps1


$securePassword = $AppSecret | ConvertTo-SecureString -AsPlainText -Force
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $AppID, $SecurePassword
Connect-AzAccount -ServicePrincipal -Credential $cred -Tenant $AzureTenantID | Out-Null
Select-AzSubscription -SubscriptionId $AzureSubscriptionID

Set-AzContext -SubscriptionId $AzureSubscriptionID

function Invoke-WithRetry {
    param(
        [ScriptBlock]$ScriptBlock,
        [int]$MaxAttempts = 5,
        [int]$DelaySeconds = 10,
        [string]$OperationName = "operation"
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return & $ScriptBlock
        }
        catch {
            if ($attempt -eq $MaxAttempts) {
                throw "Failed $OperationName after $MaxAttempts attempts. Last error: $($_.Exception.Message)"
            }

            Write-Warning "$OperationName failed on attempt $attempt of $MaxAttempts. Retrying in $DelaySeconds seconds. Error: $($_.Exception.Message)"
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

$domainName = $AzureUserName.Split("@")[1]
$VnetName = "aadds-vnet"

#Start creating Prerequisites 
Register-AzResourceProvider -ProviderNamespace Microsoft.AAD 

# Get Service Principal
$sp = Get-AzADServicePrincipal -ApplicationId $AppId

# Ensure AAD DC Administrators group exists
try {
    $AADDSGroup = Invoke-WithRetry -OperationName "Get AAD DC Administrators group" -ScriptBlock {
        Get-AzADGroup -DisplayName "AAD DC Administrators" -ErrorAction SilentlyContinue
    }

    if (-not $AADDSGroup) {
        $AADDSGroup = Invoke-WithRetry -OperationName "Create AAD DC Administrators group" -ScriptBlock {
            New-AzADGroup `
                -DisplayName "AAD DC Administrators" `
                -Description "Delegated group to administer Azure AD Domain Services" `
                -MailNickName "AADDCAdministrators" `
                -ErrorAction Stop
        }
        Write-Output "Created AAD DC Administrators group."
    }

    # Add SPN to group
    if ($sp) {
        Invoke-WithRetry -OperationName "Add SPN to AAD DC Administrators" -ScriptBlock {
            Add-AzADGroupMember -TargetGroupObjectId $AADDSGroup.Id -MemberObjectId $sp.Id -ErrorAction Stop
        } | Out-Null
    }

    Write-Output "AAD DC Administrators setup completed."
}
catch {
    Write-Warning "AAD DC Administrators setup failed: $($_.Exception.Message)"
}

Sleep 10

# Task Scheduler
# Scheduled Task
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$User = "$($env:ComputerName)\demouser" 
$Action = New-ScheduledTaskAction -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\Powershell.exe" -Argument "-executionPolicy Unrestricted -File $LabFilesDirectory\logontask.ps1"
Register-ScheduledTask -TaskName "Setup" -Trigger $Trigger -User $User -Action $Action -RunLevel Highest -Force

$Username = "demouser"
$RegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty $RegistryPath 'AutoAdminLogon' -Value "1" -Type String
Set-ItemProperty $RegistryPath 'DefaultUsername' -Value "$Username" -type String
Set-ItemProperty $RegistryPath 'DefaultPassword' -Value "$jvmadminPassword" -type String

Stop-Transcript
Sleep 15
shutdown.exe /r /t 50 /c "CloudLabs post-setup reboot"
exit 0