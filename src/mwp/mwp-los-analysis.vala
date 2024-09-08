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

/*
 * Copyright (C) 2023 Jonathan Hudson <jh+mwptools@daria.co.uk>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

public class LOSPoint : Object {
	private static Shumate.MarkerLayer fmlayer;
	private static Shumate.PathLayer []players;
    private static MWPLabel fmpt;
	private static double xlat;
	private static double xlon;
	private static double xalt;
	public static bool is_init ;

	public static void init() {
        fmlayer = new Shumate.MarkerLayer(Gis.map.viewport);
        fmpt = new MWPLabel("⨁");
        fmpt.set_colour ("red");
        fmpt.set_text_colour("white");
		Gis.map.insert_layer_above (fmlayer, Gis.hm_layer); // above home layer
		fmlayer.add_marker(fmpt);
		fmlayer.hide();
		players = {};
	}

	public static void clear_los_lines() {
		clear_all();
		fmlayer.add_marker(fmpt);
	}

	public static void clear_all() {
		foreach(var p in players) {
			p.remove_all();
			Gis.map.remove_layer(p);
		}
		players = {};
		fmlayer.remove_all();
	}

	public static void show_los(bool state) {
		if(state) {
			fmlayer.show();
		} else {
			fmlayer.hide();
		}
	}

	public static void set_lospt(double lat, double lon, double relalt) {
        fmpt.set_location (lat, lon);
		xlat = lat;
		xlon = lon;
		xalt = relalt;
	}

    public static void get_lospt(out double lat, out double lon, out double relalt) {
        lat = xlat;
        lon = xlon;
		relalt = xalt;
    }

	public static void add_path(double lat0, double lon0, double lat1, double lon1, uint8 col,
								double ldist, int incr) {
		Gdk.RGBA green = {0.0f, 1.0f, 0.0f, 0.5f};
		Gdk.RGBA warning = {1.0f, 0.65f, 0.0f, 0.5f};
		Gdk.RGBA red = {1.0f, 0.0f, 0.0f, 0.5f};

        var pmlayer = new Shumate.PathLayer(Gis.map.viewport);
		var llist = new List<uint>();
        llist.append(5);
        llist.append(5);
        llist.append(15);
        llist.append(5);
		Gdk.RGBA wcol;
		switch(col) {
		case 0:
			wcol = green;
			break;
		case 1:
			wcol = warning;
			break;
		default:
			wcol = red;
			break;
		}
		if(incr < 8) {
			wcol.alpha = 0.2f;
		}

		pmlayer.set_stroke_color(wcol);
        pmlayer.set_dash(llist);
        pmlayer.set_stroke_width (6);
		var ip0 =  new  Shumate.Marker();
		ip0.latitude = lat0;
		ip0.longitude = lon0;
		pmlayer.add_node(ip0);
		ip0 =  new  Shumate.Marker();
		ip0.latitude = lat1;
		ip0.longitude = lon1;
		pmlayer.add_node(ip0);
		players += pmlayer;
		Gis.map.insert_layer_behind (pmlayer, Gis.mp_layer); // below mission path

		if(col != 0) {
			double c,d;
			double dlat, dlon;
			Geo.csedist(lat0, lon0, lat1, lon1, out d, out c);
			d *= ldist;
			Geo.posit(lat0, lon0, c, d, out dlat, out dlon);
			var dlos = new MWPPoint();
			var strcol = wcol.to_string();
			var cssstr =  ".map-point { min-width: 5px; min-height: 5px; background: %s; border: 1px solid %s; border-radius: 50%%; }".printf(strcol, strcol);
			dlos.set_css_style(cssstr);
			dlos.set_size_request(15,15);
			dlos.set_location (dlat, dlon);
			fmlayer.add_marker(dlos);
		}
	}
}

public class LOSSlider : Adw.Window {
	private const string AUTO_LOS = "Area LOS";
	private double maxd;
	private MissionPreviewer mt;
	private LegPreview []plist;
	private Gtk.Scale slider;
	private Gtk.Button button;
	private Gtk.Button abutton;
	private Gtk.Button cbutton;
	private Gtk.Button sbutton;
	private Gtk.Button ebutton;
	private Gtk.SpinButton mentry;
	private static bool is_running;
	private bool  _auto;
	private bool  _can_auto;
	private int _margin;
	private bool mlog;
	private int incr;
	private GLib.Subprocess? los;
	public signal void new_margin(int m);

	public void set_log(bool _mlog) {
		mlog = _mlog;
	}

	private void update_from_pos(double ppos) {
		var pdist = maxd*ppos / 1000.0;
		var j = 0;
		for (; j < plist.length; j++) {
			if(plist[j].dist >= pdist) {
				break;
			}
		}
		double slat, slon, amsl;

		int salt, ealt;
		var k = plist[j].p1;
		if (k == -1) {
			slat = HomePoint.hp.latitude;
			slon = HomePoint.hp.longitude;
			salt = 0;
		} else {
			slat =  mt.get_mi(k).lat;
			slon =  mt.get_mi(k).lon;
			salt = mt.get_mi(k).alt;
			if (mt.get_mi(k).param3 == 1) {
				if ((amsl = DemManager.lookup(slat, slon)) != Hgt.NODATA) {
					salt -= (int)amsl;
				}
			}
		}

		k = plist[j].p2;
		if (k == -1) {
			ealt = 0;
		} else {
			ealt = mt.get_mi(k).alt;
			if (mt.get_mi(k).param3 == 1) {
				if ((amsl = DemManager.lookup(slat, slon)) != Hgt.NODATA) {
					ealt -= (int)amsl;
				}
			}
		}

		var deltad = 0.0;
		if (j != 0) {
			deltad = pdist - plist[j-1].dist;
		} else {
			deltad = pdist;
		}

		var csed = plist[j].cse;
		double nlat, nlon;
		Geo.posit(slat, slon, csed, deltad/1852.0, out nlat, out nlon);
		double dalt;
		dalt = (ealt - salt);
		var palt =  deltad / plist[j].legd;
		var fdalt = salt + dalt*palt;
		LOSPoint.set_lospt(nlat, nlon, fdalt);
	}

	private void reset_slider_buttons() {
		var ppos = slider.get_value ();
		if(ppos < 1) {
			button.sensitive = false;
			abutton.sensitive = _can_auto;
		} else if  (ppos > 999) {
			button.sensitive = (plist[plist.length-1].p2 != -1); // last is home
			abutton.sensitive = false;
		} else if (!_auto) {
			button.sensitive = true;
			abutton.sensitive = _can_auto;
		}
		if (!_auto) {
			update_from_pos(ppos);
		}
	}


	private void set_marker_state(bool state) {
		var mklist =  Gis.mm_layer.get_markers();
		for (unowned GLib.List<weak Shumate.Marker> lp = mklist.first(); lp != null; lp = lp.next) {
			unowned MWPMarker m = lp.data as MWPMarker;
			m.set_draggable(state);
		}
		//Gis.mm_layer.sensitive = state; // dims the markers, not wanted
	}

	public LOSSlider (int lmargin) {
		_can_auto = true;
		_margin = lmargin;
		this.title = "LOS Analysis";
		var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
		var header_bar = new Adw.HeaderBar();
		box.append(header_bar);

		slider = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 1000, 1);
		slider.set_format_value_func ((s,v) => {
				return "%.1f%%".printf(v/10.0);
			});
		slider.draw_value = true;
		slider.value_changed.connect (() => {
				reset_slider_buttons();
			});

		slider.hexpand = true;
		var hbox =  new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
		var mlab = new Gtk.Label("Margin (m):");

		mentry = new Gtk.SpinButton.with_range (0, 120, 1);
		mentry.value = _margin;

		var sbox = new Gtk.Box(Gtk.Orientation.HORIZONTAL,1);
		sbutton = new  Gtk.Button.from_icon_name("media-skip-backward");
		ebutton = new  Gtk.Button.from_icon_name("media-skip-forward");
		sbutton.clicked.connect(() => {
				slider.set_value(0);
			});
		ebutton.clicked.connect(() => {
				slider.set_value(1000);
			});
		sbox.append(sbutton);
		sbox.append (slider); // ex t,f
		sbox.append(ebutton);
		box.append(sbox);
		incr = 10;

		Gdk.ModifierType astate = 0;
		var bbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL,4);
		abutton = new Gtk.Button.with_label (AUTO_LOS);
		var abc= new Gtk.GestureClick();
		abutton.add_controller(abc);
		abc.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);

		abc.pressed.connect((n,x,y) => {
				astate = abc.get_current_event_state();
			});
		abutton.clicked.connect(() => {
				if (abutton.label == AUTO_LOS) {
					_margin = mentry.get_value_as_int ();
					var ppos = slider.get_value ();
					abutton.label = "Stop";
					incr = 10;
					if ((astate & (Gdk.ModifierType.SHIFT_MASK|Gdk.ModifierType.CONTROL_MASK)) != 0) {
						incr = 2;
					}
					auto_run((int)ppos);
				} else {
					abutton.label = AUTO_LOS;
					is_running = false;
					if (los != null) {
						try {
							los.get_stdin_pipe().close();
						} catch {}
					}
				}
			});

		abutton.sensitive=_can_auto;
		button = new Gtk.Button.with_label ("Point LOS");
		button.clicked.connect(() => {
				Utils.terminate_plots();
				_margin = mentry.get_value_as_int ();
				run_elevation_tool();
				send_los_location();
				cbutton.sensitive = true;
			});

		cbutton = new Gtk.Button.with_label ("Clear");
		cbutton.clicked.connect(() => {
				LOSPoint.clear_los_lines();
				cbutton.sensitive = false;
			});
		cbutton.sensitive = false;
		bbox.append (button);
		bbox.append (abutton);
		bbox.append (cbutton);
		box.append(hbox);
		hbox.append(mlab);
		hbox.append (mentry);
		hbox.append(bbox);
		default_width = 600;
		set_transient_for (Mwp.window);

		if (LOSPoint.is_init == false) {
			LOSPoint.init();
		}

		this.close_request.connect(() => {
				_margin = mentry.get_value_as_int ();
				new_margin(_margin);
				is_running = false;
				if (los != null) {
					if (los != null) {
						try {
							los.get_stdin_pipe().close();
						} catch {}
					}
				}
				LOSPoint.clear_all();
				Utils.terminate_plots();
				set_marker_state(true);
				return false;
			});
		this.set_content(box);
		this.present();
	}

	public void run(Mission ms, int wpno, bool auto) {
		_auto = auto;
		set_marker_state(false);
		mt = new MissionPreviewer();
		mt.is_mr = true; // otherwise, gets confused by POSHOLD
		plist =  mt.check_mission(MissionManager.current(), false);
		maxd =  plist[plist.length-1].dist;
		LOSPoint.show_los(true);
		var pct = 0;
		if (_auto == false) {
			var j = 0;
			if (wpno != -1) {
				for (; j < plist.length; j++) {
					if(plist[j].p2 + 1 == wpno) {
						break;
					}
				}
				var adist = plist[j].dist;
				pct = (int)(1000.0*adist/maxd);
			}
			slider.set_value(pct);
		} else {
			incr = 10;
			auto_run(0);
		}
	}

	private void auto_run(int dp) {
		Utils.terminate_plots();
		slider.sensitive = false;
		button.sensitive = false;
		mentry.sensitive = false;
		cbutton.sensitive = false;
		sbutton.sensitive = false;
		ebutton.sensitive = false;

		is_running = true;
		_auto = true;
		abutton.label = "Stop";
		update_from_pos((double)dp);
		slider.set_value((double)dp);
		run_elevation_tool();
		send_los_location();
	}

	void send_los_location() {
        double lat,lon;
		double alt;
		var ppos = slider.get_value ();
		if(ppos < incr) {
			slider.set_value(incr);
			update_from_pos(incr);
		}
		LOSPoint.get_lospt(out lat, out lon, out alt);
		var losstr = "%.8f,%.8f,%.0f\n".printf(lat, lon, alt);
		try {
			los.get_stdin_pipe().write(losstr.data);
		} catch (Error e) {
			MWPLog.message("LOS write %s\n", e.message);
		}
	}

	private void auto_reset() {
		slider.sensitive = true;
		mentry.sensitive = true;
		abutton.label = AUTO_LOS;
		cbutton.sensitive = true;
		sbutton.sensitive = true;
		ebutton.sensitive = true;
		_auto = false;
		is_running = false;
		reset_slider_buttons();
	}

	private void run_elevation_tool() {
		string[] spawn_args = {"mwp-plot-elevations"};
		if (_auto) {
			spawn_args += "-no-graph";
		}

		spawn_args += "-localdem=%s".printf(DemManager.demdir);
		spawn_args += "-margin=%d".printf(_margin);
        spawn_args += "-home=%.8f,%.8f".printf(	HomePoint.hp.latitude, HomePoint.hp.longitude);
		spawn_args += "-stdin";
		if (mlog) {
			MWPLog.message("LOS DBG %s\n", string.joinv(" ",spawn_args));
		}

		bool ok = false;
		try {
			los = new Subprocess.newv(spawn_args, SubprocessFlags.STDOUT_PIPE|SubprocessFlags.STDIN_PIPE);
			read_spipe(los.get_stdout_pipe());
			los.wait_check_async.begin(null, (obj,res) => {
					try {
						ok =  los.wait_check_async.end(res);
						if (mlog) {
							MWPLog.message("LOS DBG Spawn End %s\n", ok.to_string());
						}
					}  catch (Error e) {
						MWPLog.message("LOS Spawn %s\n", e.message);
					}
				});
		} catch (Error e) {
			MWPLog.message("LOS Spawn %s\n", e.message);
		}
    }

	void read_spipe(InputStream s) {
		uint8  mbuf[10];
		s.read_async.begin(mbuf, GLib.Priority.DEFAULT, null, (obj,res) => {
				try {
					var slen = s.read_async.end(res);
					if (slen == 10) {
						uint8 losc  = (uint8)int.parse(((string)mbuf)[0:1]);
						double ldist = double.parse(((string)mbuf)[2:mbuf.length]);
						if (!_auto || is_running) {
							double lat,lon;
							double alt;
							LOSPoint.get_lospt(out lat, out lon, out alt);
							Idle.add(() => {
									LOSPoint.add_path(
										HomePoint.hp.latitude,HomePoint.hp.longitude,
										lat, lon, losc, ldist, incr);
									return false;
								});
							if(_auto) {
								var ppos = slider.get_value ();
								ppos += incr;
								if (ppos > 1000) {
									slider.set_value(1000.0);
									try {
										los.get_stdin_pipe().close();
									} catch (Error e) {
										MWPLog.message("LOS e close %s\n", e.message);
									}
									auto_reset();
								} else {
									slider.set_value(ppos);
									update_from_pos(ppos);
									send_los_location();
								}
								read_spipe(s);
							} else {
								try {
									los.get_stdin_pipe().close();
								} catch (Error e) {
									MWPLog.message("LOS p close %s\n", e.message);
								}
							}
						}
					} else {
						try {
							los.get_stdin_pipe().close();
						} catch (Error e) {
							MWPLog.message("LOS 0 close %s\n", e.message);
						}
						auto_reset();
					}
				} catch (Error e) {
					MWPLog.message("LOS ra end %s\n", e.message);
				}
			});
	}

}
