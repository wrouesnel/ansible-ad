# Ansible Auth

Once machines domain join, we need to switch to Kerberos auth and delete local
credentials. That's...annoyingly tricky. Process adapted from here: https://buildingtents.com/2025/01/15/using-kerberos-to-authenticate-winrm-for-ansible/

It is very specific to the kvmboot style runners.

# AD Helpers

Unix `id` replacements:

```
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$groups = $id.Groups | foreach-object {$_.Translate([Security.Principal.NTAccount])}
$groups | select *
```
# ADCS

Run as Domain Admin
```powershell
Install-WindowsFeature Adcs-Cert-Authority -IncludeManagementTools
Add-WindowsFeature ADCS-Enroll-Web-Pol
Add-WindowsFeature Adcs-Enroll-Web-Svc
Add-WindowsFeature ADCS-Web-Enrollment
Add-WindowsFeature ADCS-Device-Enrollment
Add-WindowsFeature ADCS-Online-Cert

# IIS required for most services
Install-WindowsFeature -name Web-Server -IncludeManagementTools

# Install ADCS
Install-AdcsCertificationAuthority -CAType EnterpriseRootCa `
    -CACommonName "Test Network Root CA" `
    -CADistinguishedNameSuffix "DC=default,DC=libvirt" `
    -HashAlgorithmName SHA512 `
    -KeyLength 4096 `
    -ValidityPeriod Years `
    -ValidityPeriodUnits 20 `
    -Force

Import-Module ServerManager

# Grant administrators permission to enroll web server certificates


# Generate certificate for the webserver
$fqdn = [System.Net.Dns]::GetHostByName($env:computerName).HostName
$certThumbprint = (Get-ChildItem -Path Cert:LocalMachine\MY | Where-Object {$_.Subject -Match $fqdn}).Thumbprint

Get-Certificate `
    -Template "WebServer" `
    -SubjectName $fqdn `
    -DnsName $fqdn `
    -CertStoreLocation "Cert:LocalMachine\MY"

# Policy service
Install-AdcsEnrollmentPolicyWebService -AuthenticationType Kerberos -SSLCertThumbprint $certThumbprint

New-ADServiceAccount `
    -Name gMSA_CEP `
    -PrincipalsAllowedToRetrieveManagedPassword "${env:COMPUTERNAME}$" `
    -DNSHostName "gMSA_CEP.$fqdn"

setspn -S "HTTP/$fqdn" "$env:USERDOMAIN\gMSA_CEP$"

# When the server is separate
# Add-WindowsFeature RSAT-AD-PowerShell 
# Install-ADServiceAccount gMSA_CEP
# Test-ADServiceAccount gMSA_CEP
# -- also maybe something like this?
# Add-LocalGroupMember -Group IIS_IUSRS

Install-AdcsEnrollmentWebService `
    -CAConfig "server-1.default.libvirt\default-SERVER-1-CA-1" `
    -SSLCertThumbprint $certThumbprint `
    -AuthenticationType Kerberos

# Don't do this as a domain admin?
# Install-AdcsNetworkDeviceEnrollmentService -ApplicationPoolIdentity

Install-AdcsNetworkDeviceEnrollmentService -ApplicationPoolIdentity

# This didn't seem to complete everythng?
Install-AdcsWebEnrollment -CAConfig "server-1.default.libvirt\default-SERVER-1-CA-1" -Force
```