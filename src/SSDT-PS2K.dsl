/* VoodooPS2 keyboard settings for the hp elitebook 850 g8 keyboard (PS2K, HPQ8002).
   fn + airplane sends e078, which macOS has no key for. map it to F18 so it can be bound in keyboard shortcuts.
   fn + the star key (F12) already sends 0x68 = F17. */
DefinitionBlock ("", "SSDT", 2, "CLAWD", "PS2K", 0x00001000)
{
    External (_SB_.PC00.LPCB.PS2K, DeviceObj)

    Scope (\_SB.PC00.LPCB.PS2K)
    {
        Method (RMCF, 0, NotSerialized)
        {
            If (_OSI ("Darwin"))
            {
                Return (Package ()
                {
                    "Keyboard", Package ()
                    {
                        "Custom ADB Map", Package ()
                        {
                            Package () {},
                            "e078=4f"   // fn + airplane to F18
                        }
                    }
                })
            }
            Return (Zero)
        }
    }
}
