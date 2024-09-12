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

using Gtk;

namespace Mwp {
	MWPSettings conf;
	Gtk.ComboBoxText dev_combox;
	Gtk.Entry dev_entry;
	DevManager devman;
	public Mwp.Window window;
	public Adw.ToastOverlay toaster;
	public StrIntStore amis;
	double current_lat;
	double current_lon;
	double current_elev;
	TileUtils.Dialog msd;
	Measurer.Measure dmeasure;
	MwpNotify dtnotify;
	Gtk.Label sensor_sts[6];
	Craft craft;
	GeoZoneManager gzr;
	uint8 gzcnt;
	private Overlay? gzone;
	private GZEdit gzedit;

	[GtkTemplate (ui = "/org/stronnag/mwp/mwpmain.ui")]
	public class Window : Adw.ApplicationWindow {
		[GtkChild]
		internal unowned Adw.ToastOverlay toaster;
		[GtkChild]
		internal unowned Adw.OverlaySplitView split_view;
		[GtkChild]
		internal unowned Gtk.SpinButton zoomlevel;
		[GtkChild]
		internal unowned Gtk.Label poslabel;
		[GtkChild]
		internal unowned Gtk.DropDown mapdrop;
		[GtkChild]
		internal unowned Gtk.DropDown protodrop;
		[GtkChild]
		internal unowned Gtk.DropDown actmission;
		[GtkChild]
		internal unowned Gtk.Box devbox;
		[GtkChild]
		internal unowned Gtk.MenuButton button_menu;
		[GtkChild]
		internal unowned Gtk.ToggleButton wpeditbutton;
		[GtkChild]
		internal unowned Gtk.Button conbutton;
		[GtkChild]
		internal unowned  Gtk.CheckButton autocon;
		[GtkChild]
		internal unowned Gtk.Label gpslab;
		[GtkChild]
		internal unowned Gtk.Label gyro_sts;
		[GtkChild]
		internal unowned Gtk.Label acc_sts;
		[GtkChild]
		internal unowned Gtk.Label baro_sts;
		[GtkChild]
		internal unowned Gtk.Label mag_sts;
		[GtkChild]
		internal unowned Gtk.Label gps_sts;
		[GtkChild]
		internal unowned Gtk.Label sonar_sts;
		[GtkChild]
		internal unowned Gtk.Label elapsedlab;
		[GtkChild]
		internal unowned Gtk.Label validatelab;
		[GtkChild]
		internal unowned Gtk.Label missionlab;
		[GtkChild]
		internal unowned Gtk.Spinner armed_spinner;
		[GtkChild]
		internal unowned Gtk.Label statusbar1;
		[GtkChild]
		internal unowned Gtk.Label typlab;
		[GtkChild]
		internal unowned Gtk.Label verlab;
		[GtkChild]
		internal unowned Gtk.Label mmode;
		[GtkChild]
		internal unowned Gtk.Label fmode;
		[GtkChild]
		internal unowned Gtk.CheckButton follow_button;
		[GtkChild]
		internal unowned Gtk.DropDown viewmode;
		[GtkChild]
		internal unowned Gtk.CheckButton logger_cb;
		[GtkChild]
		internal unowned Gtk.CheckButton audio_cb;
		[GtkChild]
		internal unowned Gtk.Button arm_warn;

		private StrIntStore pis;

		private Mwp.GotoDialog posdialog;
		private Mwp.SCWindow scwindow;

		public Window (Adw.Application app) {
            Object (application: app);
			mapdrop.factory = null;
			protodrop.factory = null;
			actmission.factory = null;

			Mwp.window = this;
			Mwp.toaster = toaster;

			var builder = new Builder.from_resource ("/org/stronnag/mwp/mwpmenu.ui");
			var menubar = builder.get_object("menubar") as MenuModel;
			button_menu.menu_model = menubar;

			// behave like grownup menus ...
			button_menu.always_show_arrow = false;
			var popover = button_menu.popover as Gtk.PopoverMenu;
			popover.has_arrow = false;
#if MODERN_GTK
			popover.flags = Gtk.PopoverMenuFlags.NESTED;
#endif
			setup_accels(app);
			setup_misc_controls();
			close_request.connect(() => {
					MapManager.killall();
					app.remove_window(this);
					return false;
				});
			init_basics();

			setup_terminal_reboot();
			follow_button.active = conf.autofollow;
			show_window();
		}

		private void init_basics() {
			conf = new MWPSettings();
			if(conf.uilang == "en") {
				Intl.setlocale(LocaleCategory.NUMERIC, "C");
			}
			devman = new DevManager(conf.bluez_disco);
			devman.device_added.connect((dd) => {
					string s = devname_for_dd(dd);
					if(dev_is_bt(dd) || Mwp.msp.available)
						append_combo(dev_combox, s);
					else
						prepend_combo(dev_combox, s);
				});
			devman.device_removed.connect((s) => {
					remove_combo(dev_combox, s);
				});
			build_serial_combo();
			Places.get_places();
			posdialog = new Mwp.GotoDialog();
			scwindow = new Mwp.SCWindow();
			GstDev.init();
			TelemTracker.init();
			conbutton.clicked.connect(() => {
					Msp.handle_connect();
				});

			logger_cb.toggled.connect (() => {
					if (logger_cb.active) {
						Logger.start(conf.logsavepath, vname);
						if(armed != 0) {
							string devnam = null;
							if(msp.available) {
								devnam = dev_entry.text;
							}
							Logger.fcinfo(MissionManager.last_file,vi,capability,profile, null,
										  vname, devnam, boxids);
							if(gzone != null) {
								Logger.logstring("geozone", gzr.to_string());
							}
						}
					} else {
						Logger.stop();
					}
            });

			sensor_sts[0] = gyro_sts;
			sensor_sts[1] = acc_sts;
			sensor_sts[2] = baro_sts;
			sensor_sts[3] = mag_sts;
			sensor_sts[4] = gps_sts;
			sensor_sts[5] = sonar_sts;
		}

		private void show_window() {
			if (!no_max) {
				maximize();
			} else {
				Gdk.Rectangle r;
				if(Misc.get_primary_size(out r)) {
					int w = (r.width*conf.window_scale)/100;
					int h = (r.height*conf.window_scale)/100;
					set_default_size(w, h);
				}
			}
			DemManager.init();
			Gis.init();
			Gis.map.viewport.notify["zoom-level"].connect(() => {
					var val = (int)Gis.map.viewport.zoom_level;
					var zval = (int)zoomlevel.value;
					if (val != zval)
						zoomlevel.value = (int)val;
            });

			zoomlevel.value_changed.connect(()=> {
					Gis.map.viewport.zoom_level = zoomlevel.value;
				});


			wpeditbutton.clicked.connect(() => {
					if(wpeditbutton.active) {
						if (HomePoint.hidden()) {
							double clat, clon;
							MapUtils.get_centre_location(out clat, out clon);
							HomePoint.set_home(clat, clon);
						}
					} else {
						if(MissionManager.msx.length==0) {
							HomePoint.try_hide();
						}
					}
				});

			arm_warn.clicked.connect(() => {
					show_arm_status();
				});

			var evtcm = new Gtk.EventControllerMotion();
			Gis.map.add_controller(evtcm);
			evtcm.motion.connect((x,y) => {
					Gis.map.viewport.widget_coords_to_location(Gis.base_layer, x, y,
															   out Mwp.current_lat,
															   out Mwp.current_lon);
					set_pos_label(Mwp.current_lat, Mwp.current_lon);
				});

			var gestc = new Gtk.GestureClick(); // Gtk.GestureLongPress();
			gestc.pressed.connect((n, x, y) => {
					if(wpeditbutton.active) {
						gestc.set_state(Gtk.EventSequenceState.CLAIMED);
						double lat, lon;
						Gis.map.viewport.widget_coords_to_location(Gis.base_layer, x,y,out lat, out lon);
						MissionManager.insert_new(lat, lon);
					} else if(Measurer.active) {
						gestc.set_state(Gtk.EventSequenceState.CLAIMED);
						double lat, lon;
						Gis.map.viewport.widget_coords_to_location(Gis.base_layer, x, y, out lat, out lon);
						dmeasure.add_point(lat, lon);
					}
				});
			Battery.init();
			hwstatus[0] = 1; // Assume OK
			Msp.init();
			Gis.map.add_controller(gestc);
			split_view.sidebar_width_unit = Adw.LengthUnit.SP;
			int fw,fh;
			check_pango_size(this, "Monospace", "_00:00:00.0N 000.00.00.0W_", out fw, out fh);
			// Must match 150% scaling in flight_view
			fw = 2+(150*fw)/100;
			split_view.min_sidebar_width = fw;
			split_view.content = Gis.overlay;
			Gis.setup_map_sources(mapdrop);
			FWPlot.init();
			MissionManager.init();
			Safehome.manager = new SafeHomeDialog();
			Mwp.window.split_view.sidebar = new Panel.Box();
			dtnotify = new MwpNotify();
			Cli.handle_options();
			Radar.init();
			craft = new Craft();
			DND.init();
			GCS.init();
			Odo.init();
			gzr = new GeoZoneManager();
			gzedit = new GZEdit();
			set_initial_states();
			msp.td.state.notify["ltmstate"].connect((s,p) => {
					bool mstate = false;
					if(msp.available) {
						if(serstate == SERSTATE.POLLER) {
							mstate = (((StateData)s).ltmstate ==  Msp.Ltm.POSHOLD);
						}
					}
					MwpMenu.set_menu_state(Mwp.window, "followme", mstate);
				});
		}

		private void set_initial_states() {
			set_mission_menus(false);
			reboot_status();
			set_replay_menus(true);
			string []opts={"stop-replay", "kml-remove", "gz-edit", "gz-save", "gz-kml", "gz-clear"};
			foreach(var o in opts) {
				MwpMenu.set_menu_state(Mwp.window, o, false);
			}
		}

		private void setup_misc_controls() {
			pis = new StrIntStore();
			protodrop.set_model(pis.model);
			protodrop.set_factory(pis.factory);
			pis.append(new StrIntItem("Auto", MWSerial.PMask.AUTO));
			pis.append(new StrIntItem("INAV", MWSerial.PMask.INAV));
			pis.append(new StrIntItem("S.Port", MWSerial.PMask.SPORT));
			pis.append(new StrIntItem("CRSF", MWSerial.PMask.CRSF));
			pis.append(new StrIntItem("MPM", MWSerial.PMask.MPM));

			amis = new StrIntStore();
			actmission.set_model(amis.model);
			actmission.set_factory(amis.factory);

			dev_combox = new Gtk.ComboBoxText.with_entry ();
			devbox.append(dev_combox);
			dev_combox.hexpand = true;
			dev_entry = dev_combox.get_child() as Gtk.Entry;
			dev_entry.set_width_chars(16);

			viewmode.notify["selected"].connect(() =>  {
					conf.view_mode =  viewmode.get_selected();
					if (conf.view_mode != 2) {
						Gis.map.viewport.rotation = 0;
					}
				});
		}

		private void launch_manual() {
			new Gtk.UriLauncher("https://stronnag.github.io/mwptools/").launch(null, null);
		}

		private void launch_posdialog() {
			posdialog.present();
		}

		private void launch_scwindow() {
			scwindow.present();
		}

		private void launch_safehomes() {
			Safehome.manager.display();
		}

		private void launch_radar() {
			Radar.display();
		}

		private void launch_bbl() {
			BBL.replay_bbl(null);
		}

		private void launch_etx() {
			ETX.replay_etx(null);
		}

		private void launch_raw() {
			Raw.replay_raw(null);
		}

		private void launch_json() {
			Mwpjs.replay_js(null);
		}

		private void set_def_loc() {
			double clat, clon;
			MapUtils.get_centre_location(out clat, out clon);
			conf.latitude = clat;
			conf.longitude = clon;
			conf.zoom = (uint)Gis.map.viewport.zoom_level;
		}

		private void get_location() {
			Clip.get_location(false);
		}
		private void fmt_get_location() {
			Clip.get_location(true);
		}

		private void mapseed() {
			Mwp.msd = new TileUtils.Dialog();
			msd.run_seeder();
		}

		private void start_measurer() {
			if (Measurer.active == false) {
				Mwp.dmeasure = new Measurer.Measure();
				Mwp.dmeasure.run();
			}
		}

		private void show_ttracker() {
			TelemTracker.ttrk.show_dialog();
		}

		private void show_odo() {
			Odo.view.unhide();
		}

		private void stop_replay() {
			Mwp.stop_replayer();
		}

		private void do_hard_reset() {
			 hard_display_reset(false);
		}

		private void do_mission_clear() {
			hard_mission_clear();
		}

		private void do_mission_upload() {
			upload_mm(MissionManager.mdx, WPDL.GETINFO|WPDL.SAVE_FWA);
		}

		private void do_missions_upload() {
			upload_mm(-1, WPDL.GETINFO|WPDL.SAVE_FWA|WPDL.SET_ACTIVE);
		}

		private void restore_mission() {
			uint8 zb=0;
			queue_cmd(Msp.Cmds.WP_MISSION_LOAD, &zb, 1);
		}

		private void store_mission() {
			upload_mm(-1, WPDL.SAVE_EEPROM|WPDL.SET_ACTIVE);
		}

		private void do_gz_save() {
			GZUtils.save_dialog(false);
		}

		private void do_gz_kml() {
			GZUtils.save_dialog(true);
		}

		private void do_gz_edit() {
			if(gzone == null) {
				gzone = new Overlay();
			}
			set_gzsave_state(true);
			gzedit.edit(gzone);
		}

		private void do_gz_clear() {
			if(gzone!=null) {
				gzedit.clear();
				gzone.remove();
			}
			gzr.reset();
			set_gzsave_state(false);
		}

		private void do_gz_dl() {
			gzr.reset();
			queue_gzone(0);
		}

		private void do_gz_ul() {
			gzcnt = 0;
			var mbuf = gzr.encode(gzcnt);
			queue_cmd(Msp.Cmds.SET_GEOZONE, mbuf, mbuf.length);
		}

		private void test_audio() {
			TTS.say(TTS.Vox.AUDIO_TEST);
		}

		private void run_prefs() {
			var prefs = new Prefs.Window();
			prefs.present();
			prefs.run();
		}

		private void setup_accels(Adw.Application app) {
			GLib.ActionEntry[] winacts = {
				{"quit",  Mwp.window.close},
				{"about",  About.show_about},
				{"centre-on",  launch_posdialog},
				{"keys", launch_scwindow},
				{"manual", launch_manual},
				{"kml-load", Kml.load_file},
				{"kml-remove", Kml.remove_kml},
				{"radar-view", launch_radar},
				{"mission-open", MissionManager.load_mission_file},
				{"mission-append", MissionManager.append_mission_file},
				{"mission-save", MissionManager.save_mission_file},
				{"mission-save-as", MissionManager.save_mission_file_as},
				{"mman", MissionManager.mm_manager},
				{"safe-homes", launch_safehomes},
				{"recentre", MissionManager.zoom_to_mission},
				{"defloc", set_def_loc},
				{"cliploc", get_location},
				{"fmtcliploc", fmt_get_location},
				{"seed-map", mapseed},
				{"dmeasure", start_measurer},
				{"replay-bb-log", launch_bbl},
				{"replay-etx-log", launch_etx},
				{"replay-raw-log", launch_raw},
				{"replay-mwp-log", launch_json},
				{"vstream", VideoMan.load_v4l2_video},
				{"ttrack-view", show_ttracker},
				{"flight-stats", show_odo},
				{"stop-replay", stop_replay},
				{"hardreset", do_hard_reset},
				{"clearmission", do_mission_clear},
				{"pausemission", do_mission_pause},
				{"upload-mission", do_mission_upload},
				{"upload-missions",do_missions_upload},
				{"download-mission", download_mission},
				{"restore-mission", restore_mission},
				{"store_mission", store_mission},
				{"gz-load", GZUtils.load_dialog},
				{"gz-save", do_gz_save},
				{"gz-kml", do_gz_kml},
				{"gz-edit", do_gz_edit},
				{"gz-clear", do_gz_clear},
				{"gz-dl", do_gz_dl},
				{"gz-ul", do_gz_ul},
				{"followme", Follow.run},
				{"audio-test", test_audio},
				{"prefs", run_prefs},
				{"toggle-fs", toggle_fs},
				{"go-home", go_home},
				{"handle-connect", Msp.handle_connect},
				{"show-serial-stats", show_serial_stats},
			};

            add_action_entries (winacts, this);

			var lsaq = new GLib.SimpleAction.stateful ("locicon", null, false);
			lsaq.change_state.connect((s) => {
					var b = s.get_boolean();
					double clat, clon;
					MapUtils.get_centre_location(out clat, out clon);
					GCS.default_location(clat, clon);
					GCS.set_visible(b);
					lsaq.set_state (s);
				});
			window.add_action(lsaq);

			app.set_accels_for_action ("win.about", { "<primary>a" });
			app.set_accels_for_action ("win.cliploc", { "<primary>l" });
			app.set_accels_for_action ("win.fmtcliploc", { "<primary><shift>l" });
			app.set_accels_for_action ("win.mission-open", { "<primary>m" });
			app.set_accels_for_action ("win.dmeasure", { "<primary>d" });
			app.set_accels_for_action ("win.hardreset", { "<primary>i" });
			app.set_accels_for_action ("win.clearmission", { "<primary>z" });
			app.set_accels_for_action ("win.pausemission", { "space" });

			app.set_accels_for_action ("win.go-home", { "<primary>h" });
			app.set_accels_for_action ("win.toggle-fs", { "F11" });
			app.set_accels_for_action ("win.handle-connect", { "<primary><shift>c" });
			app.set_accels_for_action ("win.show-serial-stats", { "<primary>s" });

			MwpMenu.set_menu_state(Mwp.window, "followme", false);
		}
	}

	private void go_home() {
		Gis.map.center_on(Mwp.conf.latitude, Mwp.conf.longitude);
	}

	private void toggle_fs() {
		if(window.maximized) {
			window.unmaximize();
		} else {
			window.maximize();
		}
	}

	private void do_mission_pause() {
		if(replayer != Player.NONE) {
			handle_replay_pause();
		}
	}

	public void set_pos_label(double lat, double lon) {
		if (!conf.pos_is_centre) {
			Mwp.window.poslabel.label = PosFormat.pos(lat, lon, Mwp.conf.dms, true);
		}
	}

	public bool set_zoom_sanely(double zval) {
        var sane = true;
        var mmax = Gis.map.viewport.get_max_zoom_level();
        var mmin = Gis.map.viewport.get_min_zoom_level();
        if (zval > mmax) {
            sane= false;
            Gis.map.viewport.zoom_level = mmax;
        } else if (zval < mmin) {
            sane = false;
            Gis.map.viewport.zoom_level = mmin;
        } else {
            Gis.map.viewport.zoom_level = zval;
		}
        return sane;
    }

	public void add_toast_text(string s) {
		Mwp.window.toaster.add_toast(new Adw.Toast(s));
	}

    public void clear_sensor_array() {
        xs_state = 0;
        for(int i = 0; i < 6; i++)
            sensor_sts[i].label = " ";
    }

    public void reboot_status() {
		var state = ((Mwp.msp != null && Mwp.msp.available && Mwp.armed == 0));
		MwpMenu.set_menu_state(Mwp.window, "reboot", state);
        MwpMenu.set_menu_state(Mwp.window, "terminal", state);
    }

    private void set_replay_menus(bool state) {
		const string [] ms = {
			"replay-mwp-log",
			"replay-bb-log",
			"replay-etx-log",
			"replay-raw-log"
		};
        var n = 0;
        foreach(var s in ms) {
            var istate = state;
			if( ((n == 1) && (x_fl2ltm == false))  ||
                ((n == 2) && (x_otxlog == false)) ||
                ((n == 3) && x_rawreplay == false)) {
                istate = false;
			}
            MwpMenu.set_menu_state(Mwp.window, s, istate);
            n++;
        }
    }

	private void set_mission_menus(bool state) {
        const string[] ms0 = {
			"store-mission",
			"restore-mission",
			"upload-mission",
			"download-mission",
			"navconfig",
			"mission-info"};
        foreach(var s in ms0) {
            MwpMenu.set_menu_state(Mwp.window, s, state);
		}

		if(Mwp.vi.fc_vers == 0 || Mwp.vi.fc_vers >= Mwp.FCVERS.hasWP_V4) {
			MwpMenu.set_menu_state(Mwp.window, "upload-missions", state);
		}
		if((feature_mask & Msp.Feature.GEOZONE) == 0) {
			state = false;
		}
		MwpMenu.set_menu_state(Mwp.window, "gz-dl", state);
		MwpMenu.set_menu_state(Mwp.window, "gz-ul", state);
	}

	void check_pango_size(Gtk.Widget w, string fname, string str, out int fw, out int fh) {
		var font = new Pango.FontDescription().from_string(fname);
		var context = w.get_pango_context();
		var layout = new Pango.Layout(context);
		layout.set_font_description(font);
		layout.set_text(str,  -1);
		layout.get_pixel_size(out fw, out fh);
	}


	void show_arm_status() {
		StringBuilder sb = new StringBuilder();
		if((xarm_flags & ~(ARMFLAGS.ARMED|ARMFLAGS.WAS_EVER_ARMED)) != 0) {
			sb.append("<b>Arm Status</b>\n");
			string arm_msg = get_arm_fail(xarm_flags,'\n');
			sb.append(arm_msg);
		}

		if(hwstatus[0] == 0) {
			sb.append("<b>Hardware Status</b>\n");
			for(var i = 0; i < 8; i++) {
				uint ihs = hwstatus[i+1];
				string shs = (ihs < health_states.length) ?
					health_states[ihs] : "*broken*";
				sb.append_printf("%s : %s\n", sensor_names[i], shs);
			}
		}

		var pop = new Gtk.Popover();
		Gtk.Label label = new Gtk.Label(sb.str);
		label.set_use_markup (true);
		pop.set_child(label);
		pop.set_parent(Mwp.window.arm_warn);
        pop.position = Gtk.PositionType.BOTTOM;
        pop.set_offset(0, 10);
		pop.set_has_arrow(true);
        pop.set_autohide(true);
		pop.popup();
	}

	private void set_gzsave_state(bool val) {
		MwpMenu.set_menu_state(Mwp.window, "gz-save", val);
		MwpMenu.set_menu_state(Mwp.window, "gz-kml", val);
		MwpMenu.set_menu_state(Mwp.window, "gz-clear", val);
		MwpMenu.set_menu_state(Mwp.window, "gz-edit", val);
	}

}
