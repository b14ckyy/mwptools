private static int baud = 115200;
private static string eolmstr;
private static string dev;
private static bool noinit=false;
private static bool msc=false;
private static bool gpspass=false;
private static string rcfile=null;
private static int eolm;
private static string cli_delay=null;

const OptionEntry[] options = {
    { "baud", 'b', 0, OptionArg.INT, out baud, "baud rate", "115200"},
    { "device", 'd', 0, OptionArg.STRING, out dev, "device", null},
    { "noinit", 'n', 0,  OptionArg.NONE, out noinit, "noinit", "false"},
    { "msc", 'm', 0,  OptionArg.NONE, out msc, "msc mode", "false"},
    { "gpspass", 'g', 0,  OptionArg.NONE, out gpspass, "gpspassthrough", "false"},
    { "gpspass", 'p', 0,  OptionArg.NONE, out gpspass, "gpspassthrough", "false"},
    { "file", 'f', 0, OptionArg.STRING, out rcfile, "file", null},
    { "eolmode", 'm', 0, OptionArg.STRING, out eolmstr, "eol mode", "[cr,lf,crlf,crcrlf]"},
    {null}
};

class CliTerm : Object {
    private MWSerial msp;
    private MWSerial.ProtoMode oldmode;
    public DevManager dmgr;
    private MainLoop ml;
    private string eol;
    private bool sendpass = false;
	private uint8 inavvers;

	public CliTerm() {
	}

	public void init() {
        eol="\r";
        if(eolm == 1)
            eol="\n";
        else if(eolm == 2)
            eol="\r\n";
        else if(eolm == 3)
            eol="\r\r\n";

        MWPLog.set_time_format("%T");
        ml = new MainLoop();
        msp= new MWSerial();
        dmgr = new DevManager(DevMask.USB);

        var devs = dmgr.get_serial_devices();
        if(dev == null && devs.length == 1)
            dev = devs[0];

        if(dev != null)
            open_device(dev);

        dmgr.device_added.connect((sdev) => {
                if(!msp.available)
                    open_device(sdev);
            });

        dmgr.device_removed.connect((sdev) => {
                msp.close();
            });

        msp.cli_event.connect((buf,len) => {
                if(sendpass)
                    ml.quit();
                else
                    Posix.write(1,buf,len);
            });

		msp.serial_event.connect((cmd, buf, len, flags, err) => {
				//				stderr.printf("msp %u %u %s\r\n", cmd, len, err.to_string());
				if (!err && cmd == MSP.Cmds.FC_VERSION) {
					inavvers = buf[0];
					if(inavvers > 4 && cli_delay != null) {
						Timeout.add(500, () => {
								msp.write(cli_delay, cli_delay.length);
								msp.write(eol.data, eol.length);
								return false;
							});
					}
					msp_init();
				}
			});

		msp.serial_lost.connect(() => {
				ml.quit();
			});
    }

    private void replay_file() {
        FileStream fs = FileStream.open (rcfile, "r");
        if(fs != null) {
            Timeout.add(200, () => {
                    var s = fs.read_line();
                    if(s != null) {
                        if(s.has_prefix("#") == false && s._strip().length != 0) {
                            msp.write(s.data, s.length);
                            msp.write(eol.data, eol.length);
                        }
                        return true;
                    } else
                        return false;
                });
        }
    }

	private void msp_init() {
		oldmode  =  msp.pmode;
		msp.pmode = MWSerial.ProtoMode.CLI;
		if(noinit == false) {
			Timeout.add(50, () => {
					msp.write("#".data, 1);
					return false;
				});
		}

		if(msc) {
			Timeout.add(500, () => {
					msp.write("msc".data, 3);
					msp.write(eol.data, eol.length);
					return false;
				});
		} else if(gpspass) {
			Timeout.add(500, () => {
					var g = "gpspassthrough";
					msp.write(g.data, g.length);
					msp.write(eol.data, eol.length);
					sendpass = true;
					return false;
				});
		} else if(rcfile != null) {
			Timeout.add(1000, () => {
					replay_file();
					return false;
				});
		}
	}

    private void open_device(string device) {

        print ("open %s\r\n",device);
		msp.open_async.begin(device, baud,  (obj,res) => {
				var ok = msp.open_async.end(res);
				if (ok) {
					msp.setup_reader();
					if(noinit) {
						msp.pmode = MWSerial.ProtoMode.CLI;
					} else {
						msp.pmode = MWSerial.ProtoMode.NORMAL;
						msp.send_command(MSP.Cmds.FC_VERSION, null,0);
						Timeout.add(2000,() => {
								if (msp.pmode != MWSerial.ProtoMode.CLI) {
									msp.pmode = MWSerial.ProtoMode.CLI;
								}
								return false;
							});
					}
				} else {
					string estr;
					msp.get_error_message(out estr);
					print("open failed %s\r\n", estr);
				}
			});
	}

    public void run() {
        Posix.termios newtio = {0}, oldtio = {0};
        Posix.tcgetattr (0, out newtio);
        oldtio = newtio;
        Posix.cfmakeraw(ref newtio);
        Posix.tcsetattr(0, Posix.TCSANOW, newtio);

        try {
            var io_read = new IOChannel.unix_new(0);
            if(io_read.set_encoding(null) != IOStatus.NORMAL)
                error("Failed to set encoding");
			io_read.add_watch(IOCondition.IN|IOCondition.HUP|IOCondition.NVAL|IOCondition.ERR, (g,c) => {
				uint8 buf[2];
				ssize_t rc = -1;
				var err = ((c & (IOCondition.HUP|IOCondition.ERR|IOCondition.NVAL)) != 0);
				if (!err)
					rc = Posix.read(0,buf,1);

				if (err || buf[0] == 3 || rc <0) {
					ml.quit();
					return false;
				}
				if (msp.available) {
					if(buf[0] == 13 && eolm != 0) {
						msp.write(eol.data,eol.length);
					} else {
						msp.write(buf,1);
					}
				}
				return true;
			});
		} catch(IOChannelError e) {
			error("IOChannel: %s", e.message);
		}
		ml.run ();
		msp.close();
		Posix.tcsetattr(0, Posix.TCSANOW, oldtio);
	}

	public static string[]? set_def_args() {
		var fn = MWPUtils.find_conf_file("cliopts");
		if(fn != null) {
			var file = File.new_for_path(fn);
			try {
				var dis = new DataInputStream(file.read());
				string line;
				string []m;
				var sb = new StringBuilder ("cli");
				while ((line = dis.read_line (null)) != null) {
					if(line.strip().length > 0) {
						if (line.has_prefix("-")) {
							sb.append_c(' ');
							sb.append(line);
						} else if (line.has_prefix("cli_delay")) {
							cli_delay = line;
						}
					}
				}
				Shell.parse_argv(sb.str, out m);
				if (m.length > 1) {
					return m;
				}
			} catch (Error e) {
				error ("%s", e.message);
			}
		}
		return null;
	}

	public static int main (string[] args) {
		try {
			var opt = new OptionContext(" - cli tool");
			opt.set_help_enabled(true);
			opt.add_main_entries(options, null);
			var m = set_def_args();
			if (m != null) {
				opt.parse_strv(ref m);
			}
			opt.parse(ref args);
		} catch (OptionError e) {
			stderr.printf("Error: %s\n", e.message);
			stderr.printf("Run '%s --help' to see a full list of available "+
						  "options\n", args[0]);
			return 1;
		}

		if (args.length > 2)
			baud = int.parse(args[2]);

		if (args.length > 1)
			dev = args[1];

		switch (eolmstr) {
		case "cr":
			eolm = 0;
			break;
		case "lf":
			eolm = 1;
			break;
		case "crlf":
			eolm = 2;
			break;
        case "crcrlf":
            eolm = 3;
            break;
		}
		var cli = new CliTerm();
		cli.init();
		cli.run();
		return 0;
	}
}
