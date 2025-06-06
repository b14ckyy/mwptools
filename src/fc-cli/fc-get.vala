/*
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * (c) Jonathan Hudson <jh+mwptools@daria.co.uk>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

private static int baud = 115200;
private static string dev = null;
private static string filename = null;
private static bool noback = false;
private static bool sdump = false;
private static bool ddump = false;
private static int delay = 0;
private static bool itest = false;

const OptionEntry[] options = {
    { "baud", 'b', 0, OptionArg.INT, out baud, "baud rate", null},
    { "device", 'd', 0, OptionArg.STRING, out dev, "device", null},
    { "no-back", 'n', 0, OptionArg.NONE, out noback, "no back", null},
    { "stdout", 0, 0, OptionArg.NONE, out sdump, "echo input to stdout", null},
    { "delay", 'w', 0, OptionArg.INT, out delay, "inter-line in ms", null},
    { "dump", 'D', 0, OptionArg.NONE, out ddump, "dump not diff", null},
    { "instrument", 'I', 0, OptionArg.NONE, out itest, "instrument", null},
    {null}
};

class FCMgr :Object {
    private enum State {
        IDLE = 0,
        CLI,
        DIFF,
        REBOOT,
        SETLINES,
        CALACC,
        BACKUP,
        EXIT = 0x7fff,
		VERS
    }

    private enum Mode {
        GET,
        SET
    }

    private enum Fc {
        UNKNOWN,
        INAV,
        BF
    }

    public MWSerial msp;
    public MWSerial.ProtoMode oldmode;
    private uint8 [] inbuf;
    private uint inp = 0;
    private uint linp = 0;
    private bool logging = false;
    private State state;
    private uint tid = 0;
    private MainLoop ml;
    public DevManager dmgr;
    private Mode mode = Mode.GET;
    private bool docal = false;
    private string[]lines;
    private string[]errors;
    private uint lp = 0;
    private uint etid = 0;
    private Fc fc;
    private uint8 trace = 0;
    private uint32 fc_vers;
    private bool have_acal = false;
    private bool skip_bbl = false;

	private static int lastid;
	private static Timer timer;
	private static FileStream tstream;

	private static string cmd;

	public FCMgr() {
		if(itest) {
			timer = new Timer();
			tstream = FileStream.open("/tmp/fcset-timer.txt", "w");
			lastid =-1;
		}

		inp = linp = 0;
        state = State.IDLE;
        inbuf = new uint8[1024*1024];
        MwpTermCap.init();
    }

    private void start_calacc() {
        MWPLog.message("Accelerometer calibration started\n");
        msp.send_command(Msp.Cmds.CALIBRATE_ACC, null, 0);
    }

    private void force_exit() {
        state = State.EXIT;
        cmd="exit\n";
        msp.write(cmd.data, cmd.length);
        Timeout.add(250,  () => { ml.quit(); return false;});
    }

    private void start_restore() {
        string s;
        Fc _fc = Fc.UNKNOWN;
        lines = {};
        lp = 0;
        FileStream fs = FileStream.open (filename, "r");
        if(fs == null) {
            MWPLog.message("Failed to open %s\n", filename);
            force_exit();
            return;
        }

        while((s = fs.read_line()) != null) {
                /* old F1 issue */
            if(s.contains("set blackbox_rate_num = 231")) {
                MWPLog.message("Skipping bogus BBL settings\n");
                skip_bbl = true;
            }

            if(skip_bbl && s.contains(" blackbox_"))
                continue;

            if(s.contains("set acc_hardware = NONE"))
                docal = false;

            if(s.contains("set acc_calibration") || s.contains("set acczero_x"))
                have_acal = true;

            if(s.has_prefix("# Betaflight"))
                _fc = Fc.BF;
            if(s.has_prefix("# INAV"))
                _fc = Fc.INAV;

            if(s.has_prefix("feature TRACE") && noback == false) {
                MWPLog.message("removing \"feature TRACE\"\n");
                continue;
            }

            if(s.has_prefix("#") == false && s._strip().length != 0)
                lines += s;
        }

        MWPLog.message("Starting restore: %s\n", filename);
        if(_fc != Fc.UNKNOWN && fc != _fc) {
            MWPLog.message("Refusing to restore incompatible settings\n");
            ml.quit();
        } else {
            switch(fc) {
                case Fc.INAV:
                    docal = false;
                    break;
                case Fc.BF:
                    if(have_acal && fc_vers >= 0x30400)
                        docal = false;
                    else
                        docal = true;
                    break;
                default:
                    docal = true;
                    break;
            }
            start_cli();
        }
    }

    private void start_cli() {
        cmd = "#";
        MWPLog.message("Establishing CLI\n");
        inp = linp = 0;
        state = State.CLI;
        msp.pmode = MWSerial.ProtoMode.CLI;
        msp.write(cmd.data, cmd.length);
    }

    private void start_diff() {
		var act = (ddump) ? "dump" : "diff";

		MWPLog.message("Starting \"%s all\"\n", act);
        cmd="%s all\n".printf(act);
        state = State.DIFF;
        inbuf[0] = '#';
        inbuf[1] = ' ';
        inp =2;
        msp.write(cmd.data, cmd.length);
    }

    private void start_quit() {
        MWPLog.message("Exiting\n");
        logging = false;
        inp = linp = 0;
        force_exit();
    }

    private void start_vers() {
        msp.send_command(Msp.Cmds.FC_VERSION, null, 0);
    }

    private void set_save_state() {
        if(docal)
            state = State.CALACC;
        else
            state = (noback) ? State.EXIT : State.BACKUP;
        trace = 0;
    }

    private void show_progress() {
         var pct = 100 * lp / lines.length;
         var sb = new StringBuilder();
         int i;
         for(i = 0; i < 50; i++)
             if(i <= pct/2)
                 sb.append_unichar(0x2587);
             else
                 sb.append_c(' ');
         var s = "\r[%s] %3u%%%s".printf(sb.str, pct, MwpTermCap.ceol);
         MWPLog.sputs(s);
    }

    private void start_setlines() {
        bool done = false;
        state = State.SETLINES;
	// Note: explicit save will save regardless of any errors
        if(lp < lines.length) {
			MWPLog.fputs("%4u : %s\n".printf(lp, lines[lp]));
            if(lines[lp].has_prefix("save")) {
				MWPLog.fputs("found save\n");
                set_save_state();
                done = true;
            }
            if (delay > 0)
                Thread.usleep(1000*delay);

			if(itest) {
				lastid = (int)lp;
				timer.start();
			}

            msp.write(lines[lp].data, lines[lp].length);
            msp.write("\n".data, 1);
            lp++;
        } else {
            done = true;
            if(errors.length == 0) {
				MWPLog.fputs("start save\n");
				set_save_state();
                cmd="save\n";
                msp.write(cmd.data,cmd.length);
            }
        }
        show_progress();
        if(done) {
			MWPLog.fputs("Done [%u]\n".printf(inp));
            lp = lines.length;
            stderr.printf("%s\n", MwpTermCap.cnorm);
            if(errors.length > 0) {
                MWPLog.sputs("\007Error(s) in restore\n\007");
                foreach (var e in errors) {
                    var s = "\t%s\n".printf(e);
                    MWPLog.sputs(s);
                }
                MWPLog.sputs("** Please check FC settings **\n\007");
                force_exit();
            }
        }
    }

    private void try_connect() {
        cancel_timers();
        if(msp.available) {
            msp.send_command(Msp.Cmds.API_VERSION,null,0);
        }
        etid = Timeout.add_seconds(2,() => {try_connect(); return false;});
    }

    private void reset_filenames() {
        StringBuilder sb = new StringBuilder(filename);
        var dt = new DateTime.now_local();
        sb.append_printf(".%s", dt.format("%FT%H.%M.%S"));
        FileUtils.rename(filename, sb.str);
    }

	private void set_cli_delay() {
		if (fc == Fc.INAV && fc_vers > 0x4ffff) {
			state = State.VERS;
			cmd="cli_delay=1\n";
			msp.write(cmd.data, cmd.length);
		}
	}

	private void next_state() {
        switch(state) {
            case State.IDLE:
				start_vers();
                break;

            case State.CLI:
				set_cli_delay();
                if(mode == Mode.GET) {
					Timeout.add(500, () => {
							start_diff();
							return false;
						});
				} else {
                    stderr.puts(MwpTermCap.civis);
					Timeout.add(500, () => {
							start_setlines();
							return false;
						});
                }
                break;

            case State.DIFF:
                dump_diff();
                start_quit();
                break;

            case State.SETLINES:
                start_setlines();
                break;

            case State.CALACC:
                start_calacc();
                break;

            case State.BACKUP:
                mode = Mode.GET;
                reset_filenames();
                start_cli();
                break;

            default:
                break;
        }
    }

    private void dump_diff() {
        const string intro="# mwptools / fc-cli dump at %s\n# fc-cli is a toolset # (fc-set, fc-get) to manage\n# iNav / βF CLI diff backup and restore\n# <https://github.com/stronnag/mwptools>\n\n";
        var dt = new DateTime.now_local();
        string fn = (filename == null) ? "/tmp/dump.txt" : filename;
        int fd = Posix.open (fn, Posix.O_TRUNC|Posix.O_CREAT|Posix.O_WRONLY, 0640);
        string s = intro.printf(dt.format("%FT%T%z"));
        Posix.write(fd, s, s.length);
        Posix.write(fd, inbuf, inp);
        Posix.close(fd);
    }

    private void cancel_timers() {
        if(tid != 0)
            Source.remove(tid);
        if(etid != 0)
            Source.remove(etid);
        tid = etid = 0;
    }

    public void init(bool issetting) {
        msp = new MWSerial();
        oldmode  =  msp.pmode;
        mode = (issetting) ? Mode.SET : Mode.GET;
        dmgr = new DevManager();

        dmgr.device_added.connect((sdev) => {
				if (sdev.type == DevMask.USB) {
					if(!msp.available) {
						if(sdev.name == dev || dev == null) {
							msp.open_async.begin(sdev.name, baud,  (obj,res) => {
									var ok = msp.open_async.end(res);
									if (ok) {
										if(tid != 0) {
											Source.remove(tid);
											tid = 0;
										}
										msp.setup_reader();
										msp.pmode = MWSerial.ProtoMode.NORMAL;
										tid = Timeout.add_seconds(1, () => {
												try_connect();
												return true;
										});
									} else {
										string estr;
										msp.get_error_message(out estr);
										MWPLog.message("Failed to open %s\n", estr);
									}
								});
						}
					}
				}
            });

        dmgr.device_removed.connect((sdev) => {
                MWPLog.message("%s has been removed\n",sdev);
                msp.close();
            });

        msp.cli_event.connect(() => {
				MWSerial.INAVEvent? m;
				while((m = msp.msgq.try_pop()) != null) {
					if(tid != 0) {
						Source.remove(tid);
						tid = 0;
					}
					if(sdump)
						Posix.write(1, m.raw, m.len);

					for(var j = 0; j < m.len; j++) {
						if(m.raw[j] != 13)
							inbuf[inp++] = m.raw[j];
					}

					if(state == State.SETLINES &&
					   ((string)inbuf).slice(linp,inp).contains("### ERROR:")) {
						FileStream fs = FileStream.open ("/tmp/fcset-err.txt", "a");
						fs.printf("Err: %s\n", ((string)inbuf).slice(linp,inp));
						fs.flush();
						errors += lines[lp-1];
					}

					linp = inp;
					if(inp >= 9 && Memory.cmp(&inbuf[inp-9], "Rebooting".data, 9) == 0) {
						MWPLog.message("Rebooting (%s)\n", state.to_string());
						inp = linp = 0;
						msp.pmode = oldmode;
						if(state == State.EXIT)
							Timeout.add(2000, () => { ml.quit(); return false; });
						else {
							msp.pmode = MWSerial.ProtoMode.NORMAL;
							etid = Timeout.add_seconds(2, () => {
									try_connect(); return false;
								});
						}
					} else if( inp > 3) {
						if(inbuf[inp-1] == ' ' && inbuf[inp-2] == '#' &&
						   (inbuf[inp-3] == '\n' || inbuf[inp-3] == '\r')) {
							if(itest) {
								var els = timer.elapsed();
								if(lastid != -1) {
									tstream.printf("%04d\t%6.3f\t%s\n", lastid, els, lines[lastid]);
									lastid = -1;
								}
							}
							if(state == State.SETLINES)
								next_state();
							else {
								tid = Timeout.add(500, () => {
										tid = 0;
										if(inp == linp)
											next_state();
										return false;
									});
							}
						}
					}
				}
            });

		msp.serial_event.connect(()  => {
				//				msp.serial_event.connect((cmd, raw, len, flags, err) => {
				MWSerial.INAVEvent? m;
				while((m = msp.msgq.try_pop()) != null) {
					if(m.err == false) {
						switch(m.cmd) {
                        case Msp.Cmds.API_VERSION:
							cancel_timers();
							if(trace == 0)
								next_state();
							break;

						case Msp.Cmds.DEBUGMSG:
							MWPLog.message((string)m.raw);
							trace++;
							if(trace == 2)
								next_state();
							break;

                        case Msp.Cmds.CALIBRATE_ACC:
							Timeout.add_seconds(4, () => {
									MWPLog.message("Accelerometer calibration finished\n");
									msp.send_command(Msp.Cmds.EEPROM_WRITE,null, 0);
									if(noback)
										ml.quit();
									else {
										state = State.BACKUP;
										next_state();
									}
									return false;
								});
							break;

                        case Msp.Cmds.FC_VERSION:
							fc_vers = m.raw[0] << 16 | m.raw[1] << 8 | m.raw[2];
							msp.send_command(Msp.Cmds.FC_VARIANT, null, 0);
							break;

                        case Msp.Cmds.FC_VARIANT:
							string fwid = (string)m.raw[0:4];
							switch(fwid) {
                            case "INAV":
                                fc = Fc.INAV;
                                break;
                            case "BTFL":
                                fc = Fc.BF;
                                break;
                            default:
                                fc = Fc.UNKNOWN;
                                break;
							}

							if(mode == Mode.GET)
								Idle.add(() => { start_cli(); return false; });
							else
								Idle.add(() => { start_restore(); return false;});
							break;

                        default:
							break;
						}
					}
				}
            });

        msp.serial_lost.connect(() => {
                MWPLog.message("Lost serial connection\n");
                if(state == State.EXIT)
                    ml.quit();
            });


		if(dev == null) {
			if(DevManager.serials.length() == 1) {
				var dx = DevManager.serials.nth_data(0);
				if (dx.type == DevMask.USB) {
					dev = dx.name;
				}
			}
		}

		if(!msp.available && dev != null) {
			string rdev;
			var st = DevUtils.evince_device_type(dev, out rdev);
			if(st == DevUtils.SerialType.BT || st == DevUtils.SerialType.UNKNOWN) {
				dev = rdev;
				DevManager.wait_device_async.begin(rdev, (obj,res) => {
						var ok = DevManager.wait_device_async.end(res);
						if (ok) {
							var dd = DevManager.get_dd_for_name(dev);
							if (dd != null) {
								dev = dd.name;
								if (DevUtils.valid_bt_name(dev)) {
									open_device();
								}
							}
						} else {
							MWPLog.message("Unrecognised %s\n", dev);
							ml.quit();
						}
					});
			} else if (st != DevUtils.SerialType.UNKNOWN) {
				open_device();
			} else {
				MWPLog.message("Unrecognised %s\n", dev);
				ml.quit();
			}
		}
    }

	void open_device() {
		msp.open_async.begin(dev, baud, (obj,res) => {
					var ok = msp.open_async.end(res);
					if (ok) {
						MWPLog.message("Opening %s\n", dev);
						msp.setup_reader();
						etid = Idle.add(() => { try_connect(); return false; });
					} else {
						string estr;
						msp.get_error_message(out estr);
						MWPLog.message("open failed %s\n", estr);
					}
				});
	}

    public void run() {
        ml = new MainLoop();
        ml.run ();
        msp.close();
    }
}

static int main (string[] args) {
    try {
        var opt = new OptionContext(" - fc diff manager");
        opt.set_help_enabled(true);
        opt.add_main_entries(options, null);
        opt.parse(ref args);
    } catch (OptionError e) {
        stderr.printf("Error: %s\n", e.message);
        stderr.printf("Run '%s --help' to see a full list of available "+
                      "options\n", args[0]);
        return 1;
    }

    MWPLog.set_time_format("%T");
    bool issetting =  args[0].has_suffix("set");
    for(var j = 1; j < args.length; j++) {
        int b;
        var a = args[j];
        if(a.has_prefix("/dev/") || (a.length == 17 && a[2] == ':' && a[5] == ':'))
            dev = a;
        else if((b = int.parse(a)) != 0)
            baud = b;
        else
            filename = a;
    }
    if(issetting && filename == null)
        MWPLog.message("Need a filename to restore FC\n");
    else {
        if(dev == null)
            MWPLog.message("No device given ... watching\n");
        var fcm  = new FCMgr();
        fcm.init(issetting);
        fcm.run();
    }
    return 0;
}