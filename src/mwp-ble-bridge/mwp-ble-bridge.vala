namespace MWPLog {
	public void  message(string format, ...) {
		var args = va_list();
		stdout.vprintf(format, args);
	}
}

public class GattTest : Application {
	private string? addr;
	private BleSerial gs;
	private int rdfd;
	private int wrfd;
	private int pfd;
	private int mtu;
	private int delay;
	private bool verbose;
	private Bluez bt;
	private uint id;

	public GattTest () {
        Object (application_id: "org.mwptools.mwp-ble-bridge",
				flags: ApplicationFlags.HANDLES_COMMAND_LINE);
        Unix.signal_add (
            Posix.Signal.INT,
            on_sigint,
            Priority.DEFAULT
        );
		startup.connect (on_startup);
        shutdown.connect (on_shutdown);
		delay = 500;
		var options = new OptionEntry[] {
			{ "address", 'a', 0, OptionArg.STRING, null, "BT address", null},
			{ "settle", 's', 0, OptionArg.INT, null, "BT settle time (ms)", null},
			{ "verbose", 's', 0, OptionArg.NONE, null, "be verbose", null},
            { "version", 'v', 0, OptionArg.NONE, null, "show version", null},
			{null}
		};
		set_option_context_parameter_string(" - BLE serial bridge");
		set_option_context_description(" requires a BT address or $MWP_BLE to be set");
		add_main_option_entries(options);
		handle_local_options.connect(do_handle_local_options);
	}

	public override int command_line (ApplicationCommandLine command_line) {
		string[] args = command_line.get_arguments ();
		var o = command_line.get_options_dict();
		o.lookup("address", "s", ref addr);
		o.lookup("settle", "i", ref delay);
		o.lookup("verbose", "b", ref verbose);

		if (addr == null) {
			if (args.length > 1) {
				addr = args[1];
			} else {
				addr =  Environment.get_variable("MWP_BLE");
			}
		}
		if(addr == null) {
			stderr.printf("usage: mwp-ble-bridge --address ADDR (or set $MWP_BLE)\n");
			return 127;
		} else {
			activate();
			return 0;
		}
	}

	private int do_handle_local_options(VariantDict o) {
        if (o.contains("version")) {
            stdout.printf("0.0.1\n");
            return 0;
        }
		return -1;
    }

	public override void activate () {
		hold ();
		new BLEKnownUUids();
		bt = new Bluez();
		Idle.add(() => {
				bt.init();
				init();
				return false;
			});
		return;
	}

	private void init () {
		gs = new BleSerial();
		if(addr.has_prefix("bt://")) {
			addr = addr[5:addr.length];
		}

		open_async.begin((obj, res) =>  {
				var ok = open_async.end(res);
				if (ok == 0) {
					mtu = gs.get_bridge_fds(bt, out rdfd, out wrfd);
					MWPLog.message("BLE chipset %s, mtu %d\n", gs.get_chipset(), mtu);
					start_session();
				} else {
					MWPLog.message("Failed to find service (%d)\n", ok);
					close_session();
				}
			});
	}

	private async int open_async() {
		var thr = new Thread<int> (addr, () => {
				var res = open_w();
				Idle.add (open_async.callback);
				return res;
			});
		yield;
		return thr.join();
	}

	private int open_w() {
		uint tc = 0;
		while ((id = bt.get_id_for(addr)) == 0) {
			Thread.usleep(5000);
			tc++;
			if(tc > 200*15) {
				return -1;
			}
		}
		tc = 0;
		if (!bt.set_device_connected(id, true)) {
			return -2;
		}
		while (!bt.get_device(id).is_connected) {
			Thread.usleep(5000);
			tc++;
			if(tc > 200*5) {
				return -2;
			}
		}
		tc = 0;
		while(true) {
			int gid = -1;
			var uuids =  bt.get_device_property(id, "UUIDs").dup_strv();
			var sid = BLEKnownUUids.verify_serial(uuids, out gid);
			gs.set_gid(gid);
			if(sid == 2) {
				break;
			}
			Thread.usleep(5000);
			tc++;
			if (tc > 200*15) {
				return -3;
			}
		}
		tc = 0;
		while (!gs.find_service(bt, id)) {
			Thread.usleep(5000);
			tc++;
			if (tc > 200*2) {
				return -4;
			}
		}
		return 0;
	}

	private void close_session () {
		if(rdfd != -1)
			Posix.close(rdfd);
		if(wrfd != -1)
			Posix.close(wrfd);
		if(pfd != -1)
			Posix.close(pfd);
		pfd = rdfd = wrfd = -1;
		if (gs != null) {
			MWPLog.message("Disconnect\n");
			bt.set_device_connected(id, false);
		}
		this.quit();
	}

	private void start_session () {
		if (rdfd != -1 && wrfd != -1) {
			pfd = Posix.posix_openpt(Posix.O_RDWR|Posix.O_NONBLOCK);
			if (pfd != -1) {
				Posix.grantpt(pfd);
				Posix.unlockpt(pfd);
				unowned string s = Posix.ptsname(pfd);
				print("%s <=> %s\n",addr, s);
				ioreader();
			} else {
				close_session();
			}
		}
	}

	private void ioreader() {
		ioreader_async.begin((obj,res) => {
				int bres = ioreader_async.end(res);
				if(verbose) {
					MWPLog.message("End of reader (%d)", bres);
				}
				close_session();
			});
	}

	private async int ioreader_async () {
		var thr = new Thread<int> ("mwp-ble", () => {
				uint8 buf[512];
				int done = 0;
				while (done == 0) {
					var nw = Posix.read(pfd, buf, 20);
					if (nw > 0) {
						Posix.write(wrfd, buf, nw);
					} else if (nw < 0) {
						if(Posix.errno == Posix.EAGAIN) {
							Thread.usleep(1000);
						} else {
							done = Posix.errno;
						}
					} else {
						done =  -3;
					}
					var nr = Posix.read(rdfd, buf, 512);
					if (nr > 0) {
						Posix.write(pfd, buf, nr);
					} else if (nr < 0) {
						if(Posix.errno == Posix.EAGAIN) {
							Thread.usleep(1000);
						} else {
							done = Posix.errno;
						}
					} else {
						done =  -3;
					}
				}
				Idle.add (ioreader_async.callback);
				return done;
			});
		yield;
		return thr.join();
	}

	private bool on_sigint () {
		close_session();
		return Source.REMOVE;
    }

	private void on_startup() {	}

	private void on_shutdown() {
	}
}

public static int main (string[] args) {
	var ga = new GattTest();
	ga.run(args);
	return 0;
}
