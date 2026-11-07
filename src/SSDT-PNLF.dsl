/* backlight device for the internal panel, under the Iris Xe at _SB.PC00.GFX0 */
DefinitionBlock ("", "SSDT", 2, "CLAWD", "PNLF", 0x00001000)
{
    External (_SB_.PC00.GFX0, DeviceObj)

    Scope (\_SB.PC00.GFX0)
    {
        Device (PNLF)
        {
            Name (_HID, EisaId ("APP0002"))
            Name (_CID, "backlight")
            Name (_UID, 0x13)
            Method (_STA, 0, NotSerialized)
            {
                If (_OSI ("Darwin")) { Return (0x0B) }
                Return (Zero)
            }
        }
    }
}
