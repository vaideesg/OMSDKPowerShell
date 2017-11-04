#
#
# Copyright © 2017 Dell Inc. or its subsidiaries. All rights reserved.
# Dell, EMC, and other trademarks are trademarks of Dell Inc. or its
# subsidiaries. Other trademarks may be trademarks of their respective owners.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Authors: Vaideeswaran Ganesan
#
# Type Management System
enum TypeState {
    UnInitialized
    Initializing
    Precommit
    Committed
    Changing
}

class TypeBase {
    hidden $_orig_value = $null
    hidden $_default = $null
    hidden $_type  = $null
    hidden $_alias = $null
    hidden $_volatile = $False
    hidden $_parent = $null
    hidden $_composite = $False
    hidden $_index = 1
    hidden $_modifyAllowed = $True
    hidden $_deleteAllowed = $True
    hidden $_rebootRequired = $False
    hidden $_default_on_delete = $null
    hidden $_list = $False
    hidden $_freeze = $False
    hidden $_state = [TypeState]::UnInitialized
    hidden $_value
}

class FieldType : TypeBase
{

    FieldType($type, $value, $properties)
    {
        $this._value = $(Add-Member -InputObject $this -MemberType ScriptProperty -TypeName $type -Name 'Value' -Value {
             $this._value
        } -SecondValue {
            # set
            param ( $arg )
            if ($this._modifyAllowed -eq $True -or $this._state -eq [TypeState]::UnInitialized)
            {
                $this._value = $arg
            }
            else
            {
                throw [System.Exception], "Updates not allowed for this object"
            }
        })

        $this._value = $value
        if ($properties -eq $null -or $properties.GetType() -ne [Hashtable])
        {
            return
        }

        if ($properties.ContainsKey('Readonly') -and $properties.Readonly -eq $true)
        {
            $this._modifyAllowed = $False
            $this._deleteAllowed = $False
        }
        if ($properties.ContainsKey('RebootRequired') -and $properties.RebootRequired -eq $true)
        {
            $this._rebootRequired = $True
        }
        if ($properties.ContainsKey('IsList') -and $properties.IsList -eq $true)
        {
            $this._list = $True
        }
    }

    [void] _default($value)
    {
        $this._default = $value
        $this._orig_value = $value
    }

    [string] ToString()
    {
       return [string]$this.value
    }

    [string] Json()
    {
       return [string]$this.value
    }

    [string] myjson($level)
    {
       return [string]$this.value
    }

    [string] modified_xml($level)
    {
       return [string]$this.value
    }

    [bool] commit($loading_from_scp)
    {
        $this._orig_value = $this._value
        $this._state = [TypeState]::Committed
        return $True
    }

    [bool] reject()
    {
        $this.value = $this._orig_value
        if ($this._orig_value -eq $null)
        {
            $this.value = [System.Management.Automation.Language.NullString]::Value
        }
        $this._state = [TypeState]::Committed
        return $True
    }

    [bool] is_changed()
    {
        if ($this.value -ne $this._orig_value)
        {
            if ($this._state -eq [TypeState]::UnInitialized)
            {
                $this._state = [TypeState]::Initializing
            }
            elseif ($this._state -eq [TypeState]::Committed)
            {
                $this._state = [TypeState]::Changing
            }
        }
        else
        {
            if ($this._state -eq [TypeState]::Initializing)
            {
                $this._state = [TypeState]::UnInitialized
            }
            elseif ($this._state -eq [TypeState]::Changing)
            {
                $this._state = [TypeState]::Committed
            }
        }
        return $this._state -eq [TypeState]::Changing -or $this._state -eq [TypeState]::Initializing
    }

    [bool] reboot_required()
    {
        $retval = $False
        if ($this.is_changed())
        {
            $retval = $this._rebootRequired
        }
        return $retval
    }

    [void] freeze()
    {
        $this._freeze = $True
    }
    [void] unfreeze()
    {
        $this._freeze = $False
    }
    [bool] is_frozen()
    {
        return $this._freeze
    }
}

class IntField : FieldType {
    IntField($value, $properties) :
        base([int], $value, $properties)
    {
    }
}

class StringField : FieldType {
    StringField($value, $properties) :
        base([string], $value, $properties)
    {
    }

}

class CompositeField : FieldType {
    hidden [object] $my

    CompositeField($obj, $value, $properties) :
        base([System.Collections.ArrayList], $value, $properties)
    {
        $this.my = $obj
        $this._composite = $True
        $this | Add-Member -MemberType ScriptProperty  -Name 'OptimalValue' -Value {
            $this._optimal()
        } -SecondValue {
            throw [System.Exception], "Updates not allowed for this object"
        }
    }

    [object[]] _optimal()
    {
        print($this.value)
        $t = [System.Collections.ArrayList]::new()
        foreach ($i in $this._value.ToArray()) {
            #write-host ("{0} {1} {2}" -f ($this.my.($i) -eq $null), ($this.my.($i) -eq ""), $this.my($i))
            if ($this.my.($i).value -eq $null -or $this.my.($i).value -eq "") {
                continue
            }
            $t.Add($this.my.($i).value)
        }
        return $t
    }
}

class ClassType {

    [string] myjson($level)
    {
        $s = [System.IO.StringWriter]::new()
        $s.WriteLine("{ ")
        foreach ($field in Get-Member -InputObject $this -MemberType Property)
        {
            $s1 = $this.($field.Name)
            if ($s1.GetType() -ne [System.String]) {
                $s1 = $s1.myjson($level + "  ")
            }
            if ($s1.Contains('{') -eq $False) {
                $s1 = """" +  $s1 + """"
            }
            $s.WriteLine($level + "  """ + $field.Name + """ : " + $s1)
       }
       $s.WriteLine($level + "}")
       return $s.ToString()
    }

    [string] modified_xml($level)
    {
        $s = [System.IO.StringWriter]::new()
        $s.WriteLine("{ ")
        foreach ($field in Get-Member -InputObject $this -MemberType Property)
        {
            $s1 = $this.($field.Name)
            #write-host ("{0}.value = {1} | {2}" -f $field.Name, $s1, $s1.is_changed())
            if ($s1 -eq $null -or $s1.is_changed() -eq $False)
            {
                continue
            }
            if ($s1.GetType() -ne [System.String]) {
                $s1 = $s1.modified_xml($level + "  ")
            }
            if ($s1.Contains('{') -eq $False) {
                $s1 = """" +  $s1 + """"
            }
            $s.WriteLine($level + "  """ + $field.Name + """ : " + $s1)
       }
       if ($s.ToString() -eq "{ ")
       {
            return ""
       }
       $s.WriteLine($level + "}")
       return $s.ToString()
    }

    [string] ModifiedXML() 
    {
        return $this.modified_xml("")
    }

    [string] Json() 
    {
        return $this.myjson("")
    }

    [bool] commit($loading_from_scp)
    {
        $rboot = $False
        foreach ($field in Get-Member -InputObject $this -MemberType Property)
        {
            if ($field.Name -eq '_optimal') { continue }
            $prop = $this.($field.Name)
            if ($prop -eq $null -or $prop.GetType() -eq [System.String]) {
                continue
            }
            if ($prop.commit($loading_from_scp)) {
                $rboot = $True
            }
       }
       return $rboot
    }

    [bool] reject() {
        $rboot = $True
        foreach ($field in Get-Member -InputObject $this -MemberType Property)
        {
            if ($field.Name -eq '_optimal') { continue }
            $prop = $this.($field.Name)
            if ($prop -eq $null -or $prop.GetType() -eq [System.String]) {
                continue
            }
            if ($prop.reject() -eq $False) {
                $rboot = $False
            }
       }
       return $rboot
    }
    [bool] is_changed()
    {
        $rboot = $False
        foreach ($field in Get-Member -InputObject $this -MemberType Property)
        {
            if ($field.Name -eq '_optimal') { continue }
            $prop = $this.($field.Name)
            if ($prop -eq $null -or $prop.GetType() -eq [System.String]) {
                continue
            }
            if ($prop.is_changed()) {
                return $True
            }
       }
       return $rboot
    }
    [bool] reboot_required() {
        $rboot = $False
        foreach ($field in Get-Member -InputObject $this -MemberType Property)
        {
            if ($field.Name -eq '_optimal') { continue }
            $prop = $this.($field.Name)
            if ($prop.GetType() -eq [System.String]) {
                continue
            }
            if ($prop.reboot_required()) {
                return $True
            }
       }
       return $rboot
    }
    [void] freeze()
    {
        foreach ($field in Get-Member -InputObject $this -MemberType Property)
        {
            if ($field.Name -eq '_optimal') { continue }
            $prop = $this.($field.Name)
            if ($prop.GetType() -eq [System.String]) {
                continue
            }
            $prop.freeze()
       }
    }
    [void] unfreeze()
    {
        foreach ($field in Get-Member -InputObject $this -MemberType Property)
        {
            if ($field.Name -eq '_optimal') { continue }
            $prop = $this.($field.Name)
            if ($prop.GetType() -eq [System.String]) {
                continue
            }
            $prop.unfreeze()
       }
    }

    [void] _ignore_fields($name)
    {

    }
    [bool] is_frozen()
    {
        $rboot = $False
        foreach ($field in Get-Member -InputObject $this -MemberType Property)
        {
            if ($field.Name -eq '_optimal') { continue }
            $prop = $this.($field.Name)
            if ($prop.GetType() -eq [System.String]) {
                continue
            }
            if ($prop.is_frozen()) {
                return $True
            }
       }
       return $rboot
    }
}


# Generated Code
enum BootModeTypes{
   Uefi
   Bios
   None
}
enum RebootType {
   True
   False
}
enum DD {
   True
   False
}

class BIOS : ClassType {
    [FieldType]$BootMode
    [FieldType]$BootSeq
    [FieldType]$MemTest

    BIOS($loading_from_scp)
    {
        $this.BootMode = [StringField]::new($null, @{ RebootRequired = $True })
        $this.BootSeq  = [StringField]::new($null, @{})
        $this.MemTest   = [StringField]::new($null, @{ Readonly = $True })
    }
}
class Time: ClassType {
    [FieldType]$DayLightOffset_Time
    [FieldType]$TimeZoneAbbreviation_Time
    [FieldType]$TimeZoneOffset_Time
    [FieldType]$Time_Time
    [FieldType]$Timezone_Time
    [FieldType]$Timezones

    Time($loading_from_scp)
    {
        $this.DayLightOffset_Time = [IntField]::new($null, @{})
        $this.TimeZoneAbbreviation_Time = [StringField]::new("", @{})
        $this.TimeZoneOffset_Time = [IntField]::new($null, @{})
        $this.Time_Time = [IntField]::new($null, @{})
        $this.Timezone_Time = [StringField]::new("", @{})
        $this.Timezones = [CompositeField]::new($this, 
            [System.Collections.ArrayList]('DayLightOffset_Time', 'Time_Time', 'Timezone_Time'), @{})
        $this._ignore_fields('DaylightOffset_Time')
        $this._ignore_fields('TimeZone_Time')
        $this.commit($loading_from_scp)
    }
}

class iDRAC : ClassType {
    #[ValidatePattern("^[01]$")]
    #[string]$ina
    [Time]$Time

    iDRAC($loading_from_scp)
    {
        $this.Time = [Time]::new($loading_from_scp)
       #$this.ina = "1"
    }
}
class SystemConfiguration : ClassType {
    [BIOS]$BIOS
    [iDRAC]$iDRAC
    SystemConfiguration($loading_from_scp) {
       $this.BIOS = [BIOS]::new($loading_from_scp)
       $this.iDRAC = [iDRAC]::new($loading_from_scp)
    }
}

$t = [SystemConfiguration]::new($False)
$t.iDRAC.Time.DayLightOffset_Time.Value = 20
$t.iDRAC.Time.Time_Time.Value = 10
$t.iDRAC.Time.Timezone_Time.Value = 'CDT'
#write-host ($t.iDRAC.Time.Timezone_Time)
write-host ($t.iDRAC.Time.Timezones.OptimalValue)
exit


$t.BIOS.MemTest.value = "CDT"
write-host ("modified XML : {0}" -f $t.ModifiedXML())
write-host ("MemTest.value = {0} " -f $t.BIOS.MemTest.value)
$t.commit()
$t.BIOS.MemTest.value = "ff"
write-host ("MemTest after setting to ff" -f $t.BIOS.MemTest.is_changed())
write-host ("MemTest.value = {0} " -f $t.BIOS.MemTest.value)
write-host ("t.commit() = {0}" -f $t.commit())
write-host ($t.ModifiedXML())
write-host ("t.is_changed() = {0}" -f $t.is_changed())
write-host ("t.reboot_required() = {0}" -f $t.reboot_required())
$t.iDRAC.Time.Timezone_Time = "CDT"
write-host ("t.is_changed() = {0}" -f $t.is_changed())
write-host ("t.reboot_required() = {0}" -f $t.reboot_required())
write-host ($t.BIOS.is_changed())
write-host ("t.commit() = {0}" -f $t.commit())
$t.BIOS.BootMode = [BootModeTypes]::Uefi
write-host ($t.ModifiedXML())
write-host ("t.is_changed() = {0}" -f $t.is_changed())
write-host ("t.reboot_required() = {0}" -f $t.reboot_required())
write-host ("t.commit() = {0}" -f $t.commit())
exit

write-host $t.Json()
if ($t.is_changed()) {
    #idrac.import_scp(reboot_required = $t.reboot_required())
    write-host "Changed"
}
