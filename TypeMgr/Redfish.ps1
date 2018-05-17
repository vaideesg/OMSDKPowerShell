


class RFieldType {
    hidden $RESTRootService
    hidden $RESTResourcePath
    hidden $RESTInternalObject
    hidden $Credential
    RFieldType($RESTRootService, $RESTResourcePath, $Credential)
    {
        $this.RESTRootService = $RESTRootService
        $this.RESTResourcePath = $RESTResourcePath
        $this.RESTInternalObject = $null
        $this.Credential = $Credential
    }

    hidden [void] InitializeRecurse()
    {
        $this.InitializeSelf()
        foreach ($member in Get-Member -MemberType NoteProperty -InputObject $this)
        {
            if ($this.$($member.Name) -is [RFieldType])
            {
                $this.$($member.Name).InitializeRecurse()
            }
        }
    }


    hidden [void] InitializeSelf()
    {
        if ($this.RESTResourcePath -eq $null -or $this.RESTResourcePath -eq '')
        {
            return
        }
        write-host -Object ($this.RESTRootService + $this.RESTResourcePath)
        if ($this.Credential -eq $null)
        {
            $this.RESTInternalObject = Invoke-RestMethod -Uri ($this.RESTRootService + $this.RESTResourcePath)
        }
        else
        {
            $this.RESTInternalObject = Invoke-RestMethod -Uri ($this.RESTRootService + $this.RESTResourcePath) -Credential $this.Credential
        }
        $memlist = Get-member -type NoteProperty -InputObject $this.RESTInternalObject | where { $_.Name -notin @(
            'UUID', 'Links', 'JsonSchemas', 'RelatedItem') } | where { $_.Name -notmatch '@odata' } 
        $memlist | foreach -Process {
            $obj_ent = $this.RESTInternalObject.$($_.Name)
            if (($obj_ent -is [PSCustomObject] -or $obj_ent -is [System.Array]) -and $_.Name -ne 'Oem')
            {
                $new_uri = $this.RESTInternalObject.$($_.Name)."@odata.id"
                if ($new_uri -isnot [System.Array]) {
                    Add-Member -InputObject $this -MemberType NoteProperty -Name $_.Name -Value ([RFieldType]::new($this.RESTRootService,$new_uri, $this.Credential))
                } else {
                    $name = $_.Name
                    $counter = 1
                    foreach ($path in $new_uri)
                    {
                        $name1 = $name + [string]$counter
                        Add-Member -InputObject $this -MemberType NoteProperty -Name $name1 -Value ([RFieldType]::new($this.RESTRootService,$path, $this.Credential))
                        $counter++
                    }
                }
            }
            else
            {
                Add-Member -InputObject $this -MemberType NoteProperty -Name $_.Name -Value $obj_ent
            }
        }
    }


    hidden [void] Print($Printer, $Level="")
    {

        Get-Member -type NoteProperty -inputobject $this| foreach -Process {
            $myobj = $this.$($_.Name)
            if ($myobj -isnot [RFieldType]) 
            {
                $Printer.PrintAttribute($Level, $_.Name, [string]$myobj)
            }
        }
        Get-Member -type NoteProperty -inputobject $this| foreach -Process {
            $myobj = $this.$($_.Name)
            if ($myobj -is [RFieldType]) 
            {
                $Printer.PrintBegin($Level, $_.Name)
                $myobj.Print($Printer, $Level + "    ")
                $Printer.PrintEnd($Level, $_.Name)
            }
        }
    }

    hidden [void]_FindVariablesRecurse($fieldList, [ref]$vals)
    {
        Get-Member -type NoteProperty -inputobject $this| foreach -Process {
            $found = $false
            $currentField = $_
            foreach ($field in $fieldList.Keys)
            {
                if ($this.RESTInternalObject.'@odata.context' -match $field -and $currentField.Name -in $fieldList[$field])
                {
                    $found = $true
                }
            }
            if ($found -eq $true) 
            {
                $myobj = $this.$($_.Name)
                if ($myobj -isnot [RFieldType])
                {
                    $vals.Value.Add($this.RESTInternalObject.'@odata.id' + "::" + $_.Name, [ref]$myobj)
                }
            }
        }
        Get-Member -type NoteProperty -inputobject $this| foreach -Process {
            $myobj = $this.$($_.Name)
            if ($myobj -is [RFieldType]) 
            {
                $myobj._FindVariablesRecurse($flist, $vals)
            }
        }
    }

}

class XMLPrinter 
{
    [void] PrintBegin($level, $attribute)
    {
        write-host -InputObject ("{0}<{1}>" -f $level, $attribute)
    }

    [void] PrintAttribute($level, $attribute, $value)
    {
        write-host -InputObject ("{0}<{1}>{2}</{1}>" -f $level, $attribute, $value)
    }

    [void] PrintEnd($level, $attribute)
    {
        write-host -InputObject ("{0}</{1}>" -f $level, $attribute)
    }
}

class StdOutPrinter 
{
    [void] PrintBegin($level, $attribute)
    {
        write-host ("{0}+-- {1}" -f $level, $attribute)
    }

    [void] PrintAttribute($level, $attribute, $value)
    {
        write-host ("{0}{1}={2}" -f $level, $attribute, $value)
    }

    [void] PrintEnd($level, $attribute)
    {
    }
}

class DeviceModel {
    hidden $RESTRootService
    $Device

    DeviceModel($RESTRootService, $Credential)
    {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::TLS12

        $this.RESTRootService = $RESTRootService
        $this.Device = [RFieldType]::new($this.RESTRootService, "/redfish/v1", $Credential)
        $this.InitializeSelf()
    }

    hidden [void] Print()
    {
        $Printer = [StdOutPrinter]::new()
        #$Printer = [XMLPrinter]::new()
        $Printer.PrintBegin("", 'Device')
        $this.Device.Print($Printer, "  ")
        $Printer.PrintEnd("", 'Device')
    }

    hidden [void] FindInsightVariables($vals)
    {
        $flist = @{ 
            'AccountService' = @('AccountLockoutThreshold', 'AccountLockoutCounterResetAfter')
            'ManagerAccount' = @('Id')
        }

        $this.Device._FindVariablesRecurse($flist, [ref]$vals)
    }

    hidden [void] InitializeSelf()
    {
        $this.Device.InitializeSelf()
        $this.Device.AccountService.InitializeRecurse()
        if ($true)
        {
        $this.Device.Chassis.InitializeSelf()
        
        if ($this.Device.Managers -ne $null)
        {
            $this.Device.Managers.InitializeSelf()
            $this.Device.Managers.Members.InitializeSelf()
            $this.Device.Managers.Members.EthernetInterfaces.InitializeRecurse()
            #$this.Device.Managers.Members.NetworkProtocol.InitializeRecurse()
        }
        if ($this.Device.Systems -ne $null)
        {
            $this.Device.Systems.InitializeSelf()
        }
        if ($this.Device.Systems.Members -ne $null)
        {
            $this.Device.Systems.Members.InitializeSelf()
            if ($this.Device.Systems.Members.Storage -ne $null)
            {
                $this.Device.Systems.Members.Storage.InitializeRecurse()
            }
            if ($this.Device.Systems.Members.SimpleStorage -ne $null)
            {
                $this.Device.Systems.Members.SimpleStorage.InitializeRecurse()
            }
            if ($this.Device.Systems.Members.Processors -ne $null)
            {
                $this.Device.Systems.Members.Processors.InitializeRecurse()
            }
            if ($this.Device.Systems.Members.ProcessorSummary -ne $null)
            {
                $this.Device.Systems.Members.ProcessorSummary.InitializeRecurse()
            }
            if ($this.Device.Systems.Members.MemorySummary -ne $null)
            {
                $this.Device.Systems.Members.MemorySummary.InitializeRecurse()
            }
        }
        }
    }
}




function Ignore-SSLCertificates
{
    $Provider = New-Object Microsoft.CSharp.CSharpCodeProvider
    $Compiler = $Provider.CreateCompiler()
    $Params = New-Object System.CodeDom.Compiler.CompilerParameters
    $Params.GenerateExecutable = $false
    $Params.GenerateInMemory = $true
    $Params.IncludeDebugInformation = $false
    $Params.ReferencedAssemblies.Add("System.DLL") > $null
    $TASource=@'
        namespace Local.ToolkitExtensions.Net.CertificatePolicy
        {
            public class TrustAll : System.Net.ICertificatePolicy
            {
                public bool CheckValidationResult(System.Net.ServicePoint sp,System.Security.Cryptography.X509Certificates.X509Certificate cert, System.Net.WebRequest req, int problem)
                {
                    return true;
                }
            }
        }
'@ 
    $TAResults=$Provider.CompileAssemblyFromSource($Params,$TASource)
    $TAAssembly=$TAResults.CompiledAssembly
    ## We create an instance of TrustAll and attach it to the ServicePointManager
    $TrustAll = $TAAssembly.CreateInstance("Local.ToolkitExtensions.Net.CertificatePolicy.TrustAll")
    [System.Net.ServicePointManager]::CertificatePolicy = $TrustAll
}

Ignore-SSLCertificates
$user = 'root'
$pass= 'calvin'
$secpasswd = ConvertTo-SecureString $pass -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential($user, $secpasswd)

write-host "Loading from HPE ilorestfulapiexplorer.ext.hpe.com ...."
$hp_device = [DeviceModel]::new("https://ilorestfulapiexplorer.ext.hpe.com", $null)
write-host "Loading from Dell 12G system ...."
$dell_device = [DeviceModel]::new("https://100.96.25.77", $Credential)
#$dell_device = [DeviceModel]::new("https://100.96.25.120", $Credential)
#$dell_device = [DeviceModel]::new("https://100.100.249.145", $Credential)
write-host "Loading from Dell Next Gen Modular Chassis (in devel)...."
$omem_device = [DeviceModel]::new("https://100.100.27.13", $Credential)
