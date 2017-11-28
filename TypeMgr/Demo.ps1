cd C:\Users\vaideeswaran_ganesan\Work\OMSDKPowerShell

Import-Module .\TypeMgr\TypeManager.ps1
Import-Module .\TypeMgr\Parser.ps1
Import-Module .\TypeMgr\Driver_iDRAC.ps1


$idrac = New-iDRAC-Session -IPOrHost '100.100.249.114' -Simulate

# Edit experience
$idrac.SystemConfiguration.iDRAC.Time.TimeZone_Time.Value ="something"

# Seameless experience
$idrac.SystemConfiguration.iDRAC.Time.TimeZone_Time.Value ="Africa/Abidjan"

# language-native validation
$idrac.SystemConfiguration.BIOS.BootMode.Value ="Uefi-none"
# valid value
$idrac.SystemConfiguration.BIOS.BootMode.Value ="Uefi"
# Reboot determined based on values added
$idrac.SystemConfiguration.reboot_required()
# validity check
$idrac.SystemConfiguration.is_valid()
$idrac.SystemConfiguration.get_failed_rules()

    Apply-iDRAC-Configuration -session $idrac
}
