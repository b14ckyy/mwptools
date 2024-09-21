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
 */

[DBus (name = "org.freedesktop.NetworkManager")]
interface NetworkManager : GLib.Object {
    public signal void StateChanged (uint32 state);
    public abstract uint32 State {owned get;}
}

[DBus (name = "org.gnome.Shell.Screenshot")]
interface ScreenShot : GLib.Object {
    public abstract void ScreenshotArea (int x, int y, int width, int height,
                                          bool flash, string filename,
                                          out bool success,
                                          out string filename_used) throws Error;
}

public enum NMSTATE {
        UNKNOWN=0, ASLEEP=1, CONNECTING=2, CONNECTED=3, DISCONNECTED=4,
        NM_STATE_ASLEEP           = 10,
        NM_STATE_DISCONNECTED     = 20,
        NM_STATE_DISCONNECTING    = 30,
        NM_STATE_CONNECTING       = 40,
        NM_STATE_CONNECTED_LOCAL  = 50,
        NM_STATE_CONNECTED_SITE   = 60,
        NM_STATE_CONNECTED_GLOBAL = 70
}

namespace MWPAlert {
    public const string RED = "bleet.ogg";
    public const string ORANGE = "orange.ogg";
    public const string GENERAL = "beep-sound.ogg";
    public const string SAT = "sat_alert.ogg";
}


public struct CurrData {
    bool ampsok;
    uint16 centiA;
    uint32 mah;
    uint16 bbla;
    uint64 lmahtm;
    uint16 lmah;
}

public struct Odostats {
	time_t atime;
    double speed;
    double distance;
    double alt;
    double range;
    uint16 amps; // cenitamps
    uint time;
    uint alt_secs;
    uint spd_secs;
    uint rng_secs;
	string cname;
	bool live;
}

public struct VersInfo {
    uint8 mrtype;
    uint8 mvers;
    MWChooser.MWVAR fctype;
    string fc_var;
    string board;
    string name;
    string fc_git;
    uint16 fc_api;
    uint32 fc_vers;
}

public struct TelemStats {
    SerialStats s;
    ulong toc;
    int tot;
    ulong avg;
}

public struct BatteryLevels {
    float cell;
    float limit;
    string colour;
    string audio;
    string label;
    bool reached;
    public BatteryLevels(float _cell, string? _colour, string? _audio, string? _label) {
        cell = _cell;
        limit = 0f;
        colour = _colour;
        audio = _audio;
        label = _label;
        reached = false;
    }
}

public struct FakeOffsets {
    double dlat;
    double dlon;
    bool faking;
}

public class VCol {
    public BatteryLevels [] levels = {
        BatteryLevels(3.7f, "volthigh", null, null),
        BatteryLevels(3.57f, "voltmedium", null, null),
        BatteryLevels(3.47f, "voltlow", MWPAlert.ORANGE, null),
        BatteryLevels(3.0f,  "voltcritical", MWPAlert.RED, null),
        BatteryLevels(2.0f, "voltundef", null, "n/a")
    };
}

public struct MavPOSDef {
    uint16 minval;
    uint16 maxval;
    uint8 chan;
    uint8 set;
}

namespace MwpMenu {
    public void set_menu_state(GLib.ActionMap w, string action, bool state) {
        var ac = w.lookup_action(action) as SimpleAction;
		if (ac != null) {
			ac.set_enabled(state);
		}
    }
}

namespace Misc {
    public bool get_primary_size(out Gdk.Rectangle rect) {
		rect={};
		bool ret = true;
        Gdk.Display dp = Gdk.Display.get_default();
        var mons = dp.get_monitors();
        if(mons != null)
            rect = ((Gdk.Monitor)mons.get_item(0)).get_geometry();
        else
            ret = false;
        return ret;
    }
}


namespace PosFormat  {
    public string lat(double _lat, bool dms) {
        if(dms == false)
            return "%.6f".printf(_lat);
        else
            return position(_lat, "%02d:%02d:%04.1f%c", "NS");
    }

    public string lon(double _lon, bool dms) {
        if(dms == false)
            return "%.6f".printf(_lon);
        else
            return position(_lon, "%03d:%02d:%04.1f%c", "EW");
    }

	public string pos(double _lat, double _lon, bool dms, bool with_elev=false) {
		StringBuilder sb = new StringBuilder();
		double elev = Hgt.NODATA;
		if(with_elev) {
			elev = DemManager.lookup(_lat, _lon);
		}
		var slat = lat(_lat,dms);
		var slon = lon(_lon,dms);
		sb.append(slat);
		sb.append_c(' ');
		sb.append(slon);
		if (elev != Hgt.NODATA) {
			sb.append_printf(" %.0f%s", Units.distance(elev), Units.distance_units());
		}
		return sb.str;
    }

    private string position(double coord, string fmt, string ind) {
        var neg = (coord < 0.0);
        var ds = Math.fabs(coord);
        int d = (int)ds;
        var rem = (ds-d)*3600.0;
        int m = (int)rem/60;
        double s = rem - m*60;
        if ((int)s*10 == 600) {
            m+=1;
            s = 0;
        }
        if (m == 60) {
            m = 0;
            d+=1;
        }
        var q = (neg) ? ind.get_char(1) : ind.get_char(0);
        return fmt.printf((int)d,(int)m,s,q);
    }
}

namespace SportDev {
	bool active;
    int32 lat;
    int32 lon;
    double cse;
    double spd;
    int32 alt;
    double galt;
    uint16 rhdop;
    int16 pitch;
    int16 roll;
    uint8 fix;
    uint8 sats;
    uint8 flags;
    double ax;
    double ay;
    double az;
    uint16 range;
    uint16 rssi;
    int16 vario;
    double volts;
}


namespace Utils {
	public int get_row_at(Gtk.Widget w, double x,  double y) {
		// from  https://discourse.gnome.org/t/gtk4-finding-a-row-data-on-gtkcolumnview/8465
		var  child = w.get_first_child();
		Gtk.Allocation alloc = { 0, 0, 0, 0 };
		var line_no = -1;
		var reading_header = true;
		var curr_y = 0;
		var header_height  = 0;

		while (child != null) {
			if (reading_header) {
				if (child.get_type().name() == "GtkColumnViewRowWidget") {
					child.get_allocation(out alloc);
				}
				if (child.get_type().name() != "GtkColumnListView") {
					child = child.get_next_sibling();
					continue;
				}
				child = child.get_first_child();
				header_height = alloc.y + alloc.height;
				curr_y = header_height;
				reading_header = false;
			}
			if (child.get_type().name() != "GtkColumnViewRowWidget") {
				child = child.get_next_sibling();
				continue;
			}
			line_no++;
			child.get_allocation(out alloc);
			if (y > curr_y && y <= header_height + alloc.height + alloc.y ) {
				return line_no;
			}
			curr_y = header_height + alloc.height + alloc.y;
			child = child.get_next_sibling();
		}
		return -1;
	}

	private string trimfp(double val) {
        string stext;
        if (val > 9.95)
            stext = "%3.0f".printf(val);
        else
            stext = "%.1f".printf(val);
        return stext;
    }

	public void terminate_plots() {
		try {
			var kplt = new Subprocess(0, "pkill", "gnuplot");
			kplt.wait_check_async.begin(null, (obj,res) => {
					try {
						kplt.wait_check_async.end(res);
					}  catch {}
				});
		} catch {}
	}

    public string mstempname(bool xlate = true) {
        var t = Environment.get_tmp_dir();
        var ir = new Rand().int_range (0, 0xffffff);
        var s = Path.build_filename (t, ".mi-%d-%08x.xml".printf(Posix.getpid(), ir));
        if (xlate && MwpMisc.is_cygwin())
            s = MwpMisc.get_native_path(s);
        return s;
    }

	public void warning_box(string warnmsg,	int timeout = 0) {
		uint tid = 0;
		var am = new Adw.MessageDialog(Mwp.window, "MWP Message",  warnmsg);

		am. set_body_use_markup (true);
		am.add_response ("ok", "OK");
		am.response.connect((s) => {
				if(tid != 0) {
					Source.remove(tid);
				}
			});
		am.present();
		if(timeout > 0) {
            tid = Timeout.add_seconds_once(timeout, () => {
					tid = 0;
                    am.close();
                });
		}
	}
}

namespace  UpdateFile {
    private void save(string filename, string key, string keyline) {
		string headerln = "# %s".printf(key);
        if(FileUtils.test(filename, FileTest.EXISTS)) {
			string keyspc = "%s ".printf(key);
            string []lines = {};
            string s;
            bool written = false;
			bool header = false;

            FileStream fs = FileStream.open (filename, "r");
            while((s = fs.read_line()) != null)
                lines += s;

            fs = FileStream.open (filename, "w");
            foreach (var l in lines) {
				if(l.has_prefix(headerln))
				   header = true;

                if(l.has_prefix(keyspc)) {
                    if (written == false) {
						if(!header) {
							fs.puts(headerln);
							fs.putc('\n');
						}
						fs.puts(keyline);
                        written = true;
                    }
                } else {
                    fs.puts(l);
                    fs.puts("\n");
                }
            }
            if (written == false) {
				if(!header) {
					fs.puts(headerln);
					fs.putc('\n');
				}
				fs.puts(keyline);
			}
        } else {
            FileStream fs = FileStream.open (filename, "w");
            fs.puts(headerln);
			fs.putc('\n');
			fs.puts(keyline);
        }
    }
}


namespace Rebase {
	struct Point {
		double lat;
		double lon;
	}
	Point orig;
	Point reloc;
	uint8 status;

	public void set_reloc(double rlat, double rlon) {
		reloc.lat = rlat;
		reloc.lon = rlon;
		status |= 1;
	}

	public void set_origin(double olat, double olon) {
		status |= 2;
		orig.lat = olat;
		orig.lon = olon;
	}

	public bool has_reloc() {
		return ((status & 1) == 1);
	}

	public bool has_origin() {
		return ((status & 2) == 2);
	}

	public bool is_valid() {
		return ((status & 3) == 3);
	}

	public void relocate(ref double lat, ref double lon) {
		if (is_valid()) {
			double c,d;
			Geo.csedist(orig.lat, orig.lon, lat, lon, out d, out c);
			Geo.posit(reloc.lat, reloc.lon, c, d, out lat, out lon);
		}
	}
}

namespace LLparse {
	bool llparse(string llstr, ref double clat, ref double clon, ref uint zm) {
		var llok = false;
		string[] delims =  {","," "};
		var nps = 0;
		foreach (var delim in delims) {
			var parts = llstr.split(delim);
			if(parts.length >= 2) {
				foreach(var pp in parts) {
					var ps = pp.strip();
					if(InputParser.posok(ps)) {
						switch (nps) {
						case 0:
							clat = InputParser.get_latitude(ps);
							nps = 1;
							break;
						case 1:
							clon = InputParser.get_longitude(ps);
							nps = 2;
							break;
						case 2:
							zm = int.parse(parts[2]);
							break;
						default:
							break;
						}
					}
				}
				if (nps >= 2) {
					llok = true;
					break;
				}
			}
		}

		if (!llok) {
			var pls = Places.get_places();
			foreach(var pl in pls) {
				if (pl.name == llstr) {
					llok = true;
					clat = pl.lat;
					clon = pl.lon;
					if (pl.zoom > -1) {
						zm = (uint)pl.zoom;
					}
					break;
				}
			}
		}
		return llok;
	}
}

namespace CatMap {
	public struct CatIconDesc {
		string name;
		uint   idx;
	}
	public const int MAXICONS = 13;
	private	CatIconDesc[] name_for_type;

	public void init() {
		name_for_type = {
			CatIconDesc(){name="A0", idx=0},
			CatIconDesc(){name="A1", idx=1},  // "cessna",       // A1
			CatIconDesc(){name="A2", idx=2},  // "jet_nonswept", // A2
			CatIconDesc(){name="A3", idx=3},  // "airliner", 	// A3
			CatIconDesc(){name="A4", idx=4},  // "heavy_2e",		// A4
			CatIconDesc(){name="A5", idx=5},  // "heavy_4e",		// A5
			CatIconDesc(){name="A6", idx=6},  // "hi_perf",		// A6
			CatIconDesc(){name="A7", idx=7},  // "helicopter",	// A7
			CatIconDesc(){name="A0", idx=0},			// B0
			CatIconDesc(){name="A1", idx=1},  // "cessna",		// B1
			CatIconDesc(){name="B2", idx=8},  //balloon",		// B2
			CatIconDesc(){name="A0", idx=0},			// B3
			CatIconDesc(){name="A1", idx=1},  //"cessna",		// B4
			CatIconDesc(){name="A0", idx=0},			// B5
			CatIconDesc(){name="A0", idx=0},			// B6
			CatIconDesc(){name="A6", idx=6},  // "hi_perf",		// B7
			CatIconDesc(){name="C0", idx=9},  // "ground_unknown",   // C0
			CatIconDesc(){name="C1", idx=10}, // "ground_emergency", // C1
			CatIconDesc(){name="C2", idx=11}, // "ground_service",   // C2
			CatIconDesc(){name="C3", idx=12}, // "ground_fixed",     // C3
			CatIconDesc(){name="C3", idx=12},// "ground_fixed",     // C4
			CatIconDesc(){name="C3", idx=12}, // "ground_fixed",		// C5
			CatIconDesc(){name="C0", idx=9}, // "ground_unknown",   // C6
			CatIconDesc(){name="C0", idx=9},// "ground_unknown",   // C7
		};
	}

	public CatIconDesc name_for_category(uint8 etype) {
		CatIconDesc s;
		if(etype < name_for_type.length) {
			s = name_for_type[etype];
		} else {
			s = name_for_type[0];
		}
		return s;
	}

	public string? name_for_index(uint8 idx) {
		foreach(var c in name_for_type) {
			if(c.idx == idx) {
				return c.name;
			}
		}
		return null;
	}

	uint8 from_category(string s) {
		uint8 et;
		et = 8*(s.data[0]-'A') + (s.data[1]-'0');
		return et;
	}

	string to_category(uint8 et) {
		uint8 s[3];
		s[0] = 'A'+et/8;
		s[1] = '0'+et%8;
		s[2] = 0;
		return (string)s;
	}

}