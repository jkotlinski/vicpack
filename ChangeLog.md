# Changelog #

**25th July 2007: v0.10**

  * by default, vicpack now uses input image color indexes directly for color matching. colors are assumed to be in the standard c64 palette order.
  * add option -pepto for closest color matching to the pepto palette.
  * improved error messages - now prints coordinates of chars with too many colors.
  * rename options -escos and -escos2 to -sprite for clarity
  * rename option -s to -overlay
  * -mci -p will now always mask leftmost pixel column using sprites

**22nd July 2007: v0.09**

  * Asslace viewer (-ass -p) works!
  * MCI: -mci -s now hides leftmost pixel column using sprites

**22nd July 2007: v0.08**

  * Added -ass option for Asslace conversion (viewer is buggy - needs workaround for badlines)
  * Bugfix: Win32 path handling
  * Improved merging of Color RAM for interlaced images

**19th July 2007: v0.07**

  * Add path detection (no need to change system path in win32)
  * Add option -border n, for setting custom border color
  * Small interface changes

**17th July 2007: v0.06**

  * Initial public release. Support Multicolor, Hires, FLI, MCI, Escos...

## Coming Up ##

Path detection (no need to change system path for finding ACME)