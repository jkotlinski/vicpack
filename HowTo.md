## Installation ##

### Win32 ###

Extract archive to e.g. c:\vicpack. Launch program with c:\vicpack\vicpack.exe from DOS command line.

Note: Because of a bug in ACME, it's not possible to use drive letters for the image file path when using the -p option.

### OS X ###

In Terminal:

  1. tar xvzf vicpack-v006-osx.tar.gz
  1. cd vicpack-v006-osx
  1. sudo cp vicpack /usr/local/bin/
  1. sudo cp acme /usr/local/bin/ (optional)

## Usage ##

Some examples can be found in the examples archive.

```
    vicpack -p -fli fli.png
    vicpack -p -s hires_w_sprites.png
    vicpack -p -mc mc.png
    vicpack -p hires.png
    vicpack -p -mci mci.png
```

## Running your .prg files ##

For best results (if viewing with emulator), use Vice v1.21 (or later) and no cartridges plugged in.