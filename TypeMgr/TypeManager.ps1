# Type Management System
enum TypeState {
    UnInitialized
    Initializing
    Precommit
    Committed
    Changing
}

class FieldType {
    $_internal = @{
        '_orig_value' = $null
        '_default' = $null
        '_type'  = $null
        '_alias' = $null
        '_volatile' = $False
        '_parent' = $null
        '_composite' = $False
        '_index' = 1
        '_modifyAllowed' = $True
        '_deleteAllowed' = $True
        '_rebootRequired' = $False
        '_default_on_delete' = $null
        '_list' = $False
        '_freeze' = $False
        '_state' = [TypeState]::UnInitialized
    }

    hidden $_value

    FieldType($type, $value, $readonly, $rebootRequired)
    {
        $this._init($type, $value, $readonly, $rebootRequired)
    }
    FieldType($type, $value)
    {
        $this._init($type, $value, $False, $False)
    }
    [void] _init($type, $value, $readonly, $rebootRequired)
    {
        $this._value = $(Add-Member -InputObject $this -MemberType ScriptProperty -TypeName $type -Name 'value' -Value { $this._value } -SecondValue {
            # set
            param ( $arg )
            if ($this._internal['_modifyAllowed'] -eq $True -or $this._internal['_state'] -eq [TypeState]::UnInitialized)
            {
                $this._value = $arg
            }
        })
        $this._value = $value
        if ($readonly)
        {
            $this._internal['_modifyAllowed'] = $False
            $this._internal['_deleteAllowed'] = $False
        }
        if ($rebootRequired)
        {
            $this._internal['_rebootRequired'] = $True
        }
    }
    [void] _default($value)
    {
        $this._internal['_default'] = $value
        $this._internal['_orig_value'] = $value
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

    [bool] commit()
    {
        $this._internal['_orig_value'] = $this._value
        $this._internal['_state'] = [TypeState]::Committed
        return $True
    }

    [bool] reject()
    {
        $this.value = $this._internal['_orig_value']
        if ($this._internal['_orig_value'] -eq $null)
        {
            $this.value = [System.Management.Automation.Language.NullString]::Value
        }
        $this._internal['_state'] = [TypeState]::Committed
        return $True
    }

    [bool] is_changed()
    {
        if ($this.value -ne $this._internal['_orig_value'])
        {
            if ($this._internal['_state'] -eq [TypeState]::UnInitialized)
            {
                $this._internal['_state'] = [TypeState]::Initializing
            }
            elseif ($this._internal['_state'] -eq [TypeState]::Committed)
            {
                $this._internal['_state'] = [TypeState]::Changing
            }
        }
        else
        {
            if ($this._internal['_state'] -eq [TypeState]::Initializing)
            {
                $this._internal['_state'] = [TypeState]::UnInitialized
            }
            elseif ($this._internal['_state'] -eq [TypeState]::Changing)
            {
                $this._internal['_state'] = [TypeState]::Committed
            }
        }
        return $this._internal['_state'] -eq [TypeState]::Changing -or $this._internal['_state'] -eq [TypeState]::Initializing
    }

    [bool] reboot_required()
    {
        $retval = $False
        if ($this.is_changed())
        {
            $retval = $this._internal['_rebootRequired']
        }
        return $retval
    }

    [void] freeze()
    {
        $this._internal['_freeze'] = $True
    }
    [void] unfreeze()
    {
        $this._internal['_freeze'] = $False
    }
    [bool] is_frozen()
    {
        return $this._internal['_freeze']
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

    [bool] commit()
    {
        $rboot = $False
        foreach ($field in Get-Member -InputObject $this -MemberType Property)
        {
            if ($field.Name -eq '_internal') { continue }
            $prop = $this.($field.Name)
            if ($prop -eq $null -or $prop.GetType() -eq [System.String]) {
                continue
            }
            if ($prop.commit()) {
                $rboot = $True
            }
       }
       return $rboot
    }

    [bool] reject() {
        $rboot = $True
        foreach ($field in Get-Member -InputObject $this -MemberType Property)
        {
            if ($field.Name -eq '_internal') { continue }
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
            if ($field.Name -eq '_internal') { continue }
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
            if ($field.Name -eq '_internal') { continue }
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
            if ($field.Name -eq '_internal') { continue }
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
            if ($field.Name -eq '_internal') { continue }
            $prop = $this.($field.Name)
            if ($prop.GetType() -eq [System.String]) {
                continue
            }
            $prop.unfreeze()
       }
    }
    [bool] is_frozen()
    {
        $rboot = $False
        foreach ($field in Get-Member -InputObject $this -MemberType Property)
        {
            if ($field.Name -eq '_internal') { continue }
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

class BootMode : FieldType {
    BootMode() :base ([BootModeTypes], [BootModeTypes]::None, $False, $True)
    {
    }
    BootMode([BootModeTypes]$value) :base ([BootModeTypes], $value, $False, $True)
    {
    }
}

class Timezone : FieldType {
    Timezone() : base([string], 'Asia/Calcutta') {

    }
    Timezone([string]$value): base([string], $value) {
    }
}

class VDName : FieldType {
    VDName() : base([string], 'Asia/Calcutta', $True, $False){
    }
    VDName([string]$value) : base([string], $value, $True, $False) {
    }
}

class BIOS : ClassType {
    [VDName]$VDName
    BIOS() {
        $this.VDName = [VDName]::new()
    }
}
class iDRAC : ClassType {
    [BootMode]$BootMode
    [Timezone]$Timezone
    #[ValidatePattern("^[01]$")]
    #[string]$ina
    iDRAC() {
        $this.BootMode = [BootMode]::new()
        $this.Timezone = [Timezone]::new()
       #$this.ina = "1"
    }
}
class SystemConfiguration : ClassType {
    [BIOS]$BIOS
    [iDRAC]$iDRAC
    SystemConfiguration() {
       $this.BIOS = [BIOS]::new()
       $this.iDRAC = [iDRAC]::new()
    }
}

$t = [SystemConfiguration]::new()
$t.commit()
$t.BIOS.VDName = "CDT"
write-host ($t.ModifiedXML())
write-host($t.BIOS.VDName.value)
$t.BIOS.VDName.value = "ff"
write-host $t.BIOS.VDName.is_changed()
write-host($t.BIOS.VDName.value)

exit

#write-host ("t.commit() = {0}" -f $t.commit())
#write-host ($t.ModifiedXML())
#write-host ("t.is_changed() = {0}" -f $t.is_changed())
#write-host ("t.reboot_required() = {0}" -f $t.reboot_required())
#$t.BIOS.Timezone = "CDT"
#write-host ("t.is_changed() = {0}" -f $t.is_changed())
#write-host ("t.reboot_required() = {0}" -f $t.reboot_required())
write-host ($t.BIOS.is_changed())
write-host ("t.commit() = {0}" -f $t.commit())
#$t.BIOS.BootMode = [BootModeTypes]::Uefi
write-host ($t.ModifiedXML())
#write-host ("t.is_changed() = {0}" -f $t.is_changed())
#write-host ("t.reboot_required() = {0}" -f $t.reboot_required())
#write-host ("t.commit() = {0}" -f $t.commit())
exit

write-host $t.Json()
if ($t.is_changed()) {
    #idrac.import_scp(reboot_required = $t.reboot_required())
    write-host "Changed"
}
