
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
Install-AdcsCertificationAuthority -CAType EnterpriseRootCa

Import-Module ServerManager

$fqdn = [System.Net.Dns]::GetHostByName($env:computerName).HostName
$certThumbprint = (Get-ChildItem -Path Cert:LocalMachine\MY | Where-Object {$_.Subject -Match $fqdn}).Thumbprint

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