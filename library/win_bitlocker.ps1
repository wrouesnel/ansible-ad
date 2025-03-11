#!powershell

# Copyright: (c) 2019, Simon Baerlocher <s.baerlocher@sbaerlocher.ch> 
# Copyright: (c) 2019, ITIGO AG <opensource@itigo.ch> 
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#Requires -Module Ansible.ModuleUtils.ArgvParser
#Requires -Module Ansible.ModuleUtils.CommandUtil
#Requires -Module Ansible.ModuleUtils.Legacy

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$params = Parse-Args -arguments $args -supports_check_mode $true
$check_mode = Get-AnsibleParam -obj $params -name "_ansible_check_mode" -type "bool" -default $false
$diff = Get-AnsibleParam -obj $params -name "_ansible_diff" -type "bool" -default $false

$mount = Get-AnsibleParam -obj $params -name "mount" -type "str" -failifempty $true
$state = Get-AnsibleParam -obj $params -name "state" -type "str" -default "query" -validateset "enabled", "disabled", "query"
$keyprotector = Get-AnsibleParam -obj $params -name "keyprotector" -type "str"

# Create a new result object
$result = @{
    changed = $false
}

$result.status = (Get-BitLockerVolume -MountPoint $mount)

# Get the list of existing protectors
$existing_protectors=(Get-BitLockerVolume -MountPoint $mount).KeyProtector | Select-Object -ExpandProperty KeyProtectorType
# Ensure not null and at least an array
if ($null -eq $existing_protectors) { $existing_protectors=@() }
if (($existing_protectors | Measure-Object).Count -le 1) {
    $existing_protectors = @( $existing_protectors )
}

switch ($state) {
    # Query only
    "query" {
        # Do Nothing.
    }
    # Disable BitLocker
    "disabled" {
        if ( $result.status.ProtectionStatus -eq "On" ) {
            if (-not $check_mode) { 
                $res = Disable-BitLocker -MountPoint $mount
                $result.result = $res
            }   
            $result.changed = $true
        }
    }
    # Enable BitLocker
    "enabled" {
        switch ($keyprotector) {
            "RecoveryPasswordProtector" {
                if (-not $existing_protectors.Contains("RecoveryPassword")) {
                    $result.changed = $true
                    if (-not $check_mode) {
                        $res = Enable-BitLocker -MountPoint $mount -RecoveryPasswordProtector
                        $result.result = $res
                    }
                }
            }
            "TpmProtector" {
                if (-not $existing_protectors.Contains("Tpm")) {
                    $result.changed = $true
                    if (-not $check_mode) {
                        $res = Enable-BitLocker -MountPoint $mount -TpmProtector 
                        $result.result = $res
                    }
                }
            }
            default {
                $result.failed = $true
                $result.msg = "Unknown key protector requested: ${keyprotector}"
            }
        }
    }
}

# Get the BitLocker status
$result.status = (Get-BitLockerVolume -MountPoint $mount)

# Return result
Exit-Json -obj $result