﻿
# omdrivers\enums\
# omdrivers\types\
# omdrivers\lifecycle\idracconfig.py
# omdrivers\lifecycle\raidhelper.py
# omdrivers\idrac.py (partial_entity_json[storage])
cd C:\Users\vaideeswaran_ganesan\Work\OMSDKPowerShell
Import-Module .\TypeMgr\TypeManager.ps1
Import-Module .\TypeMgr\Parser.ps1

function New-iDRAC-Session
{
    param(
        $IPOrHost,
        $Credentials,
        $LiasonShare,
        [switch]$Simulate
    )
    if ($Simulate)
    {
        if (Test-Path ".\simulator\$IPOrHost\config\config.xml")
        {
            $scpparser = [SCPParser]::new('..\omsdk\omdrivers\iDRAC\Config\iDRAC.comp_spec')
            return $scpparser.parse_scp(".\simulator\$IPOrHost\config\config.xml")
        }
    }
    return $null
}

function Apply-iDRAC-Session
{
    param(
        $session,
        [switch]$Simulate
    )
    if ($Simulate)
    {
        $session.ModifiedJson()
    }
}


$idrac = New-iDRACSession -IPOrHost '100.100.249.114' -Simulate
$idrac.iDRAC.Time.TimeZone_Time.Value ="Africa/Abidjan"
Apply-iDRAC-Session -session $idrac -Simulate


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