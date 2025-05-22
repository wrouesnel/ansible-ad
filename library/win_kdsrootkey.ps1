#!powershell
# This file is part of Ansible
#
#
# Ansible is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ansible is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ansible.  If not, see <http://www.gnu.org/licenses/>.

# WANT_JSON
# POWERSHELL_COMMON

$params = Parse-Args $args;
$check_mode = Get-AnsibleParam -obj $params -name "_ansible_check_mode" -type "bool" -default $false

$timeshift = Get-AnsibleParam -obj $params -name "timeshift" -type "int" -default "10"

$result = @{
    changed = $false
    kdsrootkey = ""
}

#$adsi = [ADSI]"WinNT://$env:COMPUTERNAME"
#$group = $adsi.Children | Where-Object {$_.SchemaClassName -eq 'group' -and $_.Name -eq $name }

try {
    If (-not (Get-KDSRootKey)) {
         Add-KDSRootKey -EffectiveTime ((Get-Date).AddHours(-$timeshift))
         $result.changed = $true
         $result.kdsrootkey = (Get-KDSRootKey)
                    }
     else{
        $result.changed = $false
        $result.kdsrootkey = (Get-KDSRootKey)
     }

}
catch {
    Fail-Json $result $_.Exception.Message
}

Exit-Json $result
