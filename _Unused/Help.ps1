$name = "NIC"
$t = (Get-Content C:\users\vaideeswaran_ganesan\Work\omsdk\omdrivers\iDRAC\Config\${name}.json | ConvertFrom-Json)

$level = '    '
$class_def = [System.IO.StringWriter]::new()

$t.definitions | Get-Member -MemberType NoteProperty | ForEach-Object -Process {
    $class_def.WriteLine(('${0} = [EnumType]::new("{0}", @{{' -f $_.Name))
    ForEach ($i in $t.definitions.($_.Name).enum)
    {
        $class_def.WriteLine($level + "'{0}' = '{0}'" -f $i)
    }
    $class_def.WriteLine('})')
}

$class_def.WriteLine(('class {0} : ClassType {{' -f $name))
$class_def.WriteLine($level + '{0}($properties) : base($properties)' -f $name)
$class_def.WriteLine($level + '{')
$class_def.WriteLine($level + $level + '$this.__addattr__(@{')

$t.definitions.($name).properties | Get-Member -MemberType NoteProperty | ForEach-Object -Process {
    if ($_.Name -match '[[]Partition') { return }
    switch ($t.definitions.($name).properties.($_.Name).readonly -eq 'true')
    { $true { $readonly = '$True' } $false { $readonly = '$False' } }
    $reboot_required = '$False'
    $default = $t.definitions.($name).properties.($_.Name).default
    if ($default -eq $null)
    {
        $default = '$null'
    }
    else
    {
        $default = '"{0}"' -f $default
    }
    $class_def.Write($level + $level + $_.Name + ' = ')
    $baseType = $t.definitions.($name).properties.($_.Name).baseType
    $minValue = $t.definitions.($name).properties.($_.Name).min
    $maxValue = $t.definitions.($name).properties.($_.Name).max

    $enum_name = $_.Name.Trim()
    switch -Regex ($baseType)
    {
        'enum' { 
            $class_def.Write('[EnumTypeField]::new($Global:{0}Types, ' -f $enum_name)
        }
        'str' {
            $class_def.Write('[StringField]::new(')
        }
        'int' {
            $class_def.Write('[StringField]::new(')
        }
        'list' {
            $class_def.Write('[StringField]::new(')
        }
        '.*AddressField' {
            $class_def.Write('[{0}]::new(' -f $baseType)
        }
        'minmaxrange' {
            $class_def.Write(('[IntRangeField]::new({0}, {1}, ' -f $minValue, $maxValue))
        }
        default {
            write-host $baseType
        }
    }
    $class_def.Write('{0}, @{{' -f $default)
    $class_def.Write('RebootRequired={0}; ' -f $reboot_required)
    $class_def.Write('Readonly={0}; ' -f $readonly)
    $class_def.WriteLine('Parent=$this; LoadingFromSCP = $properties.LoadingFromSCP})')
}
$class_def.WriteLine($level + $level + '})')
$class_def.WriteLine($level + $level + '$this.commit($properties.LoadingFromSCP)')
$class_def.WriteLine($level + '}')
$class_def.WriteLine('}')

Invoke-Expression $class_def.ToString()

