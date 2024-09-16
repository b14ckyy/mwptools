# Running mwp

## Video Tutorials

There is an [slightly outdated video](https://vimeo.com/267437907)  that describes dock usage and some post-install actions:

<iframe src="https://player.vimeo.com/video/267437907?h=015ed1fdc6" width="640" height="431" frameborder="0" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe>

!!! info "Update"
    * More useful than I remember!
    * The dock is now installed populated.
    * WP editor switch is enabled by default
    * There is now a graphical "favourite places" editor
    * The build system is no longer `make`

Apart from that, it's quite informative.

### Tutorial Playlist

All the developer's tutorial videos are in a [YouTube playlist](https://www.youtube.com/playlist?list=PLE_mnLfCdjvAH4pLe9HCqaWm682_r8NT3).

## Graphical User Interface

Once you've [built and / or installed](Building-with-meson-and-ninja.md) {{ mwp }}.

The install process installs an desktop icon and `mwp.desktop` application file ![icon](images/mwp_icon.svg)

  The `desktop` file tells the window manager where to find {{ mwp }} and on modern desktop environments (e.g. Gnome Shell, xfce, kde), {{ mwp }} will be added to the system application menu and / or 'finder'.

* It is also possible to run {{ mwp }} from a terminal, passing additional [options](mwp-Configuration.md) if required.
* Such [options can be added to a configuration file](mwp-Configuration.md) for persistence or use from the graphical icon.

### Display Managers

{{ mwp }} uses a library, `libchamplain` to draw maps and mission symbols; unfortunately, this does not integrate consistently with the various generations of open source display managers (ironically, it works without problems in WSL2-G). Please check the following before raising Github issues:

* On **Wayland** : Wayland is the latest open source display manager. On some graphics cards, it may fail to 'pick' waypoint symbols when there are more than c. 40 symbols in a mission.
  In order to mitigate this, the default setting in mwp is to use a fallback implementation known as **XWayland**. Use of **Wayland** (vice XWayland) for newer graphics cards may be forced by setting `GDK_BACKEND=wayland` in [`~/.config/mwp/cmdopts`](mwp-Configuration.md#cmdopts) or the environment.

* On **Xlib** : For older versions of mwp sometimes you may load a mission and the WPs cannot be 'picked' and the map is unresponsive to mouse control. The work-around is to move the mouse off the map and back on again (or scroll the map with the keyboard, CTRL-arrow-keys).

    This is fixed in mwp later than 5.251.652 (2022-09-08); the solution being to ensure all dialogs are non-modal. **Please upgrade.**

## Touch Screen

From {{ mwp }} 7.178.767, the mwp map and map symbols are 'touch-aware'.

* You can drag map symbols using touch
* You can invoke "right mouse button" actions by a double tap

## Command line options

{{ mwp }}'s command line options may be displayed with the `--help` option:

    mwp --help
    Usage:
      mwp [OPTION…]

    Help Options:
      -h, --help                          Show help options
      --help-all                          Show all help options
      --help-gapplication                 Show GApplication options
      --help-gtk                          Show GTK Options

    Application Options:
      -m, --mission=file-name             Mission file
      -s, --serial-device=device_name     Serial device
      -d, --device=device-name            Serial device
      -f, --flight-controller=fc-name     mw|mwnav|bf|cf
      -c, --connect                       connect to first device (does not set auto flag)
      -a, --auto-connect                  auto-connect to first device (sets auto flag)
      -N, --no-poll                       don't poll for nav info
      -T, --no-trail                      don't display GPS trail
      -r, --raw-log                       log raw serial data to file
      --ignore-sizing                     ignore minimum size constraint
      --full-screen                       open full screen
      --ignore-rotation                   legacy unused
      --dont-maximise                     don't maximise the window
      --force-mag                         force mag for vehicle direction
      --force-nav                         force nav capaable
      -l, --layout                        Layout name
      -t, --force-type=type-code_no       Model type
      -4, --force4                        Force ipv4
      -3, --ignore-3dr                    Ignore 3DR RSSI info
      -H, --centre-on-home                Centre on home
      --debug-flags                       Debug flags (mask)
      -p, --replay-mwp=file-name          replay mwp log file
      -b, --replay-bbox=file-name         replay bbox log file
      --centre=position                   Centre position (lat lon or named place)
      --offline                           force offline proxy mode
      -S, --n-points=N                    Number of points shown in GPS trail
      -M, --mod-points=N                  Modulo points to show in GPS trail
      --rings=number,interval             Range rings (number, interval(m)), e.g. --rings 10,20
      --voice-command=command string      External speech command
      -v, --version                       show version
      --build-id                          show build id
      --really-really-run-as-root         no reason to ever use this
      --forward-to=device-name            forward telemetry to
      --radar-device=device-name          dedicated inav radar device
      --perma-warn                        info dialogues never time out
      --fsmenu                            use a menu bar in full screen (vice a menu button)
      -k, --kmlfile=file-name             KML file
      --rebase=lat,lon                    rebase location (for replay)
      --relaxed-msp                       don't check MSP direction flag
      --display=DISPLAY                   X display to use

### Bash completion

{{ mwp }} installation also installs a 'bash completion' script.
Note this is only available after you log in, so on first install, it's only available after the *next* login.

This facilitates automatic command completion, so you don't have to remember all the options or be always typing `mwp --help`.

Typing `mwp ` and then `<TAB>` will first display the option lead `--`; then a subsequent `<TAB><TAB>` will display all the options. If one then typed `ra<TAB><TAB>`, it would complete to:

    $ mwp --ra
    --radar-device  --raw-log

Further entry (e.g. `d`) would complete the command (`--radar-device`).

### Adding options to a running mwp

Certain options, like `--replay-bbox`, `--mission` allow you to add a file to a running {{ mwp }}. So if {{ mwp }} was running, either from the command line or Desktop Environment icon, then (for example):

    mwp --mission file-i-forgot.mission

would load the mission `file-i-forgot.mission` into the running {{ mwp }} rather than starting a new instance.

### Drag and Drop

You can *drag and drop* relevant files onto the {{ mwp }} map:

* Blackbox Logs
* Mission Files
* KML Overlays

### Clean and unclean exits

If you exit {{ mwp }} from the **Quit** menu (or Control-Q key shortcut), then the current dock layout will be saved; if you close {{ mwp }} from the Window Manager `close` title bar button, or CLI `kill` command, the layout is not saved; this is a feature.
