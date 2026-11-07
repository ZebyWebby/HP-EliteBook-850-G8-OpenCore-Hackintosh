/* VoodooPS2 keyboard settings for the hp elitebook 850 g8 keyboard (PS2K, HPQ8002).
   the airplane hotkey sends e078 and the display switch hotkey (F1) sends e06e. VoodooPS2 maps e06e to adb 0x70, which
   macOS drops. map them to F18 and F16 so they can be bound in keyboard shortcuts.
   the star hotkey (F12) already sends 0x68 = F17.
   F10 is the insert key (e052), which VoodooPS2 maps to eject (0x92) and macOS ignores without a drive. map it to
   help (0x72), the mac's insert key (terminal and windows apps take it as insert). */
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
                            "e078=4f",  // airplane hotkey to F18
                            "e06e=6a",  // display switch hotkey (F1) to F16
                            "e052=72"   // F10 insert to help (mac insert)
                        }
                    }
                })
            }
            Return (Zero)
        }
    }
}
