
const string AFILE="/run/readsb/aircraft.pb";

public uint8 * serialise_u32(uint8* rp, uint32 v) {
	*rp++ = v & 0xff;
	*rp++ = ((v >> 8) & 0xff);
	*rp++ = ((v >> 16) & 0xff);
	*rp++ = ((v >> 24) & 0xff);
	return rp;
}

public static int main (string[] args) {
	SList<Socket> slist = new SList<Socket>();
	int port = 37007;
	string fpath = AFILE;

	var options = new OptionEntry[] {
		{"port", 'p', 0, OptionArg.INT, &port, "TCP Port", null},
		{"acfile", 'f', 0, OptionArg.STRING, out fpath, "File path", null},
		{null}
		};

	try {
		var opt = new OptionContext(" - dump1090 JSON server");
		opt.set_help_enabled(true);
		opt.add_main_entries(options, null);
		opt.parse(ref args);
	} catch (OptionError e) {
        stderr.printf("Error: %s\n", e.message);
        stderr.printf("Run '%s --help' to see a full list of available "+
                      "options\n", args[0]);
        return 1;
    }

	try {
		SocketService service = new SocketService ();
		File file = File.new_for_path (fpath);
		FileMonitor monitor = file.monitor (FileMonitorFlags.NONE, null);
		print ("Monitoring: %s for [::]:%d\n", file.get_path(), port);

		monitor.changed.connect ((src, dest, event) => {
				if(event == FileMonitorEvent.CHANGES_DONE_HINT) {
					if(slist.length() != 0) {
						Posix.Stat st;
						if(Posix.stat(fpath, out st) == 0) {
							uint8[] buf = new uint8[st.st_size];
							if (buf != null) {
								FileStream fs= FileStream.open (fpath, "r");
								fs.read(buf, st.st_size);
								slist.@foreach((skt) => {
										try {
											uint8 sz[4];
											serialise_u32(sz, (uint)st.st_size);
											skt.send(sz);
											skt.send(buf);
										} catch (Error e) {
											stderr.printf("send %s\n", e.message);
										}
									});
							}
						}
					}
				}
		});

		service.add_inet_port ((uint16)port, null);
		service.incoming.connect ((conn, s) => {
				var skt = conn.get_socket();
				var fd = skt.get_fd();
				slist.append(skt);
				var io_read = new IOChannel.unix_new(fd);
				io_read.add_watch(IOCondition.IN|IOCondition.HUP|
											IOCondition.NVAL|IOCondition.ERR, (io,cond) => {
									  var fd_ = io.unix_get_fd();
									  try {
										  unowned var sl = slist.search(fd_, (s,f) => {
												  return (s.get_fd() - (int)((int64)f));
											  });
										  io.shutdown(true);
										  slist.remove(sl.data);
									  } catch  {}
									  return false;
								  });
				return false;
		});
		service.start ();
		MainLoop loop = new MainLoop ();
		loop.run ();
	} catch (Error e) {
		stderr.printf ("Error: %s\n", e.message);
	}
	return 0;
}
