/* turn off the AWAC clock and turn on the legacy RTC under macOS (STAS = 1) */
DefinitionBlock ("", "SSDT", 2, "CLAWD", "AWAC", 0x00001000)
{
    External (STAS, IntObj)

    Scope (\_SB)
    {
        Method (_INI, 0, NotSerialized)
        {
            If (_OSI ("Darwin")) { STAS = One }
        }
    }
}
