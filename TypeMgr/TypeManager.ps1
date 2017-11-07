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

    [bool] my_accept_value($value)
    {
        return $true
    }
}

class EnumType
{
    hidden [string]$Name
    EnumType($name, $properties)
    {
        foreach ($prop in $properties.Keys)
        {
            Add-Member -InputObject $this -MemberType NoteProperty -Name $prop -Value $properties[$prop] 
        }
        $this.Name = $name
    }

    [string] ToString()
    {
        return $this.Name
    }
}

class TypeHelper
{
    static [bool] is_enum($type)
    {
        return ($type -eq [EnumType])
    }

    static [object] convert_to_enum($value, $type, $enumtype)
    {
        if ( ($enumtype | Get-Member -MemberType NoteProperty | Where { $enumtype.($_.Name) -eq $value }) -eq $null)
        {
            $value = $null
        }
        return $value
    }
}

class FieldType : TypeBase
{
    # FieldType:: TODO
    # 1. _orig_value and _state should not be allowed for modify outside typemgr
    # 2. How to freeze and unfreeze objects for accidental modification?
    # 3. How to not allow deletion of properties? [Powershell does not allow - so it is ok for now]
    # 4. Comparision Operations - [Workaround: Added __op__ APIs]

    FieldType($type, $value, $properties)
    {
        $this._type = $type
        $this._value = $(Add-Member -InputObject $this -MemberType ScriptProperty -TypeName $type -Name 'Value' -Value {
             $this._value
        } -SecondValue {
            # set
            param ( $value )
            if ($this._modifyAllowed -eq $False -and 
                @([TypeState]::Committed, [TypeState]::Changing).Contains($this._state))
            {
                throw [System.Exception], "1Updates not allowed to this object"
            }
            elseif ($this._composite)
            {
                throw [System.Exception], "Composite objects cannot be modified"
            }
            elseif ($value -eq $null -and 
                   @([TypeState]::Committed, [TypeState]::Precommit, [TypeState]::Changing).Contains($this._state))
            {
                # noop
                return 
            }

            #write-host("this.type={0}, value.type={1}" -f $this.GetType(), $value.GetType())
            #write-host("value={0}, this._type={1}" -f $value, $this._type)
            $valid = $False
            $msg = $null
            if ($value -eq $null -or $value.GetType() -eq $this._type)
            {
                #Write-host ("initial value")
                $valid = $True
            }
            elseif ($this.GetType() -eq $value.GetType())
            {
                #Write-host ("same valuetypes")
                $value = $value.Value
                $valid = $True
            }
            elseif ($value.GetType() -eq [string])
            {
                #Write-host ("converting from string to {0}" -f $this._type)
                # expected value is int
                if ($this._type -eq [int])
                {
                    $value = [int]$value
                    $valid = $True
                }
                # expected value is bool
                elseif ($this._type -eq [bool])
                {
                    $value = [bool]$value
                    $valid = $True
                }
                # expected value is str
                elseif ($this._type -eq [string])
                {
                    $valid = $True
                }
                # expected value is enumeration
                elseif ([TypeHelper]::is_enum($this._type))
                {
                    $newvalue = [TypeHelper]::convert_to_enum($value, $this._type, $this.enumtype)
                    if ($newvalue -ne $null)
                    {
                        $value = $newvalue
                        $valid = $True
                    }
                    else
                    {
                        $msg = "{0} is not {1}" -f $value, $this._type
                    }
                }
                else
                {
                    $msg = ("{0} cannot be converted to {1}" -f $value, $this._type)
                }
            }
            else
            {
                #Write-host ("no conversion found")
                $msg = "No type conversion found for '{0}'. Expected {1}, Got {2}" -f $value, $this._type, $value.GetType()
            }

           #write-host('${0}({1}) <> {2}' -f $value.GetType(), $value, $valid)
           if ($valid -and $this.my_accept_value($value) -eq $False)
           {
                $msg = "{0} returned failure for {1}" -f $this.GetType(), $value
                $valid = $False
            }
            # if invalid, raise ValueError exception
            if ($valid -eq $False)
            {
                #ValueError
                throw [System.Exception], $msg
            }

            # same value - no change
            if ($this._value -eq $value)
            {
                #write-host("..got same value....")
                return
            }
            # List fields, simply append the new entry!
            if ($this._list)
            {
                if ($this.Value -ne $null -and $this.Value -ne "")
                {
                    $value = $this.Value + "," + $value
                }
            }
            # modify the value
            $this._value = $value

            if (@([TypeState]::UnInitialized, [TypeState]::Precommit, [TypeState]::Initializing).Contains($this._state))
            {
                $this._state = [TypeState]::Initializing

            }
            elseif (@([TypeState]::Committed, [TypeState]::Changing).Contains($this._state))
            {
                if ($this._orig_value -eq $this._value)
                {
                    $this._state = [TypeState]::Committed
                }
                else
                {
                    $this._state = [TypeState]::Changing
                }
            }
            else
            {
                write-host("Should not come here")
            }

            if ($this.is_changed() -and $this._parent -ne $null)
            {
                $this._parent.child_state_changed($this._state)
            }
            #write-host("done.....")
        })

        $this._value = $value
        $this | Add-Member -MemberType ScriptProperty  -Name 'OptimalValue' -Value {
            $this.Value
        } -SecondValue {
            throw [System.Exception], "Use Value property to modify"
        }

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


    [void] set_value($value)
    {
        $this.Value = $value
    }

    [void] nullify_value()
    {
        # modify the value
        $this._value = $null

        if (@([TypeState]::UnInitialized, [TypeState]::Precommit, [TypeState]::Initializing).Contains($this._state))
        {
            $this._state = [TypeState]::Initializing

        }
        elseif (@([TypeState]::Committed, [TypeState]::Changing).Contains($this._state))
        {
            if ($this._orig_value -eq $this._value)
            {
                $this._state = [TypeState]::Committed
            }
            else
            {
                $this._state = [TypeState]::Changing
            }
        }
        else
        {
            write-host("Should not come here")
        }

        if ($this.is_changed() -and $this._parent -ne $null)
        {
            $this._parent.child_state_changed($this, $this._state)
        }
    }

    [void]child_state_changed($obj, $obj_state)
    {
    }

    [void]parent_state_changed($new_state)
    {
    }

    # State : to Committed
    # allowed even during freeze
    [bool] commit()
    {
        return $this.commit($False)
    }
    [bool] commit($loading_from_scp)
    {
        if ($this.is_changed() -or $this._state -eq [TypeState]::Precommit)
        {
            if ($this._composite -eq $False)
            {
                $this._orig_value = $this._value
            }
            if ($loading_from_scp)
            {
                $this._state = [TypeState]::Precommit
            }
            else
            {
                $this._state = [TypeState]::Committed
            }
        }
        return $True
    }

    # State : to Committed
    # allowed even during freeze
    [bool] reject()
    {
        if ($this.is_changed())
        {
            if ($this._composite -eq $False)
            {
                $this.value = $this._orig_value
                if ($this._orig_value -eq $null)
                {
                    $this.value = [System.Management.Automation.Language.NullString]::Value
                    $this._state = [TypeState]::UnInitialized
                }
                else
                {
                    $this._state = [TypeState]::Committed
                }
            }
        }
        return $True
    }

    [bool] is_changed()
    {
        return $this._state -in @([TypeState]::Initializing, [TypeState]::Changing)
    }

    [bool] reboot_required()
    {
        return ($this.is_changed() -and $this._rebootRequired)
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

    # Compare APIs:
    [bool] __lt__($other)
    {
        if ($this._state -eq [TypeState]::UnInitialized)
        {
            return $False
        }
        if ($other -eq $null)
        {
            return $False
        }
        $myvalue = $this.Value
        if ($other.GetType() -eq $this.GetType())
        {
            $othervalue = $other.Value
        }
        elseif ($other.GetType() -eq $this._type)
        {
            $othervalue = $other
        }
        else
        {
            throw [System.Exception], 'cannot compare with {0}' -f $other.GetType()
        }
        if ($myvalue -eq $null -and $othervalue -ne $null)
        {
            return $true
        }
        if ($myvalue -eq $null -and $othervalue -eq $null)
        {
            return $False
        }
        return $myvalue -lt $othervalue
    }

    # Compare APIs:
    [bool] __le__($other)
    {
        if ($this._state -eq [TypeState]::UnInitialized)
        {
            return $False
        }
        if ($this.Value -eq $null -and $other -eq $null)
        {
            return $True
        }
        if ($this.Value -ne $null -and $other -eq $null)
        {
            return $False
        }
        $myvalue = $this.Value
        if ($other.GetType() -eq $this.GetType())
        {
            $othervalue = $other.Value
        }
        elseif ($other.GetType() -eq $this._type)
        {
            $othervalue = $other
        }
        else
        {
            throw [System.Exception], 'cannot compare with {0}' -f $other.GetType()
        }
        if ($myvalue -ne $null -and $othervalue -eq $null)
        {
            return $False
        }
        if ($myvalue -eq $null -and $othervalue -ne $null)
        {
            return $True
        }
        return $myvalue -le $othervalue
    }
    

    # Compare APIs:
    [bool] __gt__($other)
    {
        if ($this._state -eq [TypeState]::UnInitialized)
        {
            return $False
        }
        if ($this.Value -eq $null)
        {
            return $False
        }
        if ($this.Value -ne $null -and $other -eq $null)
        {
            return $True
        }
        $myvalue = $this.Value
        if ($other.GetType() -eq $this.GetType())
        {
            $othervalue = $other.Value
        }
        elseif ($other.GetType() -eq $this._type)
        {
            $othervalue = $other
        }
        else
        {
            throw [System.Exception], 'cannot compare with {0}' -f $other.GetType()
        }
        if ($myvalue -ne $null -and $othervalue -eq $null)
        {
            return $True
        }
        return $myvalue > $othervalue
    }

    # Compare APIs:
    [bool] __ge__($other)
    {
        if ($this._state -eq [TypeState]::UnInitialized)
        {
            return $False
        }
        if ($this.Value -eq $null -and $other -eq $null)
        {
            return $True
        }
        if ($this.Value -ne $null -and $other -eq $null)
        {
            return $True
        }
        $myvalue = $this.Value
        if ($other.GetType() -eq $this.GetType())
        {
            $othervalue = $other.Value
        }
        elseif ($other.GetType() -eq $this._type)
        {
            $othervalue = $other
        }
        else
        {
            throw [System.Exception], 'cannot compare with {0}' -f $other.GetType()
        }
        if ($myvalue -eq $null -and $othervalue -eq $null)
        {
            return $True
        }
        if ($myvalue -eq $null -and $othervalue -ne $null)
        {
            return $False
        }
        return $myvalue -ge $othervalue
    }

    # Don't allow comparision with string ==> becomes too generic
    # Compare APIs:
    [bool] __eq__($other)
    {
        if ($this._state -eq [TypeState]::UnInitialized)
        {
            return $False
        }
        if ($this.Value -eq $null -and $other -eq $null)
        {
            return $True
        }
        if ($this.Value -ne $null -and $other -eq $null)
        {
            return $False
        }
        $myvalue = $this.Value
        if ($other.GetType() -eq $this.GetType())
        {
            $othervalue = $other.Value
        }
        elseif ($other.GetType() -eq $this._type)
        {
            $othervalue = $other
        }
        else
        {
            throw [System.Exception], 'cannot compare with {0}' -f $other.GetType()
        }
        if ($myvalue -eq $null -and $othervalue -eq $null)
        {
            return $True
        }
        if ($myvalue -eq $null -and $othervalue -ne $null)
        {
            return $True
        }
        return $myvalue -eq $othervalue

    }
    # Compare APIs:
    [bool] __ne__($other)
    {
        return ($this.__eq__($other) -eq $False)
    }

    [FieldType] clone($value)
    {
        return [FieldType]::new($this._type, $this.Value, @{ Readonly = $this._modifyAllowed; RebootRequired = $this._reboot_required; IsList = $this._list }) 
    }
}

class IntField : FieldType {
    IntField($value, $properties) :
        base([int], $value, $properties)
    {
    }
}

class BooleanField : FieldType {
    BooleanField($value, $properties) :
        base([bool], $value, $properties)
    {
    }
}

class ListField : FieldType {
    ListField($value, $properties) :
        base([string], $value, $properties)
    {
        $this._list = $True
    }
}

class IntRangeField : IntField {
    hidden [int]$max
    hidden [int]$min
    IntRangeField($value, $properties) :
        base($value, $properties)
    {
        $this.min = $properties.Min
        if ($properties.Min -eq $null)
        {
            $this.min = [int]::MinValue
        }
        else
        {
            $this.min = [int]$properties.min
        }
        $this.max = $properties.Max
        if ($properties.Max -eq $null)
        {
            $this.max = [int]::MaxValue
        }
        else
        {
            $this.max = [int]$properties.max
        }
    }

    [bool] my_accept_value($value)
    {
        if ($this.min -eq $null -and $this.max -eq $null)
        {
            return $True
        }
        if ($value -eq $null -or $value -eq '')
        {
            return $True
        }
        if ($value.GetType() -ne [int] -or 
            ($value -lt $this.min -or $value -gt $this.max))
        {
            throw [System.Exception], "{0} should be in range [{1}, {2}]" -f $value, $this.min, $this.max
        }
        return $True
    }
}

class PortField : IntField {
    PortField($value, $properties) :
        base($value, $properties)
    {
    }

    [bool] my_accept_value($value)
    {
        if ($value -eq $null -or $value -eq '')
        {
            return $True
        }
        if ($value.GetType() -ne [int] -or $value -le 0)
        {
            throw [System.Exception], "{0} should be an integer > 0" -f $value
        }
        return $True
    }
}

class StringField : FieldType {
    StringField($value, $properties) :
        base([string], $value, $properties)
    {
    }
}

enum AddressTypes {
    IPv4Address
    IPv6Address
    IPAddress
    MACAddress
    WWPNAddress
}

class AddressHelpers
{
    static [bool] CheckAddress($value, $address_type)
    {
        $match_regex = @()
        if ($address_type -in @([AddressTypes]::IPv4Address, [AddressTypes]::IPAddress))
        {
            $match_regex += @('^\d+([.]\d+){3}$')
        }
        elseif ($address_type -in @([AddressTypes]::IPv6Address, [AddressTypes]::IPAddress))
        {
            $match_regex += @('^[A-Fa-f0-9:]+$')
        }
        elseif ($address_type -in @([AddressTypes]::MACAddress))
        {
            $match_regex += @('^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$')
        }
        elseif ($address_type -in @([AddressTypes]::WWPNAddress))
        {
            $match_regex += @('^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){7}$')
        }
        if ($value -eq $null -or $value -eq '')
        {
            return $True
        }

        if ($value.GetType() -ne [string])
        {
            return $False
        }

        foreach ($pattern in $match_regex)
        {
            if ($value -notmatch $pattern)
            {
                return $False
            }
        }

        if ($address_type -in @([AddressTypes]::IPv4Address, [AddressTypes]::IPAddress) -and $value.Contains(':') -eq $False)
        {
            foreach ($n in $value.split('.'))
            {
                if ([int]$n -gt 255)
                {
                    return $False
                }
            }
        }
        return $True
    }
}

class AddressTypeField : FieldType {
    hidden $type
    AddressTypeField($type, $value, $properties) :
        base([string], $value, $properties)
    {
        $this.type = $type
    }
    [bool] my_accept_value($value)
    {
        return [AddressHelpers]::CheckAddress($value, $this.type)
    }

}

class IPv4AddressField : AddressTypeField {
    IPv4AddressField($value, $properties) :
        base([AddressTypes]::IPv4Address, $value, $properties)
    {
    }
}
class IPAddressField : AddressTypeField {
    IPAddressField($value, $properties) :
        base([AddressTypes]::IPAddress, $value, $properties)
    {
    }
}
class MacAddressField : AddressTypeField {
    MacAddressField($value, $properties) :
        base([AddressTypes]::MACAddress, $value, $properties)
    {
    }
}
class WWPNAddressField : AddressTypeField {
    WWPNAddressField($value, $properties) :
        base([AddressTypes]::WWPNAddress, $value, $properties)
    {
    }
}
class IPv6AddressField : AddressTypeField {
    IPv6AddressField($value, $properties) :
        base([string], [AddressTypes]::IPv6Address, $value, $properties)
    {
    }
}


class EnumTypeField : FieldType {
    hidden $enumType
    EnumTypeField($enumType, $value, $properties) :
        base([EnumType], $value, $properties)
    {
        $this.enumType = $enumType
    }

    [string] ToString()
    {
        return $this.enumType.Name
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
            throw [System.Exception], "Composite objects cannot be modified"
        } -Force
    }

    [object[]] _optimal()
    {
        $t = [System.Collections.ArrayList]::new()
        
        foreach ($i in $this._value.ToArray()) {
            $val = $this.my.($i).Value
            #write-host ("{0} {1} {2}" -f ($val -eq $null), ($val -eq ""), $val)
            if ($val -ne $null -and $val -ne "") 
            {
                $t.Add($val)
            }
        }
        return $t
    }
}


class ClassType : TypeBase {

    # ClassType:: TODO
    # 1. _state should not be allowed for modify outside typemgr
    # 2. How to freeze and unfreeze objects for accidental modification?
    # 3. Comparision Operations - [Workaround: Added __op__ APIs]
    hidden $_attribs
    hidden $_ign_attribs
    hidden $_ign_fields

    [void] _ignore_fields($fields)
    {
        $this._ign_fields = $fields
    }

    [void] _ignore_attribs($attribs)
    {
        $this._ign_attribs = $attribs
    }

    [bool] is_changed()
    {
        #$rboot = $False
        #foreach ($field in Get-Member -InputObject $this -MemberType Property)
        #{
            #if ($field.Name.StartsWith('_')) { continue }
            #$prop = $this.($field.Name)
            #if ($prop -ne $null -and $prop.GetType() -ne [System.String] -and $prop.is_changed()) {
            #    return $True
            #}
        #}
        return $this._state -in @([TypeState]::Initializing, [TypeState]::Precommit, [TypeState]::Changing)
    }

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
        return $this.commit($False)
    }

    #TODO copy_state
    [void] _copy_state($source, $dest)
    {
    }

    #TODO values_changed
    [bool] values_changed($source, $dest)
    {

        return $True
    }

    # TODO _orig_value manipulation
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

    # TODO _orig_value manipulation
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

    # TODO 
    [void]child_state_changed($obj, $obj_state)
    {
    }

    # TODO 
    [void]parent_state_changed($new_state)
    {
    }

    [System.Collections.ArrayList] Properties()
    {
        $ret = [System.Collections.ArrayList]::new()
        foreach ($field in Get-Member -InputObject $this -MemberType Property)
        {
            if ($field.Name.StartsWith('_')) { continue }
            $ret.Add($field)
       }
       return $ret
    }

    [bool] reboot_required() 
    {
        foreach ($prop in $this.Properties())
        {
            if ($prop.reboot_required()) {
                return $True
            }
       }
       return $False
    }
    [void] freeze()
    {
        $this._freeze = $True
        foreach ($prop in $this.Properties())
        {
            $prop.freeze()
       }
    }
    [void] unfreeze()
    {
        $this._freeze = $False
        foreach ($prop in $this.Properties())
        {
            $prop.unfreeze()
       }
    }

    [bool] is_frozen()
    {
        return $this._freeze
    }

    # TODO
    [void] _set_index($index)
    {
    }

    # TODO
    [TypeBase] get_root()
    {
        return $this
    }

    # TODO
    [void] add_attribute($name, $value)
    {
        $this._attribs[$name] = $value
    }

    #TODO
    # compare operators, _get_combined_properties()
}

class RootClassType : ClassType {
}


class IndexHelper
{
    hidden [int]$min_value
    hidden [int]$max_value
    hidden [System.Collections.ArrayList]$indexes_free
    hidden [System.Collections.ArrayList] $reserve
    IndexHelper($min_value, $max_value)
    {
        $this.min_value = $min_value
        $this.max_value = $max_value
        $this.indexes_free = [System.Collections.ArrayList]::new()
        $this.indexes_free.AddRange($this.min_value..$this.max_value)
        $this.reserve = [System.Collections.ArrayList]::new()
    }

    [object] next_index()
    {
        if ($this.indexes_free.Length -gt 0)
        {
            $index = $this.indexes_free[0]
            $this.indexes_free.Remove($index)
            return $index
        }
        throw [System.Exception], 'ran out of all entries'
    }

    [void] unusable($index)
    {
        if ($index -in $this.indexes_free)
        {
            $this.indexes_free.Remove($index)
            $this.reserve.Add($index)
        }
    }

    [void] remove($index)
    {
        if ($index -in $this.indexes_free)
        {
            $this.indexes_free.Remove($index)
        }
    }

    [void] restore_index($index)
    {
        if  ($index -notin $this.reserve -and $index -notin $this.indexes_free)
        {
            $this.indexes_free.Add($index)
            $this.indexes_free = ($this.indexes_free | sort)
        }
    }

    [bool] has_indexes()
    {
        return $this.indexes_free.Length -gt 0
    }

}

class FQDDHelper : IndexHelper
{
    FQDDHelper() : base(1, 30) {}
}

class ArrayType : TypeBase
{
    hidden [System.Collections.ArrayList]$_entries
    hidden $_fname
    hidden $_keys
    hidden $_cls
    hidden $_index_helper
    hidden $_loading_from_scp

    ArrayType($clsname) 
    {
        $this._init($clsname, $null, $null, $False)
    }

    ArrayType($clsname, $parent, $index_helper, $loading_from_scp)
    {
        $this._init($clsname, $parent, $index_helper, $loading_from_scp)
    }
    [void] _init($clsname, $parent, $index_helper, $loading_from_scp)
    {
        $this._fname = $clsname.Name
        $this._parent = $parent
        $this._loading_from_scp = $loading_from_scp
        if ($index_helper -eq $null)
        {
            $index_helper = [IndexHelper]::new(1, 20)
        }
        $this._index_helper = $index_helper
        $this._cls = $clsname
        $this._entries = [System.Collections.ArrayList]::new()
        $this._keys = @{}
        # Special case for Array. Empty Array is still valid
        $this._orig_value = [System.Collections.ArrayList]::new()
        $this._state = [TypeState]::Committed
    }



    [int] Length()
    {
        return $this._entries.Length
    }

    [bool] _copy_state($source, $dest)
    {
        # from _entries to _orig_entries
        $toadd = [System.Collections.ArrayList]::new()
        foreach ($i in $source)
        {
            if ($i -notin $dest)
            {
                $toadd.Add($i)
            }
        }

        $toremove = [System.Collections.ArrayList]::new()
        foreach ($i in $dest)
        {
            if ($i -notin $source)
            {
                $toremove.Add($i)
            }
        }

        foreach ($i in $toremove)
        {
            $dest.remove($i)
        }

        foreach ($i in $toadd)
        {
            $dest.Add($i)
        }

        return $True
    }

    [object] _get_key($entry)
    {
        if ($this.hasattr($entry, 'Key'))
        {
            $key = $entry.Key._value
            if ($key -ne $null) { $key = $key.ToString() }
            return $key
        }
        else
        {
            return $entry._index
        }
    }

    [bool] _values_changed($source, $dest)
    {
        $source_idx = [System.Collections.ArrayList]::new()
        foreach ($entry in $source)
        {
            $source_idx.append($this._get_key($entry))
        }
        foreach ($entry in $dest)
        {
            if ($this._get_key($entry) -notin $source_idx)
            {
                return $False
            }
            $source_idx.remove($this._get_key($entry))
        }
        return ($source_idx.Length -le 0)
    }

    [System.Collections.ArrayList] values_deleted()
    {
        $source_idx = [System.Collections.ArrayList]::new()
        $dest_entries = [System.Collections.ArrayList]::new()
        foreach ($entry in $this._entries)
        {
            $source_idx.Add($this._get_key($entry))
        }
        foreach ($entry in $this._orig_value)
        {
            $key = $this._get_key($entry)
            if ($key -notin $source_idx)
            {
                $dest_entries.append($entry)
                continue
            }
            $source_idx.remove($key)
        }
        return $dest_entries
    }

    # State : to Committed
    # allowed even during freeze
    [bool] commit()
    {
        return $this.commit($False)
    }

    [bool] commit($loading_from_scp)
    {
        if ($this.is_changed())
        {
            if ($this._composite)
            {
                $this._copy_state($this._entries, $this._orig_value)
                #$this._orig_value = sorted($this.__dict__['_orig_value'], key = lambda entry: entry._index)
                foreach ($entry in $this._entries)
                {
                    $entry.commit($loading_from_scp)
                }
            }
            if ($loading_from_scp)
            {
                $this._state = [TypeState]::Precommit
            }
            else
            {
                $this._state = [TypeState]::Committed
            }
        }
        return $true
    }

    # State : to Committed
    # allowed even during freeze
    [bool] reject()
    {
        if ($this.is_changed())
        {
            if (-not $this._composite)
            {
                $this._copy_state($this._orig_value, $this._entries)
                foreach ($entry in $this._entries)
                {
                    $entry.reject()
                    $this._index_helper.restore_index($entry._index)
                }
                foreach ($i in $this._entries)
                {
                    $this._keys[$this._get_key($i)] = $i
                }
                $this._state = [TypeState]::Committed
            }
        }
        return $True
    }

    # Does not have children - so not implemented
    [void] child_state_changed($child, $child_state)
    {

        if ($child_state -in @([TypeState]::Initializing, [TypeState]::Precommit, [TypeState]::Changing))
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
        if ($this.is_changed() -and $this._parent -ne $null)
        {
            $this._parent.child_state_changed($this, $this._state)
        }
    }

    # what to do?
    [void] parent_state_changed($new_state)
    {
        
    }
    # Object APIs
    [bool] copy($other)
    {
        if ($other -eq $null -or $other.GetType() -ne $this)
        {
            return $False
        }
        foreach ($i in $other._entries)
        {
            if ($i -notin $this._entries)
            {
                $this._entries[$i] = $other._entries[$i].clone($this)
            }
            elseif (-not $this._entries[$i]._volatile)
            {
                $this._entries[$i].copy($other._entries[$i])
            }
        }
        return $True
    }

    # Freeze APIs
    [void] freeze()
    {
        $this._freeze = $True
        foreach ($prop in $this.Properties())
        {
            $prop.freeze()
       }
    }
    [void] unfreeze()
    {
        $this._freeze = $False
        foreach ($prop in $this.Properties())
        {
            $prop.unfreeze()
       }
    }

    [bool] is_frozen()
    {
        return $this._freeze
    }

    [object] get_root()
    {
        if ($this._parent -eq $null)
        {
            return $this
        }
        return $this._parent.get_root()
    }

    [bool] my_accept_value($value)
    {
        return $True
    }

    # State APIs:
    [bool] is_changed()
    {
        return $this._state -in @([TypeState]::Initializing, [TypeState]::Precommit, [TypeState]::Changing)
    }

    [bool] reboot_required()
    {
        foreach ($i in $this._entries)
        {
            if ($i.reboot_required())
            {
                return $True
            }
        }
        return $False
    }

    [object] new($index, $kwargs)
    {
        return $this._new($index, $False, $kwargs)
    }

    [object] flexible_new($index, $kwargs)
    {
        return $this._new($index, $True, $kwargs)
    }
    [object] _new($index, $add, $kwargs)
    {
        if ($index -eq $null -and -not $this._index_helper.has_indexes())
        {
            throw [System.Exception], 'no more entries in array'
        }
        $entry = $this._cls($this, $this._loading_from_scp)
        foreach ($i in $kwargs)
        {
            if ($i -notin $entry.__dict__ -and $add)
            {
                if ($kwargs[$i].GetType() -eq [int])
                {
                    $entry[$i] = [IntField]::new(0, $this)
                }
                else
                {
                    $entry[$i] = [StringField]("", $this)
                }
            }
            $entry.__setattr__($i, $kwargs[$i])
        }
        if ($index -eq $null -and $this._get_key($entry) -eq $null)
        {
            throw [System.Exception], 'key not provided'
        }
        $key = $this._get_key($entry)
        if ($index -eq $null -and ($key -and $key -in $this._keys))
        {
            throw [System.Exception], ($this._cls +" key "+$key +' already exists')
        }

        if ($index -eq $null)
        {
            $index = $this._index_helper.next_index()
        }
        else
        {
            $index = [int]$index
        }
        $entry._set_index($index)
        $this._entries.append($entry)
        $this._keys[$key] = $entry
        $this._sort()

        # set state!
        if ($this._state -in @([TypeState]::UnInitialized, [TypeState]::Initializing))
        {
            $this._state = [TypeState]::Initializing
        }
        elseif ($this._state -in @([TypeState]::Committed, [TypeState]::Changing))
        {
            if ($this._values_changed($this._entries, $this.__dict__['_orig_value']))
            {
                $this._state = [TypeState]::Committed
            }
            else
            {
                $this._state = [TypeState]::Changing
            }
        }
        else
        {
            write-host("Should not come here")
        }
        if ($this.is_changed() -and $this._parent -eq $null)
        {
            $this._parent.child_state_changed($this, $this._state)
        }
        return $entry
    }

    [bool] _clear_duplicates()
    {
        $keys = @{}
        $toremove = [System.Collections.ArrayList]::new()

        foreach ($entry in $this._entries)
        {
            $strkey = $this._get_key($entry)
            if ($strkey -eq $null)
            {
                $toremove.Add($entry)
            }
            elseif ($strkey -in @("", "()"))
            {
                $toremove.Add($entry)
            }
            elseif ($strkey -in $keys)
            {
                $toremove.Add($entry)
            }
            $keys[$strkey] = $entry
        }

        foreach ($entry in $toremove)
        {
            $this._entries.remove($entry)
            $this._index_helper.restore_index($entry._index)
            $strkey = $this._get_key($entry)
            if ($strkey -in $this._keys)
            {
                $this._keys.Remove($strkey)
            }
        }

        foreach ($entry in $this._entries)
        {
            $this._index_helper.remove($entry._index)
        }
        $this._sort()
        return $True
    }

    # returns a list
    [System.Collections.ArrayList] find($kwargs)
    {
        return $this._find($True, $kwargs)
    }
    # returns the first entry
    [object] find_first($kwargs)
    {
        $entries = $this._find($False, $kwargs)
        if ($entries.Length -gt 0)
        {
            return $entries[0]
        }
        return $null
    }

    [object] entry_at($index)
    {
        foreach ($entry in $this._entries)
        {
            if ($entry._index -eq $index)
            {
                return $entry
            }
        }
        return $null
    }

    [object] find_or_create($index=$null)
    {
        if ($index -ne $null)
        {
            $index = $this._index_helper.next_index()
        }
        else
        {
            $this._index_helper.remove($index)
        }
        foreach ($entry in $this._entries)
        {
            if ($entry._index -eq $index)
            {
                return $entry
            }
        }
        return $this.new($index)
    }

    [object] remove($kwargs)
    {
        $entries = $this._find($True, $kwargs)
        return $this._remove_selected($entries)
    }

    [object] remove_matching($criteria)
    {
        $entries = $this.find_matching($criteria)
        return $this._remove_selected($entries)
    }

    [object] _remove_selected($entries)
    {
        if ($entries.Length -le 0)
        {
            return $entries
        }

        foreach ($i in $entries)
        {
            $this._entries.remove($i)
            $this._index_helper.restore_index($i._index)
            $key = $this._get_key($i)
            if ($key -in $this._keys)
            {
                $this._keys.Remove($key)
            }
        }
        $this._sort()

        if ($this._state -in @([TypeState]::UnInitialized, [TypeState]::Precommit, [TypeState]::Initializing))
        {
            $this._state = [TypeState]::Initializing
        }
        elseif ($this._state -in @([TypeState]::Committed, [TypeState]::Changing))
        {
            if ($this._values_changed($this._entries, $this._orig_value))
            {
                $this._state = [TypeState]::Committed
            }
            else
            {
                $this._state = [TypeState]::Changing
            }
        }
        else
        {
            write-host("Should not come here")
        }

        if ($this.is_changed() -and $this._parent -ne $null)
        {
            $this._parent.child_state_changed($this, $this._state)
        }
        return entries
    }

    [void] _sort()
    {
    #    $this._entries = sorted($this._entries, key = lambda entry: entry._index)
    }

    [System.Collections.ArrayList] _find($all_entries, $kwargs)
    {
        $output = [System.Collections.ArrayList]::new()
        foreach ($entry in $this._entries)
        {
            $found = $True
            foreach ($field in $kwargs)
            {
                if ($entry.($field).Value -ne $kwargs[$field])
                {
                    $found = $False
                    break
                }
                if ($entry._attribs[$field] -ne $kwargs[$field])
                {
                    $found = $False
                    break
                }
            }
            if ($found)
            {
                $output.append($entry)
                if (-not $all_entries) { break}
            }
        }
        return $output
    }

    [System.Collections.ArrayList] find_matching($criteria)
    {
        $output = [System.Collections.ArrayList]::new()
        foreach ($entry in $this._entries)
        {
            if ($this.select_entry($entry, $criteria))
            {
                $output.Add($entry)
            }
        }
        return $output
    }

    
    [string] Properties()
    {
        return $this._entries
    }

    [string] Json()
    {
        $output = @()
        foreach ($entry in $this._entries)
        {
            $output.append($entry.Json())
        }
        return $output
    }


    [string] XML()
    {
        return $this._get_xml_string($True, '', $False)
    }

    [string] ModifiedXML()
    {
        return $this._get_xml_string($False, '', $False)
    }

    [string] _get_xml_string($everything, $space, $deleted)
    {
        $s = [System.IO.StringWriter]::new()
        foreach ($entry in $this._entries)
        {
            if ($entry.is_changed() -eq $False -and -not $everything)
            {
                continue
            }
            $s.WriteLine($entry._get_xml_string($everything, $space, $False))
        }
        foreach ($entry in $this.values_deleted())
        {
            $s.WriteLine($entry._get_xml_string($True, $space, $True))
        }
        return $s.getvalue()
    }

    [string] select_entry($entry, $criteria)
    {
        if ($criteria.Contains('$this.'))
        {
            write-host ("criteria cannot have self references!")
            return $False
        }
        $criteria = $criteria.Replace('.parent', '._parent._parent')
        $criteria = $criteria -replace '([a-zA-Z0-9_.]+)\s+is\s+([^ \t]+)', '(type(\\1).__name__ == "\\2")'
        write-host("Evaluating: " + $criteria)
        return eval($criteria)
    }

}

### DONE



# Generated Code
$BootModeTypes = [EnumType]::new('BootModeTypes', @{ Uefi = "Uefi"; Bios = "Bios"; None = "None" })
$Levels = [EnumType]::new('Levels', @{ Administrator = "511"; Operator = "411"; User = "1" })


class BIOS : ClassType {
    [FieldType]$BootMode
    [FieldType]$BootSeq
    [FieldType]$MemTest

    BIOS($loading_from_scp)
    {
        $this.BootMode = [EnumTypeField]::new($Global:BootModeTypes, $null, @{ RebootRequired = $True })
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

try {
$t = [SystemConfiguration]::new($False)
$t1 = [IntField]::new(40, @{})
$t.BIOS.BootMode.Value = 'Bios'
$t.iDRAC.Time.DayLightOffset_Time.Value = $t1
$t.iDRAC.Time.Time_Time.Value = "10"
$t.iDRAC.Time.Timezone_Time.Value = 'CDT'
#write-host ($t.iDRAC.Time.Timezone_Time)
write-host ($t.iDRAC.Time.Timezones.OptimalValue)
}
catch 
{
    $ex = $_.Exception
    $orig_ex = $ex
    while ($ex -ne $null)
    {
        write-host ($ex.Message)
        write-host ($ex.ErrorRecord.InvocationInfo.PositionMessage)
        $ex = $ex.InnerException
        if ($ex -ne $null)
        {
            write-host("Inner Exception Details:")
        }
    }
}
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
