# ser2udp - simple serial to IP (UDP) bridge

`ser2udp` is a simple serial to UDP bridge. It is intended to be used for accessing a serial USB flight controller using Windows 11 / WSLg and mwp; however there is almost nothing either Windows or mwp specific. It can be used as a generic bridge, for cases where the UDP side "speaks" first, unless `-remote` is set.

## Usage

```
$ ser2udp --help
Usage of ser2udp [options] device [:port]
  -baudrate int
    	set baud rate (default 115200)
  -remote string
    	remote name
  -verbose int
    	verbosity (0:none, 1:open/close, >1:I/O)
```

If port is not provided, it defaults to `:17071` (the colon in required).

If device is not provided (which implies that port is not either), or is 'auto' then the device will be auto-detected (and has to be (a) USB and (b) have a USB pid:vid of 5740:0483, i.e. a STM32 device).

If `ser2udp` is run in Windows as a bridge for mwp in WSLg, then it will also tell you the addresses of the Linux side interface.

```
> ./set2udp.exe
External address: fe80::1439:d6de:efcb:97e1%17
External address: 172.29.32.1
```

In this case, for mwp use a device name of `udp://172.29.32.1:17071` on the Linux side. Note that for the WSLg case, this address is the default gateway address on the Linux side.

### Verbosity

If verbosity is > 0, then additional debug messages will be displayed:

| Verbosity | Affect |
| --------- | ------ |
| 0         | No debug |
| 1         | Open and close of serial device |
| > 1       | as 1, plus serial / network writes |

## Automation

For running mwp in Win11/WSL-g, the required IP address is the default gateway, this can be automated by using the magic `__MWP_SERIAL_HOST` name in the mwptools serial device.

```
mwp -d udp://__MWP_SERIAL_HOST:17071
# recognised by other tools as well ...
cliterm udp://__MWP_SERIAL_HOST:17071
```

`__MWP_SERIAL_HOST` is resolved as:

* If an enviroment variable `$MWP_SERIAL_HOST` exists, it is used; else
* The default gateway (which on WSL is the Windows host IP) is used.

Thus:

* In mwp preferences, set the serial device to `udp://__MWP_SERIAL_HOST:17071` for WSL and `ser2udp`
* Or in the shell, for some other provider `export MWP_SERIAL_HOST=foobox.org` if you have a use case.


## Building

Building `ser2udp` requires a Go (golang) compiler. This is easily installed in Linux and can cross compile a Windows binary. You could otherwise install the Go compiler in Windows and build it there.

* Build natively: `go build -ldflags "-w -s"`
* Cross compile for Windows: `GOOS=windows go build -ldflags "-w -s"`

For convenience, there is a Makefile that provides suitable targets.

## Further Info

Further information, for example automating the launching of `ser2udp.exe` from WSL is described in the [user guide](https://stronnag.github.io/mwptools/mwp-in-Windows-11---WSL-G/#autos2n).
