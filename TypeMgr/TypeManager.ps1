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
cd C:\Users\vaideeswaran_ganesan\work\OMSDKPowerShell

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
    hidden $_fname

    [bool] my_accept_value($value)
    {
        return $true
    }

    [object] _do_json($modified_only)
    {
        return $null
    }

    [string] Json()
    {
        $s = [System.IO.StringWriter]::new()
        $tree = $this._do_json($false)
        $this.format($tree, $s, "")
        return $s.ToString()
    }

    [string] ModifiedJson()
    {
        $s = [System.IO.StringWriter]::new()
        $tree = $this._do_json($True)
        $this.format($tree, $s, "")
        return $s.ToString()
    }

    [void] format($tree, $s, $level)
    {
        $increment = "    "
        if ($tree -is [hashtable])
        {
            $start = "{"
            $end = "}"
            $s.Write($start)

            $comma = ""
            foreach ($e in $tree.Keys)
            {
                $s.WriteLine($comma)
                $s.Write($level + $increment)
                $s.Write('"{0}" : ' -f $e)
                if ($tree[$e] -is [hashtable])
                {
                    $this.format($tree[$e], $s, $level + $increment)
                }
                elseif ($tree[$e] -is [System.Collections.ArrayList])
                {
                    $this.format($tree[$e], $s, $level + $increment)
                }
                else
                {
                    $s.Write('"{0}"' -f $tree[$e])
                }
                $comma = ","
            }
            $s.WriteLine()
            $s.Write($level + $end)
        }
        elseif ($tree -is [System.Collections.ArrayList])
        {
            $start = "["
            $end = "]"
            $s.Write($start)

            $comma = ""
            foreach ($e in $tree)
            {
                $s.WriteLine($comma)
                $s.Write($level + $increment)
                if ($e -is [hashtable])
                {
                    $this.format($e, $s, $level + $increment)
                }
                elseif ($e -is [System.Collections.ArrayList])
                {
                    $this.format($e, $s, $level + $increment)
                }
                else
                {
                    $s.Write('"{0}"' -f $e)
                }
                $comma = ","
            }
            $s.WriteLine()
            $s.Write($level + $end)
        }
        else
        {
            $s.Write($level + $tree)
        }
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

class FieldType : TypeBase, System.Icomparable
{
    # FieldType:: TODO
    # 1. _orig_value and _state should not be allowed for modify outside typemgr
    # 2. How to freeze and unfreeze objects for accidental modification?
    # 3. Comparision Operations - [Workaround: Added CompareTo() and __xx__() APIs]

    FieldType($type, $init_value, $properties)
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
            elseif ($value -eq [System.Management.Automation.Language.NullString]::Value)
            {
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
                        $msg = "Enum Value {0} does not exist in Enumeration {1}" -f $value, $this.enumtype
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
                $this._parent.child_state_changed($this, $this._state)
            }
            #write-host("done.....")
        })

        $this._value = $init_value
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
        if ($properties.ContainsKey('Alias'))
        {
            $this._alias = $properties.Alias
        }
        if ($properties.ContainsKey('FieldName'))
        {
            $this._fname = $properties.FieldName
        }
        if ($properties.ContainsKey('Volatile') -and $properties.Volatile -eq $true)
        {
            $this._volatile = $True
        }
        if ($properties.ContainsKey('Parent'))
        {
            $this._parent = $properties.Parent
        }
        if ($properties.ContainsKey('Index'))
        {
            $this._index = $properties.Index
        }
        if ($properties.ContainsKey('DefaultOnDelete'))
        {
            $this._default_on_delete = $properties.DefaultOnDelete
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

    [bool] isNullOrEmpty()
    {
        return ($this.Value -eq $null -or $this.Value -eq '')
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
    [bool] commit($LoadingFromSCP)
    {
        if ($this.is_changed() -or $this._state -eq [TypeState]::Precommit)
        {
            if ($this._composite -eq $False)
            {
                $this._orig_value = $this._value
            }
            if ($LoadingFromSCP)
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
       return [string]$this.Value
    }

    [object] _do_json($modified_only)
    {
       return [string]$this.value
    }

    [int] CompareTo($other)
    {
        if ($this._state -eq [TypeState]::UnInitialized)
        {
            return ($other -ne $null)
        }
        if ($this.Value -eq $null -and $other -eq $null)
        {
            return 0
        }
        if ($this.Value -eq $null -and $other -ne $null)
        {
            return -1
        }
        if ($this.Value -ne $null -and $other -eq $null)
        {
            return 1
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
            return 0
        }
        if ($myvalue -eq $null -and $othervalue -ne $null)
        {
            return -1
        }
        if ($myvalue -ne $null -and $othervalue -eq $null)
        {
            return 1
        }
        return $myvalue.CompareTo($othervalue)
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
    # 3. Comparision Operations -??
    hidden $_attribs
    hidden $_ign_attribs
    hidden $_ign_fields
    hidden $_valid_exprs

    ClassType($properties)
    {
        if ($properties.ContainsKey('Parent'))
        {
            $this._parent = $properties.Parent
        }
        $this._attribs = @{}
        $this._valid_exprs = [System.Collections.ArrayList]::new()
    }
    
    [void] __setattr__($name, $value)
    {
        #write-host ("set {0}={1}| {2}" -f $name, $value, $this.($name))
        if ($this.($name) -eq $null)
        {
            $this | Add-Member -Name $name -Value ([StringField]::new($null, @{Parent=$this})) -MemberType NoteProperty
        }
        $this.($name).Value = $value
    }

    [void] __addattr__($properties)
    {
        foreach ($prop in $properties.Keys)
        {
            $this | Add-Member -Name $prop -Value $properties[$prop] -MemberType NoteProperty
        }
    }

    [bool] hasattr($t, $name)
    {
        return $null -ne (Get-Member -InputObject $t -Name $name)
    }

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
        return $this._state -in @([TypeState]::UnInitialized, [TypeState]::Initializing, [TypeState]::Precommit, [TypeState]::Changing)
    }

    [void] add_valid_expression($name, $expression)
    {
        $this.add_valid_expression($name, '$true', $expression)
    }
    [void] add_valid_expression($name, $prelim, $expression)
    {
        $this._valid_exprs.Add(@{$name = @{ PrelimCondition = $prelim; Expression =$expression }})
    }

    [bool] is_valid()
    {
        $retval = $True
        foreach ($field in Get-Member -InputObject $this -MemberType Property,NoteProperty)
        {
            $s1 = $this.($field.Name)
            if ($s1 -is [ClassType] -and $s1.is_valid() -eq $False)
            {
                return $false
            }
        }
        return $this._check_valid('One', [System.Collections.ArrayList]::new())
    }

    [bool] check_all_rules()
    {
        $retval = $True
        foreach ($field in Get-Member -InputObject $this -MemberType Property,NoteProperty)
        {
            $s1 = $this.($field.Name)
            if ($s1 -is [ClassType] -and $s1.check_all_rules() -eq $False)
            {
                $retval = $false
            }
        }
        return $this._check_valid('All', [System.Collections.ArrayList]::new()) -and $retval
    }

    [System.Collections.ArrayList] get_failed_rules()
    {
        $errors = [System.Collections.ArrayList]::new()
        $this._get_failed_rules($errors)
        return $errors
    }
    [void] _get_failed_rules($errors)
    {
        foreach ($field in Get-Member -InputObject $this -MemberType Property,NoteProperty)
        {
            $s1 = $this.($field.Name)
            if ($s1 -is [ClassType])
            {
                $s1._get_failed_rules($errors)
            }
        }
        $this._check_valid('All', $errors)
    }

    [bool] _check_valid($scope, $errors)
    {
        $returnValue = $True
        foreach ($valid_expr in $this._valid_exprs)
        {  
            foreach ($expr in $valid_expr.Keys)
            {
                $result = Invoke-Expression $valid_expr[$expr]['PrelimCondition']
                if ($result -eq $False)
                {
                    continue
                }
                $result = Invoke-Expression $valid_expr[$expr]['Expression']
                if ($result -eq $False)
                {
                    $returnValue = $False
                    $errors.Add(@{ $expr = $valid_expr[$expr] })
                    if ($scope -eq 'One')
                    {
                        return $returnValue
                    }
                }
            }
        }
        return $returnValue
    }

    [object] _do_json($modified_only)
    {
        $a = @{}
        foreach ($field in Get-Member -InputObject $this -MemberType Property,NoteProperty)
        {
            $s1 = $this.($field.Name)
            if ($modified_only -and ($s1 -eq $null -or $s1.is_changed() -eq $False))
            {
                continue
            }
            if ($s1 -isnot [CompositeField])
            {
                $a[$field.Name] = $s1._do_json($modified_only)
            }
       }
       return $a
    }

    [bool] commit()
    {
        return $this.commit($False)
    }

    [bool] commit($LoadingFromSCP)
    {
        if ($this.is_changed())
        {
            if ($this._composite -eq $False)
            {
                foreach ($prop in $this.Properties())
                {
                    $this.($prop.Name).commit($LoadingFromSCP)
                }
            }
            if ($LoadingFromSCP)
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

    [bool] reject() 
    {
       if ($this.is_changed())
       {
            if ($this._composite -eq $False)
            {
                foreach ($prop in $this.Properties())
                {
                    $this.($prop.Name).reject()
                }
                $this._state = [TypeState]::Committed
            }
        }
        return $True
    }

    [void]child_state_changed($obj, $obj_state)
    {
        if ($obj_state -in @([TypeState]::Initializing, [TypeState]::Precommit, [TypeState]::Changing))
        {
            if ($this._state -in @([TypeState]::UnInitialized, [TypeState]::Precommit))
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

    [void]parent_state_changed($new_state)
    {
    }

    [System.Collections.ArrayList] Properties()
    {
        $ret = [System.Collections.ArrayList]::new()
        foreach ($field in Get-Member -InputObject $this -MemberType Property,NoteProperty)
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
            if ($this.($prop.Name).reboot_required()) {
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
            $this.($prop.Name).freeze()
       }
    }
    [void] unfreeze()
    {
        $this._freeze = $False
        foreach ($prop in $this.Properties())
        {
            $this.($prop.Name).unfreeze()
       }
    }

    [bool] is_frozen()
    {
        return $this._freeze
    }

    [void] _set_index($index)
    {
       $this._index = $index
       foreach ($prop in $this.Properties())
       {
            $this.($prop.Name)._index = $index
       }
    }

    [TypeBase] get_root()
    {
        if ($this._parent -eq $null)
        {
            return $this
        }
        return $this._parent.get_root()
    }

    [void] add_attribute($name, $value)
    {
        $this._attribs[$name] = $value
    }

    [void] _clear_duplicates()
    {
        foreach ($prop in $this.Properties())
        {
            if ($this.($prop.Name) -isnot [FieldType])
            {
                $this.($prop.Name)._clear_duplicates()
            }
        }
    }

    [System.Collections.ArrayList] find_matching($criteria)
    {
        $output = [System.Collections.ArrayList]::new()
        foreach ($entry in $this.Properties())
        {
            if ($this.($entry.Name).select_entry($criteria) -eq $true)
            {
                $output.Add($this.($entry.Name))
            }
        }
        return $output
    }

    [System.Collections.ArrayList] find_all_matching($criteria)
    {
        $output = [System.Collections.ArrayList]::new()
        $this._find_all_matching($criteria, $output)
        return $output
    }

    [void] _find_all_matching($criteria, $output)
    {
        foreach ($entry in $this.Properties())
        {
            if ($this.($entry.Name) -is [FieldType])
            {
                continue
            }
            if ($this.($entry.Name).select_entry($criteria) -eq $true)
            {
                $output.Add($this.($entry.Name))
            }
            $this.($entry.Name)._find_all_matching($criteria, $output)
        }
    }

    [object] select_entry($criteria)
    {
        $criteria = $criteria.Replace('.parent', '._parent._parent')
        $criteria = $criteria -replace '([a-zA-Z0-9_.]+)\s+is\s+([^ \t]+)', '${1} -is [${2}]'
        return Invoke-Expression ($criteria)
    }
}

class RootClassType : ClassType 
{
    RootClassType($properties): base($properties) 
    {}
}


class IndexHelper
{
    hidden $min_value
    hidden $max_value
    hidden $indexes_free
    hidden $reserve
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
            $this.indexes_free.Sort()
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

# TODO: ArrayType.new() is not updating the parent class

class ArrayType : TypeBase
{
    hidden [System.Collections.ArrayList]$_entries
    hidden $_keys
    hidden $_cls
    hidden $_index_helper
    hidden $_LoadingFromSCP

    ArrayType($clsname)
    {
        $this._init($clsname, $null, $null, $False)
    }

    ArrayType($clsname, $parent, $index_helper, $LoadingFromSCP)
    {
        $this._init($clsname, $parent, $index_helper, $LoadingFromSCP)
    }
    [void] _init($clsname, $parent, $index_helper, $LoadingFromSCP)
    {
        $this._fname = $clsname.Name
        $this._parent = $parent
        $this._LoadingFromSCP = $LoadingFromSCP
        if ($index_helper -eq $null)
        {
            $index_helper = [IndexHelper]::new(1, 30)
        }
        $this._index_helper = $index_helper
        $this._cls = $clsname
        $this._entries = [System.Collections.ArrayList]::new()
        $this._keys = @{}
        # Special case for Array. Empty Array is still valid
        $this._orig_value = [System.Collections.ArrayList]::new()
        $this._state = [TypeState]::Committed
    }

    [bool] hasattr($t, $name)
    {
        return $null -ne (Get-Member -InputObject $t -Name $name)
    }

    [int] Length()
    {
        return $this._entries.Length
    }


    [object] _get_key($entry)
    {
        if ($this.hasattr($entry, 'Key'))
        {
            $key = $entry.Key()
            if ($key -ne $null) { $key = $key.ToString() }
            return $key
        }
        else
        {
            return $entry._index
        }
    }

    [bool] _copy_state($source, $dest)
    {
        $source_entries = @{}
        $dest_entries = @{}
        foreach ($i in $source)
        {
            $source_entries[$i._index] = $i
        }
        foreach ($i in $dest)
        {
            $dest_entries[$i._index] = $i
        }
        # from _entries to _orig_entries
        $toadd = [System.Collections.ArrayList]::new()
        foreach ($i in $source_entries.Keys)
        {
            if ($dest_entries.ContainsKey($i) -eq $False)
            {
                $toadd.Add($source_entries[$i])
            }
        }

        $toremove = [System.Collections.ArrayList]::new()
        foreach ($i in $dest_entries.Keys)
        {
            if ($source_entries.ContainsKey($i) -eq $False)
            {
                $toremove.Add($dest_entries[$i])
            }
        }

        write-host($dest.count)
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

    # State : to Committed
    # allowed even during freeze
    [bool] commit()
    {
        return $this.commit($False)
    }

    [bool] commit($LoadingFromSCP)
    {
        if ($this.is_changed())
        {
            if ($this._composite -eq $False)
            {
                $this._copy_state($this._entries, $this._orig_value)
                foreach ($entry in $this._entries)
                {
                    $this._index_helper.remove($entry._index)
                    $entry.commit($LoadingFromSCP)
                }
            }
            if ($LoadingFromSCP)
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
            if ($this._composite -eq $false)
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
            $this.($prop.Name).freeze()
       }
    }
    [void] unfreeze()
    {
        $this._freeze = $False
        foreach ($prop in $this.Properties())
        {
            $this.($prop.Name).unfreeze()
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
        $entry = $this._cls::new(@{Parent=$this; LoadingFromSCP=$this._LoadingFromSCP})
        $entry_dict = @{}
        foreach ($prop in $entry.Properties())
        {
            $entry_dict[$prop.Name] = $prop
        }
        foreach ($i in $kwargs.Keys)
        {
            if ($i -notin $entry_dict -and $add)
            {
                if ($kwargs[$i].GetType() -eq [int])
                {
                    $entry[$i].Value = [IntField]::new(0, @{Parent=$this})
                }
                else
                {
                    $entry[$i].Value = [StringField]("", $this)
                }
            }
            $entry.__setattr__($i, $kwargs[$i])
        }
        if ($index -eq $null -and $this._get_key($entry) -eq $null)
        {
            throw [System.Exception], 'key not provided'
        }
        $key = $this._get_key($entry)
        if ($index -eq $null -and ($key -eq $null -and $this._keys.ContainsKey($key)))
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
        $this._entries.Add($entry)
        $idxname = 'Index_' + $index

        Add-Member -InputObject $this -Name ("Index_"+$index) -MemberType NoteProperty -Value $entry -Force
        if ($key -ne $null)
        {
            $this._keys[$key] = $entry
        }

        # set state!
        if ($this._state -in @([TypeState]::UnInitialized, [TypeState]::Initializing))
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
            Add-Member -InputObject $this -Name ("Index_"+$entry._index) -MemberType NoteProperty -Value $null -Force
            $this._index_helper.restore_index($entry._index)
            $strkey = $this._get_key($entry)
            if ($this._keys.ContainsKey($strkey))
            {
                $this._keys.Remove($strkey)
            }
        }
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

    [object] find_or_create($index)
    {
        if ($index -eq $null)
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
        return $this.new($index, @{})
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
        if ($entries.Count -le 0)
        {
            return $entries
        }

        foreach ($entry in $entries)
        {
            $this._entries.remove($entry)
            Add-Member -InputObject $this -Name ("Index_"+$entry._index) -MemberType NoteProperty -Value $null -Force
            $this._index_helper.restore_index($entry._index)
            $strkey = $this._get_key($entry)
            if ($this._keys.ContainsKey($strkey))
            {
                $this._keys.Remove($strkey)
            }
        }

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
        return $entries
    }

    [System.Collections.ArrayList] _find($all_entries, $kwargs)
    {
        $output = [System.Collections.ArrayList]::new()
        foreach ($entry in $this._entries)
        {
            $found = $True
            foreach ($field in $kwargs.Keys)
            {
                if ($entry.($field).Value -eq $null)
                {
                    if ($kwargs[$field] -ne $null)
                    {
                        $found = $False
                        break
                    }
                }
                elseif ($entry.($field).Value -ne $kwargs[$field])
                {
                    $found = $False
                    break
                }
                if ($entry._attribs -ne $null -and $entry._attribs.ContainsKey($field) -and $entry._attribs[$field] -ne $kwargs[$field])
                {
                        $found = $False
                        break
                }
            }
            if ($found)
            {
                $output.Add($entry)
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
            if ($entry.select_entry($criteria) -eq $true)
            {
                $output.Add($entry)
            }
        }
        return $output
    }

    [System.Collections.ArrayList] find_all_matching($criteria)
    {
        $output = [System.Collections.ArrayList]::new()
        $this._find_all_matching($criteria, $output)
        return $output
    }

    [void] _find_all_matching($criteria, $output)
    {
        foreach ($entry in $this._entries)
        {
            if ($entry -is [FieldType])
            {
                continue
            }
            if ($entry.select_entry($criteria) -eq $true)
            {
                $output.Add($entry)
            }
            $entry._find_all_matching($criteria, $output)
        }
    }

    [object] select_entry($criteria)
    {
        $criteria = $criteria.Replace('.parent', '._parent._parent')
        $criteria = $criteria -replace '([a-zA-Z0-9_.]+)\s+is\s+([^ \t]+)', '${1} -is [${2}]'
        return Invoke-Expression ($criteria)
    }


    
    [string] Properties()
    {
        return $this._entries
    }

    [object] _do_json($modified_only)
    {
        $a = [System.Collections.ArrayList]::new()
        foreach ($entry in $this._entries)
        {
            if ($entry.is_changed() -eq $False -and $modified_only)
            {
                continue
            }
            $a.Add($entry._do_json($modified_only))
        }
        foreach ($entry in $this.values_deleted())
        {
            $a.Add($entry._do_json($modified_only))
        }
        return $a
    }

    [bool] _values_changed($source, $dest)
    {
        $source_idx = @{}
        foreach ($entry in $this._entries)
        {
            $source_idx[$entry._index] = $entry
        }
        foreach ($entry in $this._orig_value)
        {
            if ($source_idx.ContainsKey($entry._index) -eq $false)
            {
                return $False
            }
            $source_idx.Remove($entry._index)
        }
        return ($source_idx.Length -le 0)
    }

    [System.Collections.ArrayList] values_deleted()
    {
        $source_idx = @{}
        $dest_entries = [System.Collections.ArrayList]::new()
        foreach ($entry in $this._entries)
        {
            $source_idx[$entry._index] = $entry
        }
        foreach ($entry in $this._orig_value)
        {
            if ($source_idx.ContainsKey($entry._index) -eq $false)
            {
                $dest_entries.Add($entry)
                continue
            }
            $source_idx.Remove($entry._index)
        }
        return $dest_entries
    }
}


# Generated Code
$BootModeTypes = [EnumType]::new('BootModeTypes', @{ Uefi = "Uefi"; Bios = "Bios"; None = "None" })

$Privilege_UsersTypes = [EnumType]::new("Privilege_UsersTypes", @{
    "NoAccess" = "0"
    "Readonly" = "1"
    "Operator" = "499"
    "Administrator" = "511"
})
$IpmiLanPrivilege_UsersTypes = [EnumType]::new("IpmiLanPrivilege_UsersTypes", @{
    "Administrator" = "Administrator"
    "No_Access" = "No Access"
    "Operator" = "Operator"
    "User" = "User"
})
$IpmiSerialPrivilege_UsersTypes = [EnumType]::new("IpmiSerialPrivilege_UsersTypes", @{
    "Administrator" = "Administrator"
    "No_Access" = "No Access"
    "Operator" = "Operator"
    "User" = "User"
})
$ProtocolEnable_UsersTypes = [EnumType]::new("ProtocolEnable_UsersTypes", @{
    "Disabled" = "Disabled"
    "Enabled" = "Enabled"
})
$AuthenticationProtocol_UsersTypes = [EnumType]::new("AuthenticationProtocol_UsersTypes", @{
    "MD5" = "MD5"
    "SHA" = "SHA"
    "T_None" = "None"
})
$Enable_UsersTypes = [EnumType]::new("Enable_UsersTypes", @{
    "Disabled" = "Disabled"
    "Enabled" = "Enabled"
})
$PrivacyProtocol_UsersTypes = [EnumType]::new("PrivacyProtocol_UsersTypes", @{
    "AES" = "AES"
    "DES" = "DES"
    "T_None" = "None"
})
$SolEnable_UsersTypes = [EnumType]::new("SolEnable_UsersTypes", @{
    "Disabled" = "Disabled"
    "Enabled" = "Enabled"
})





$tzones = (Get-content 'timezones.json' | ConvertFrom-Json)
$tzones_dict = @{}
foreach ($tzone in Get-Member -MemberType NoteProperty -InputObject $tzones) 
{
    $tzones_dict[$tzone.Name] = $tzone.Name
}
$TimeZones = [EnumType]::new('TimeZones', $tzones_dict)

class BIOS : ClassType {
    BIOS($properties) : base($properties)
    {
        $this.__addattr__(@{
            BootMode = [EnumTypeField]::new($Global:BootModeTypes, $null, @{ RebootRequired = $True; Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP   })
            UefiBootSeq  = [StringField]::new($null, @{Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP  })
            BiosBootSeq  = [StringField]::new($null, @{Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP  })
            MemTest   = [StringField]::new($null, @{ Readonly = $True; Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP   })
        })
        $this.add_valid_expression("BiosValidRule", '$this.BootMode.Value -eq "Bios"', '-not $this.BiosBootSeq.isNullOrEmpty()') 
        $this.add_valid_expression("UefiValidRule", '$this.BootMode.Value -eq "Uefi"', '-not $this.UefiBootSeq.isNullOrEmpty()') 
        $this.add_valid_expression("BootModeValidRule", '-not $this.BootMode.isNullOrEmpty()') 
        $this.commit($properties.LoadingFromSCP)
    }
}

class Time: ClassType {
    Time($properties) : base($properties)
    {
        $this.__addattr__(@{
            DayLightOffset_Time = [IntField]::new($null, @{Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP   })
            TimeZoneAbbreviation_Time = [StringField]::new("", @{Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP   })
            TimeZoneOffset_Time = [IntField]::new($null, @{Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP   })
            Time_Time = [IntField]::new($null, @{Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP   })
            Timezone_Time = [EnumTypeField]::new($Global:TimeZones, $null, @{Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP   })
            Timezones = [CompositeField]::new($this, 
                [System.Collections.ArrayList]('DayLightOffset_Time', 'Time_Time', 'Timezone_Time'), @{Readonly=$true; Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP   })
        })
        $this._ignore_fields('DaylightOffset_Time')
        $this._ignore_fields('TimeZone_Time')
        $this.commit($properties.LoadingFromSCP)
    }
}



class Users : ClassType
{
    Users($properties) : base($properties)
    {
        $this.__addattr__(@{
            AuthenticationProtocol = [EnumTypeField]::new($Global:AuthenticationProtocol_UsersTypes, $null, @{ Parent = $this; LoadingFromSCP = $properties.LoadingFromSCP })
            # readonly attribute populated by iDRAC
            ETAG = [StringField]::new("", @{ Parent=$this; ReadOnly = $True; LoadingFromSCP = $properties.LoadingFromSCP  })
            Enable = [EnumTypeField]::new($Global:Enable_UsersTypes, $null, @{ Parent = $this; default_on_delete='Disabled'; LoadingFromSCP = $properties.LoadingFromSCP })
            IpmiLanPrivilege = [EnumTypeField]::new($Global:IpmiLanPrivilege_UsersTypes, $null, @{ Parent = $this; default_on_delete='Disabled'; LoadingFromSCP = $properties.LoadingFromSCP })
            IpmiSerialPrivilege = [EnumTypeField]::new($Global:IpmiSerialPrivilege_UsersTypes, $null, @{ Parent = $this; default_on_delete='Disabled'; LoadingFromSCP = $properties.LoadingFromSCP })
            Password = [StringField]::new("", @{ Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP  })
            PrivacyProtocol = [EnumTypeField]::new($Global:PrivacyProtocol_UsersTypes, $null, @{ Parent = $this; default_on_delete='Disabled'; LoadingFromSCP = $properties.LoadingFromSCP })
            Privilege = [EnumTypeField]::new($Global:Privilege_UsersTypes, $null, @{ Parent = $this; default_on_delete='Disabled'; LoadingFromSCP = $properties.LoadingFromSCP })
            ProtocolEnable = [EnumTypeField]::new($Global:ProtocolEnable_UsersTypes, $null, @{ Parent = $this; default_on_delete='Disabled'; LoadingFromSCP = $properties.LoadingFromSCP })
            SolEnable = [EnumTypeField]::new($Global:SolEnable_UsersTypes, $null, @{ Parent = $this; default_on_delete='Disabled'; LoadingFromSCP = $properties.LoadingFromSCP })
            UserName  = [StringField]::new("", @{ Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP  })
            #MD5v3Key = [StringField]::new("", @{ Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP  })
            #IPMIKey = [StringField]::new("", @{ Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP  })
            #SHA1v3Key = [StringField]::new("", @{ Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP  })
            #SHA256PasswordSalt = [StringField]::new("", @{ Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP  })
            #SHA256Password = [StringField]::new("", @{ Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP  })
            #UserPayloadAccess = [StringField]::new("", @{ Parent=$this;LoadingFromSCP = $properties.LoadingFromSCP  })
        })
        $this.commit($properties.LoadingFromSCP)
    }

    [object] Key()
    {
        return $this.UserName.Value
    }

    [int] Index()
    {
        return $this._index
    }
}

class iDRAC : ClassType {

    iDRAC($properties) : base($properties)
    {
        $this.__addattr__(@{
            Time = [Time]::new(@{Parent = $this; LoadingFromSCP = $properties.LoadingFromSCP})
            Users = [ArrayType]::new([Users], $this, [IndexHelper]::new(1, 16), @{Parent = $this; LoadingFromSCP = $properties.LoadingFromSCP})
        })
        $this.commit($properties.LoadingFromSCP)
    }
}

class SystemConfiguration : RootClassType {
    SystemConfiguration($LoadingFromSCP) : base(@{Parent=$null; LoadingFromSCP=$LoadingFromSCP})
    {
        $this.__addattr__(@{
            BIOS = [BIOS]::new(@{Parent = $this; LoadingFromSCP = $LoadingFromSCP})
            iDRAC = [iDRAC]::new(@{Parent = $this; LoadingFromSCP = $LoadingFromSCP})
        })
        $this.commit($LoadingFromSCP)
    }
}

#$s.iDRAC.Users.find_matching('$this.Privilege.Value -eq "511"') | select UserName
#$s.iDRAC.Users.find_matching('$this.UserName.Value -match "vaidees"') | select UserName
#$sysconfig.select_entry('$this.iDRAC._attribs.FQDD -eq "iDRAC.Embedded.1"')
#$sysconfig.find_all_matching('$this.UserName.Value -match "vv"')