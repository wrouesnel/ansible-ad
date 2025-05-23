#!powershell

# Copyright: (c) 2015, Phil Schwartz <schwartzmx@gmail.com>
# Copyright: (c) 2015, Trond Hindenes
# Copyright: (c) 2015, Hans-Joachim Kliemeck <git@kliemeck.de>
# Copyright: (c) 2020, Håkon Heggernes Lerring <hakon@lerring.no>
# Copyright: (c) 2023, Jordan Pitlor <jordan@pitlor.dev>
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

# Modified Version of the win_acl module which imports the dependencies for AD: drive to be available

#Requires -Module Ansible.ModuleUtils.Legacy
#Requires -Module Ansible.ModuleUtils.PrivilegeUtil
#Requires -Module Ansible.ModuleUtils.SID
#Requires -Module Ansible.ModuleUtils.LinkUtil
#AnsibleRequires -CSharpUtil ansible_collections.ansible.windows.plugins.module_utils._CertACLHelper

$ErrorActionPreference = "Stop"

# win_acl module (File/Resources Permission Additions/Removal)

#Functions
# Add functions for handling ActiveDirectory
function New-ADDGuidMap
{
    <#
    .SYNOPSIS
        Creates a guid map for the delegation part
    .DESCRIPTION
        Creates a guid map for the delegation part
    .EXAMPLE
        PS C:\> New-ADDGuidMap
    .OUTPUTS
        Hashtable
    .NOTES
        Author: Constantin Hager
        Date: 06.08.2019
    #>
    $rootdse = Get-ADRootDSE
    $guidmap = @{ }
    $GuidMapParams = @{
        SearchBase = ($rootdse.SchemaNamingContext)
        LDAPFilter = "(schemaidguid=*)"
        Properties = ("lDAPDisplayName", "schemaIDGUID")
    }
    Get-ADObject @GuidMapParams | ForEach-Object { $guidmap[$_.lDAPDisplayName] = [System.GUID]$_.schemaIDGUID }
    return $guidmap
}

function New-ADDExtendedRightMap
{
    <#
    .SYNOPSIS
        Creates a extended rights map for the delegation part
    .DESCRIPTION
        Creates a extended rights map for the delegation part
    .EXAMPLE
        PS C:\> New-ADDExtendedRightsMap
    .NOTES
        Author: Constantin Hager
        Date: 06.08.2019
    #>
    $rootdse = Get-ADRootDSE
    $ExtendedMapParams = @{
        SearchBase = ($rootdse.ConfigurationNamingContext)
        LDAPFilter = "(&(objectclass=controlAccessRight)(rightsguid=*))"
        Properties = ("displayName", "rightsGuid")
    }
    $extendedrightsmap = @{ }
    Get-ADObject @ExtendedMapParams | ForEach-Object { $extendedrightsmap[$_.displayName] = [System.GUID]$_.rightsGuid }
    return $extendedrightsmap
}


function Get-UserSID {
    param(
        [String]$AccountName
    )

    $userSID = $null
    $searchAppPools = $false

    if ($AccountName.Split("\").Count -gt 1) {
        if ($AccountName.Split("\")[0] -eq "IIS APPPOOL") {
            $searchAppPools = $true
            $AccountName = $AccountName.Split("\")[1]
        }
    }

    if ($searchAppPools) {
        Import-Module -Name WebAdministration
        $testIISPath = Test-Path -LiteralPath "IIS:"
        if ($testIISPath) {
            $appPoolObj = Get-ItemProperty -LiteralPath "IIS:\AppPools\$AccountName"
            $userSID = $appPoolObj.applicationPoolSid
        }
    }
    else {
        $userSID = Convert-ToSID -account_name $AccountName
    }

    return $userSID
}

$params = Parse-Args $args

Function SetPrivilegeTokens() {
    # Set privilege tokens only if admin.
    # Admins would have these privs or be able to set these privs in the UI Anyway

    $adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    $myWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $myWindowsPrincipal = new-object System.Security.Principal.WindowsPrincipal($myWindowsID)


    if ($myWindowsPrincipal.IsInRole($adminRole)) {
        # Need to adjust token privs when executing Set-ACL in certain cases.
        # e.g. d:\testdir is owned by group in which current user is not a member and no perms are inherited from d:\
        # This also sets us up for setting the owner as a feature.
        # See the following for details of each privilege
        # https://msdn.microsoft.com/en-us/library/windows/desktop/bb530716(v=vs.85).aspx
        $privileges = @(
            "SeRestorePrivilege", # Grants all write access control to any file, regardless of ACL.
            "SeBackupPrivilege", # Grants all read access control to any file, regardless of ACL.
            "SeTakeOwnershipPrivilege"  # Grants ability to take owernship of an object w/out being granted discretionary access
        )
        foreach ($privilege in $privileges) {
            $state = Get-AnsiblePrivilege -Name $privilege
            if ($state -eq $false) {
                Set-AnsiblePrivilege -Name $privilege -Value $true
            }
        }
    }
}


$result = @{
    changed = $false
}

$path = Get-AnsibleParam -obj $params -name "path" -type "str" -failifempty $true
$user = Get-AnsibleParam -obj $params -name "user" -type "str" -failifempty $true
$rights = Get-AnsibleParam -obj $params -name "rights" -type "str" -failifempty $true

$type = Get-AnsibleParam -obj $params -name "type" -type "str" -failifempty $true -validateset "allow", "deny"
$state = Get-AnsibleParam -obj $params -name "state" -type "str" -default "present" -validateset "absent", "present"

$inherit = Get-AnsibleParam -obj $params -name "inherit" -type "str"
$propagation = Get-AnsibleParam -obj $params -name "propagation" -type "str" -default "None" -validateset "InheritOnly", "None", "NoPropagateInherit"
$follow = Get-AnsibleParam -obj $params -name "follow" -type "bool" -default "false"

# AFAIK these apply to active directory only
$inheritanceType = Get-AnsibleParam -obj $params -name "inheritance_type" -type "str"
$objectType = Get-AnsibleParam -obj $params -name "object_type" -type "str" -default "None"
$childObjectType = Get-AnsibleParam -obj $params -name "child_object_type" -type "str" -default "None"

# We mount the HKCR, HKU, and HKCC registry hives so PS can access them.
# Network paths have no qualifiers so we use -EA SilentlyContinue to ignore that
$path_qualifier = Split-Path -Path $path -Qualifier -ErrorAction SilentlyContinue
if ($path_qualifier -eq "HKCR:" -and (-not (Test-Path -LiteralPath HKCR:\))) {
    New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT > $null
}
if ($path_qualifier -eq "HKU:" -and (-not (Test-Path -LiteralPath HKU:\))) {
    New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS > $null
}
if ($path_qualifier -eq "HKCC:" -and (-not (Test-Path -LiteralPath HKCC:\))) {
    New-PSDrive -Name HKCC -PSProvider Registry -Root HKEY_CURRENT_CONFIG > $null
}
if ($path_qualifier -eq "AD:" -and (-not (Test-Path -LiteralPath AD:\))) {
    Import-Module ActiveDirectory
}

Load-LinkUtils
while ($follow) {
    try {
        $link_info = Get-Link $path
    }
    catch {
        $link_info = $null
    }

    if ($link_info -and $link_info.Type -in @("SymbolicLink", "JunctionPoint")) {
        $path = $link_info.AbsolutePath
        if ($link_info.SubstituteName -like "\??\*") {
            $path = "\\?\" + $path
        }
    }
    else {
        break
    }
}

If (-Not (Test-Path -LiteralPath $path)) {
    Fail-Json -obj $result -message "$path file or directory does not exist on the host"
}

# Test that the user/group is resolvable on the local machine
$sid = Get-UserSID -AccountName $user
if (!$sid) {
    Fail-Json -obj $result -message "$user is not a valid user or group on the host machine or domain"
}

If (Test-Path -LiteralPath $path -PathType Leaf) {
    $inherit = "None"
}
ElseIf ($null -eq $inherit) {
    $inherit = "ContainerInherit, ObjectInherit"
}

# Bug in Set-Acl, Get-Acl where -LiteralPath only works for the Registry provider if the location is in that root
# qualifier. We also don't have a qualifier for a network path so only change if not null. The Cert provider does
# not use Set-Acl or Get-Acl and does not have this bug.
if (($null -ne $path_qualifier) -and ($path_qualifier -ne "Cert:")) {
    Push-Location -LiteralPath $path_qualifier
}

Try {
    SetPrivilegeTokens
    $path_item = Get-Item -LiteralPath $path -Force
    If ($path_item.PSProvider.Name -eq "Registry") {
        $colRights = [System.Security.AccessControl.RegistryRights]$rights
    }
    ElseIf ($path_item.PSProvider.Name -eq "Certificate") {
        $colRights = [Ansible.Windows._CertAclHelper.CertAccessRights]$rights
    }
    ElseIf ($path_item.PSProvider.Name -eq "ActiveDirectory") {
        # The GUID map lookup adds some delay, so avoid doing it if we don't have to.
        $targetObjectType = New-Object System.Guid
        $targetChildObjectType = New-Object System.Guid
        if (($objectType -ne "None") -or ($childObjectType -ne "None") ) {
            $objectGuidMap = New-ADDGuidMap
            if ($objectType -ne "None") {
                $targetObjectType = [System.Guid]$objectGuidMap[$objectType]
            }

            if ($childObjectType -ne "None") {
                $targetChildObjectType = [System.Guid]$objectGuidMap[$childObjectType]
            }
        }
        $colRights = [System.DirectoryServices.ActiveDirectoryRights]$rights
        $InheritanceType = [System.DirectoryServices.ActiveDirectorySecurityInheritance]$inheritanceType
    }
    Else {
        $colRights = [System.Security.AccessControl.FileSystemRights]$rights
    }

    $InheritanceFlag = [System.Security.AccessControl.InheritanceFlags]$inherit
    $PropagationFlag = [System.Security.AccessControl.PropagationFlags]$propagation
    

    If ($type -eq "allow") {
        $objType = [System.Security.AccessControl.AccessControlType]::Allow
    }
    Else {
        $objType = [System.Security.AccessControl.AccessControlType]::Deny
    }

    $objUser = New-Object System.Security.Principal.SecurityIdentifier($sid)
    If ($path_item.PSProvider.Name -eq "Certificate") {
        $cert = Get-Item -LiteralPath $path
        $certSecurityHandle = [Ansible.Windows._CertAclHelper.CertAclHelper]::new($cert)
        $objACL = $certSecurityHandle.Acl
        $objACE = $objACL.AccessRuleFactory($objUser, [int]$colRights, $False, $InheritanceFlag, $PropagationFlag, $objType)
    }
    Else {
        If ($path_item.PSProvider.Name -eq "Registry") {
            $objACE = New-Object System.Security.AccessControl.RegistryAccessRule ($objUser, $colRights, $InheritanceFlag, $PropagationFlag, $objType)
        }
        ElseIf ($path_item.PSProvider.Name -eq "ActiveDirectory") {
            $objACE = New-Object System.DirectoryServices.ActiveDirectoryAccessRule ($objUser, $colRights, $objType, $targetObjectType, $InheritanceFlag, $targetChildObjectType)
        } 
        Else {
            $objACE = New-Object System.Security.AccessControl.FileSystemAccessRule ($objUser, $colRights, $InheritanceFlag, $PropagationFlag, $objType)
        }
        $objACL = Get-ACL -LiteralPath $path
    }

    # Check if the ACE exists already in the objects ACL list
    $match = $false
    $target_rule = $null
    ForEach ($rule in $objACL.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {

        If ($path_item.PSProvider.Name -eq "Registry") {
            If (
                ($rule.RegistryRights -eq $objACE.RegistryRights) -And
                ($rule.AccessControlType -eq $objACE.AccessControlType) -And
                ($rule.IdentityReference -eq $objACE.IdentityReference) -And
                ($rule.IsInherited -eq $objACE.IsInherited) -And
                ($rule.InheritanceFlags -eq $objACE.InheritanceFlags) -And
                ($rule.PropagationFlags -eq $objACE.PropagationFlags)
            ) {
                $match = $true
                $target_rule = $rule
                Break
            }
        }
        ElseIf ($path_item.PSProvider.Name -eq "Certificate") {
            If (
                ($rule.AccessMask -eq $objACE.AccessMask) -And
                ($rule.AccessControlType -eq $objACE.AccessControlType) -And
                ($rule.IdentityReference -eq $objACE.IdentityReference) -And
                ($rule.IsInherited -eq $objACE.IsInherited) -And
                ($rule.InheritanceFlags -eq $objACE.InheritanceFlags) -And
                ($rule.PropagationFlags -eq $objACE.PropagationFlags)
            ) {
                $match = $true
                $target_rule = $rule
                Break
            }
        }
        ElseIf ($path_item.PSProvider.Name -eq "ActiveDirectory") {
            If (
                ($rule.ActiveDirectoryRights -eq $objACE.ActiveDirectoryRights) -And
                ($rule.InheritanceType -eq $objACE.InheritanceType) -And
                ($rule.ObjectType -eq $objACE.ObjectType) -And
                ($rule.InheritedObjectType -eq $objACE.InheritedObjectType) -And
                ($rule.AccessControlType -eq $objACE.AccessControlType) -And
                ($rule.IdentityReference -eq $objACE.IdentityReference) -And
                ($rule.IsInherited -eq $objACE.IsInherited) -And
                ($rule.InheritanceFlags -eq $objACE.InheritanceFlags) # -And
                # ($rule.PropagationFlags -eq $objACE.PropagationFlags)
                # Propagation flags can't be directly set for active directory
            ) {
                $match = $true
                $target_rule = $rule
                Break
            }
        }
        else {
            If (
                ($rule.FileSystemRights -eq $objACE.FileSystemRights) -And
                ($rule.AccessControlType -eq $objACE.AccessControlType) -And
                ($rule.IdentityReference -eq $objACE.IdentityReference) -And
                ($rule.IsInherited -eq $objACE.IsInherited) -And
                ($rule.InheritanceFlags -eq $objACE.InheritanceFlags) -And
                ($rule.PropagationFlags -eq $objACE.PropagationFlags)
            ) {
                $match = $true
                $target_rule = $rule
                Break
            }
        }
    }

    If ($state -eq "present" -And $match -eq $false) {
        Try {
            $objACL.AddAccessRule($objACE)
            if ($path_item.PSProvider.Name -eq "Certificate") {
                $certSecurityHandle.Acl = $objACL
            }
            else {
                Try {
                    Set-ACL -LiteralPath $path -AclObject $objACL
                }
                Catch {
                    (Get-Item -LiteralPath $path).SetAccessControl($objACL)
                }
            }
            $result.changed = $true
        }
        Catch {
            Fail-Json -obj $result -message "an exception occurred when adding the specified rule - $($_.Exception.Message)"
        }
    }
    ElseIf ($state -eq "absent" -And $match -eq $true) {
        Try {
            # Active directory is quite specific about how we're allowed to remove rules
            if ($path_item.PSProvider.Name -eq "ActiveDirectory") {
                $objACL.RemoveAccessRuleSpecific($target_rule)
                Set-ACL -LiteralPath $path -AclObject $objACL
            } else {
                $objACL.RemoveAccessRule($objACE)
                If ($path_item.PSProvider.Name -eq "Registry") {
                    Set-ACL -LiteralPath $path -AclObject $objACL
                }
                elseif ($path_item.PSProvider.Name -eq "Certificate") {
                    $certSecurityHandle.Acl = $objACL
                }
                else {
                    (Get-Item -LiteralPath $path).SetAccessControl($objACL)
                }
            }
            $result.changed = $true
        }
        Catch {
            Fail-Json -obj $result -message "an exception occurred when removing the specified rule - $($_.Exception.Message)"
        }
    }
    Else {
        # A rule was attempting to be added but already exists
        If ($match -eq $true) {
            Exit-Json -obj $result -message "the specified rule already exists"
        }
        # A rule didn't exist that was trying to be removed
        Else {
            Exit-Json -obj $result -message "the specified rule does not exist"
        }
    }
}
Catch {
    Fail-Json -obj $result -message "an error occurred when attempting to $state $rights permission(s) on $path for $user - $($_.Exception.Message)"
}
Finally {
    # Make sure we revert the location stack to the original path just for cleanups sake
    if (($null -ne $path_qualifier) -and ($path_qualifier -ne "Cert:")) {
        Pop-Location
    }
}

Exit-Json -obj $result
