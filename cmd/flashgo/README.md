# mwp flashgo

## Description

`flashgo` is a simple tool to download / erase data flash from INAV flight controllers.
Requires INAV 1.80 or later (MSPv2 support).

## Features

* Enumerates USB / STM32 for serial device discovery.
* Provides information on flash usage
* Downloads BBL from flash
* Erase flash
* Golang, so can be built for most modern OS and architectures (Linux, Windows, FreeBSD, MacOS, ia32, x86_64, arm7, aarch64, riscv64 at least).

## Usage

```
flashgo [options] [device_name]
```

`device_name` is the name of the FC serial device (e.g. `/dev/ttyUSB0`, `/dev/ttyACM0`, `COM17`). On Linux, you may also use a Bluetooth device address (`xx:xx:xx:xx:xx:xx`).

If no device name is given, any extant USB / STM32 device will be auto-detected, at least on Linux and Windows. A device name specified on the command line will be used in preference to auto-detection. Note: On many OS, Bluetooth devices will not be auto-detected, so must be given as a command parameter.

### Options

```
$ flashgo --help
Usage of flashgo [options] [device_name]
  -dir string
    	output directory
  -erase
    	erase after download
  -file string
    	generated if not defined
  -info
    	only show info
  -only-erase
    	erase only
  -test
    	download whole flash regardess of usage
```

The default is to download the flash BBL (if the used size is > 0).
`-info` and `-only-erase` options do not download the flash contents.

If the file name is not provided, `-file BBL.TXT`, then a name is constructed of the form `bbl_YYYY-MM-DD_hhmmss.TXT` (i.e. current time stamp).

## Installation

* `make`
* `make install`  (installs in `~/.local/bin`)
* or `sudo make install prefix=/usr/local` (installs in `/usr/local/bin`)
* cross compile for Windows (can also build natively) `GOOS=windows make`

## Examples

``` go
# Test download of whole flash
$ flashgo  -test
Using /dev/ttyACM0
Firmware: INAV
Version: 5.0.0
Entering test mode for 2097152b
Data flash 2097152 / 2097152 (100%)
Downloading to bbl_2022-06-28_144312.TXT
[▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇] 2.0MB/2.0MB 100% 0s
2097152 bytes in 38.8s, 54006.2 bytes/s

```

``` go
# Check usage
flashgo -info
Using /dev/ttyACM0
Firmware: INAV
Version: 5.0.0
Data flash 88547 / 2097152 (4%)
```

``` go
# download to named directory and file
$ flashgo -dir /tmp/ -file bbltest.TXT /dev/ttyACM0
Using /dev/ttyACM0
Firmware: INAV
Version: 5.0.0
Data flash 106199 / 2097152 (5%)
Downloading to /tmp/bbltest.TXT
[▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇] 103.7KB/103.7KB 100% 0s
106199 bytes in 2.1s, 51420.0 bytes/s
```

``` go
# download (defaults / auto)
$ flashgo
Using /dev/ttyACM0
Firmware: INAV
Version: 5.0.0
Data flash 106199 / 2097152 (5%)
Downloading to bbl_2022-06-28_145233.TXT
[▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇] 103.7KB/103.7KB 100% 0s
106199 bytes in 2.1s, 51409.9 bytes/s
```


``` go
# Erase flash
$ flashgo -only-erase
Using /dev/ttyACM0
Firmware: INAV
Version: 5.0.0
Erase in progress ...
Completed
```


``` go
# Download and erase
$ flashgo -erase
Using /dev/ttyACM0
Firmware: INAV
Version: 5.0.0
Data flash 88547 / 2097152 (4%)
Downloading to bbl_2022-06-28_145855.TXT
[▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇] 86.5KB/86.5KB 100% 0s
88547 bytes in 1.6s, 56430.9 bytes/s
Start erase
Erase in progress ...
Completed
```
