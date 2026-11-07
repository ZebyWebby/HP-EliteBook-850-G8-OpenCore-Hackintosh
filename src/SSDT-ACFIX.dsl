/* usb-c charger state for macOS. hp's AC._PSR returns a cached value that only refreshes when the EC raises _Q06
   (barrel charger). usb-c plug and unplug raise _Q27 instead, which only feeds the windows ucsi driver, so macOS kept
   thinking the charger was connected.
   needs the ACPI patches _PSR to XPSR (DSDT) and _Q27 to XQ27 (SSDT UcsiAcpi). */
DefinitionBlock ("", "SSDT", 2, "CLAWD", "ACFIX", 0x00001000)
{
    External (_SB_.AC__, DeviceObj)
    External (_SB_.AC__.XPSR, MethodObj)
    External (_SB_.BAT0, DeviceObj)
    External (_SB_.PC00.LPCB.EC0_, DeviceObj)
    External (_SB_.PC00.LPCB.EC0_.PWUP, MethodObj)
    External (_SB_.PC00.LPCB.EC0_.XQ27, MethodObj)

    Scope (\_SB.AC)
    {
        Method (_PSR, 0, NotSerialized)
        {
            /* mark the cached AC state stale so the original method re-reads the EC */
            If (_OSI ("Darwin")) { \_SB.PC00.LPCB.EC0.PWUP (One, Zero) }
            Return (\_SB.AC.XPSR ())
        }
    }

    Scope (\_SB.PC00.LPCB.EC0)
    {
        Method (_Q27, 0, NotSerialized)
        {
            \_SB.PC00.LPCB.EC0.XQ27 ()
            If (_OSI ("Darwin"))
            {
                /* same as _Q06: AC and battery status stale for BAT0, then tell macOS */
                \_SB.PC00.LPCB.EC0.PWUP (0x05, One)
                Notify (\_SB.AC, 0x80)
                Notify (\_SB.BAT0, 0x80)
            }
        }
    }
}
