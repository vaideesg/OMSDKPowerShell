cd C:\Users\vaideeswaran_ganesan\Work\OMSDKPowerShell

Import-Module .\TypeMgr\TypeManager.ps1
Import-Module .\TypeMgr\Parser.ps1


class Session
{
    hidden $IPOrHost
    hidden $creds
    hidden $simulate
    hidden $driver
    Session($driver, $IPOrHost, $creds, $simulate)
    {
        $this.driver = $driver
        $this.IPOrHost = $IPOrHost
        $this.creds = $creds
        $this.simulate = $simulate
    }

}

class iDRACDriver : Session
{
    $SystemConfiguration
    iDRACDriver($IPOrHost, $creds, $simulate) : base('iDRAC', $IPOrHost, $creds, $simulate)
    {
        $this.SystemConfiguration = $null
    }

    [bool] identify()
    {
        return $True
    }

    [bool] load_configuration()
    {
        if ($this.simulate)
        {
            $file = (".\simulator\{0}\config\config.xml" -f $this.IPOrHost)
            if (Test-Path $file)
            {
                write-host "Loading the server configuration"
                $scpparser = [SCPParser]::new('..\omsdk\omdrivers\{0}\Config\iDRAC.comp_spec' -f $this.driver)
                $this.SystemConfiguration = $scpparser.parse_scp($file)
                return $True
            }
        }
        return $False
    }
    [bool] apply_changes()
    {
        if ($this.simulate -and $this.SystemConfiguration -ne $null)
        {
            if ($this.SystemConfiguration.is_valid())
            {
                write-host $this.SystemConfiguration.ModifiedJson()
                return $True
            }
            else
            {
                write-host "iDRAC configuration is invalid.  Fix them and re-apply"
            }
        }
        return $False
    }
}

function Dump-Exception
{
    param($exp)
    $ex = $exp.Exception
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

function New-iDRAC-Session
{
    param(
        $IPOrHost,
        $Credentials,
        $LiasonShare,
        [switch]$Simulate
    )
    try {
        $a = [iDRACDriver]::new($IPOrHost, $Credentials, $Simulate)
        if ($a.identify() -and $a.load_configuration())
        {
            
            return $a
        }
        return $null
    }
    catch
    {
        Dump-Exception -exp $_
    }
}

function Apply-iDRAC-Configuration
{
    param($session)
    return $session.apply_changes()
}

function Load-iDRAC-Configuration
{
    param($session)
    return $session.load_configuration()
}



if ($False)
{
try {
$t = [SystemConfiguration]::new($False)
$t1 = [IntField]::new(40, @{})
$t.BIOS.BootMode.Value = 'Bios'
$t.iDRAC.Time.DayLightOffset_Time.Value = $t1
$t.iDRAC.Time.Time_Time.Value = "10"
$t.iDRAC.Time.Timezone_Time.Value = 'Asia/Calcutta'
#write-host ($t.iDRAC.Time.Timezone_Time)
write-host ($t.iDRAC.Time.Timezones.OptimalValue)
$t.iDRAC.Users.new(1, @{UserName='vaidees'; Password='vaidees123'})
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


$t1 = [t]::new(10)
$t2 = [t]::new(12)
}