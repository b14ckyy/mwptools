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

namespace Radar {
	public void display() {
		if(radarv.vis) {
			radarv.visible=false;
		} else {
			radarv.present();
		}
		radarv.vis = !radarv.vis;
	}

	public void update(uint rk, bool verbose) {
		radarv.update(rk, verbose);
	}

	public bool upsert(uint k, RadarPlot v) {
		return radar_cache.upsert(k,v);
	}

	private static bool do_purge = false;

	private void radar_periodic() {
		Toast.range = TOTHEMOON;
		Toast.id = 0;

		var now = new DateTime.now_local();
		for(var i = 0; i < radar_cache.size(); i++) {
			var r = radar_cache.get_item(i);
			if (r != null) {
				uint rk = r.id;
				var is_adsb = ((r.source & RadarSource.M_ADSB) != 0);
				if (do_purge) {
					var staled = LateTime.STALE*TimeSpan.SECOND;
					var hided = LateTime.HIDE*TimeSpan.SECOND;;
					var deled = LateTime.DELETE*TimeSpan.SECOND;
					if (!is_adsb) {
						staled *= 10;
						deled *= 10;
						hided *= 10;
					}
					var delta = now.difference(r.dt);
					bool rdebug = ((Mwp.debug_flags & Mwp.DebugFlags.RADAR) != Mwp.DebugFlags.NONE);
					var xstate = r.state;
					if (delta > deled) {
						if (rdebug) {
							MWPLog.message("TRAF-DEL %X %u %s %s len=%u\n",
										   rk, r.state, r.dt.format("%T"),
										   is_adsb.to_string(), radar_cache.size());
						}
						if(is_adsb) {
							var dsec = delta / TimeSpan.SECOND;
							r.lq = (dsec > 255) ? 255 : (uint8)dsec;
							radarv.remove(rk);
							Radar.remove_radar(rk);
							radar_cache.remove(rk);
						}
					} else if(delta > hided) {
						if(rdebug)
							MWPLog.message("TRAF-HID %X %s %u %u\n",
										   rk, r.name, r.state, radar_cache.size());
						if(is_adsb) {
							var dsec = delta / TimeSpan.SECOND;
							r.lq = (dsec > 255) ? 255 : (uint8)dsec;
							r.state = Radar.Status.HIDDEN; // hidden
							if (r.state != xstate) {
								r.alert = RadarAlert.SET;
							}
							radar_cache.upsert(rk, r);
							radarv.update(rk, ((Mwp.debug_flags & Mwp.DebugFlags.RADAR) != Mwp.DebugFlags.NONE));
							if (r.posvalid) {
								Radar.set_radar_hidden(rk);
							}
						}
					} else if(delta > staled) {
						if(rdebug)
							MWPLog.message("TRAF-STALE %X %s %u %u\n", rk, r.name, r.state, radar_cache.size());
						r.state = Radar.Status.STALE; // stale
						if (r.state != xstate) {
							r.alert = RadarAlert.SET;
						}
						radar_cache.upsert(rk, r);
						radarv.update(rk, ((Mwp.debug_flags & Mwp.DebugFlags.RADAR) != Mwp.DebugFlags.NONE));
						if(r.posvalid) {
							Radar.set_radar_stale(rk);
						}
					} else {
						if(is_adsb) {
							r.state = 0;
							if (r.state != xstate) {
								r.alert = RadarAlert.SET;
							}
							radar_cache.upsert(rk, r);
							radarv.update(rk, ((Mwp.debug_flags & Mwp.DebugFlags.RADAR) != Mwp.DebugFlags.NONE));
						}
					}
				}
				do_purge = !do_purge;
				if(r.state < Radar.Status.STALE) {
					if((r.alert &  RadarAlert.ALERT) ==  RadarAlert.ALERT) {
						if(r.range < Toast.range) {
							Toast.id = rk;
							Toast.range = r.range;
						}
					}
				}
			}
		}
		if(Toast.id != 0) {
			if(( Radar.astat & Radar.AStatus.A_TOAST) == Radar.AStatus.A_TOAST) {
				var r = radar_cache.lookup(Toast.id);
				if (r != null) {
					var msg = "ADSB proximity %s %s@%s \u21d5%s".printf(r.name, format_range(r), format_bearing(r), format_alt(r));
					if(Toast.toast == null) {
						Toast.toast = Mwp.add_toast_text(msg, 0);
						Toast.toast.dismissed.connect(() => {
								Toast.toast = null;
							});
					} else {
						Toast.toast.set_title(msg);
					}
				} else {
					if(Toast.toast != null) {
						Toast.toast.dismiss();
						Toast.toast = null;
					}
				}
				if(((Radar.astat & Radar.AStatus.A_SOUND) == Radar.AStatus.A_SOUND) && r.range < r.last_range) {
					if(Radar.do_audio) {
						Audio.play_alarm_sound(MWPAlert.GENERAL);
					}
				}
			}
		} else {
			if(Toast.toast != null) {
				Toast.toast.dismiss();
				Toast.toast = null;
			}
		}
	}

	public class RadarView : Adw.Window {
		internal bool vis;
		private int64 last_sec;
		Gtk.Label label;
		Gtk.Button[] buttons;

		Gtk.ColumnView cv;
		Gtk.NoSelection lsel;

		bool vhidden;

		enum Buttons {
			CENTRE,
			HIDE,
			CLOSE
		}

		~RadarView() {
			for (var i = 0; i < items.get_n_items(); i++) {
				var r = items.get_item(i) as RadarDev;
				if (r.tid != 0) {
					Source.remove(r.tid);
				}
				if(r.dtype == IOType.MSER && r.dev != null && ((MWSerial)r.dev).available) {
					((MWSerial)r.dev).close();
				}
			}
		}

		public static string[] status = {"Undefined", "Armed", "Hidden", "Stale"};

		private void label_alert(RadarPlot r, Gtk.Label l) {
			if((r.alert & RadarAlert.ALERT) != 0 &&
			   (Radar.astat & Radar.AStatus.A_RED) == Radar.AStatus.A_RED) {
				l.add_css_class("error");
			} else {
				l.remove_css_class("error");
			}
		}

		private void create_cv() {
			cv = new Gtk.ColumnView(null);
			var filterz = new Gtk.CustomFilter((o) => {
					if(Mwp.conf.max_radar_altitude > 0 &&
					   ((RadarPlot)o).altitude > Mwp.conf.max_radar_altitude) {
						return false;
					}
					return true;
				});

			var fm = new Gtk.FilterListModel (radar_cache.lstore, filterz);
			var sm = new Gtk.SortListModel(fm, cv.sorter);
			lsel = new Gtk.NoSelection(sm);
			cv.set_model(lsel);
			cv.show_column_separators = true;
			cv.show_row_separators = true;

			var f0 = new Gtk.SignalListItemFactory();
			var c0 = new Gtk.ColumnViewColumn("*", f0);
			var expression = new Gtk.PropertyExpression(typeof(RadarPlot), null, "source");
			c0.set_sorter(new Gtk.NumericSorter(expression));

			f0.setup.connect((f,o) => {
					Gtk.ListItem list_item = (Gtk.ListItem)o;
					var label=new Gtk.Label("");
					list_item.set_child(label);
				});
			f0.bind.connect((f,o) => {
					Gtk.ListItem list_item =  (Gtk.ListItem)o;
					RadarPlot r = list_item.get_item() as RadarPlot;
					var label = list_item.get_child() as Gtk.Label;
					label.label = ((RadarSource)r.source).source_id();
					r.notify["source"].connect((s,p) => {
							label.label =  ((RadarSource) ((RadarPlot)s).source)    .source_id();
						});
					r.notify["alert"].connect((s,p) => {label_alert((RadarPlot)s, label);});
				});
			cv.append_column(c0);

			f0 = new Gtk.SignalListItemFactory();
			c0 = new Gtk.ColumnViewColumn("Name", f0);
			c0.expand = true;
			expression = new Gtk.PropertyExpression(typeof(RadarPlot), null, "name");
			c0.set_sorter(new Gtk.StringSorter(expression));

			f0.setup.connect((f,o) => {
					Gtk.ListItem list_item = (Gtk.ListItem)o;
					var label=new Gtk.Label("");
					list_item.set_child(label);
				});

			f0.bind.connect((f,o) => {
					Gtk.ListItem list_item =  (Gtk.ListItem)o;
					RadarPlot r = list_item.get_item() as RadarPlot;
					var label = list_item.get_child() as Gtk.Label;
					r.bind_property("name", label, "label", BindingFlags.SYNC_CREATE);
					r.notify["alert"].connect((s,p) => {label_alert((RadarPlot)s, label);});
				});
			cv.append_column(c0);

			f0 = new Gtk.SignalListItemFactory();
			c0 = new Gtk.ColumnViewColumn("Latitude", f0);
			c0.expand = true;
			f0.setup.connect((f,o) => {
					Gtk.ListItem list_item = (Gtk.ListItem)o;
					var label=new Gtk.Label("");
					list_item.set_child(label);
				});
			f0.bind.connect((f,o) => {
					Gtk.ListItem list_item =  (Gtk.ListItem)o;
					RadarPlot r = list_item.get_item() as RadarPlot;
					var label = list_item.get_child() as Gtk.Label;
					label.label = PosFormat.lat(r.latitude, Mwp.conf.dms);
					r.notify["latitude"].connect((s,p) => {
							label.label = PosFormat.lat(((RadarPlot)s).latitude, Mwp.conf.dms);
						});
					r.notify["alert"].connect((s,p) => {label_alert((RadarPlot)s, label);});
				});
			cv.append_column(c0);

			f0 = new Gtk.SignalListItemFactory();
			c0 = new Gtk.ColumnViewColumn("Longitude", f0);
			c0.expand = true;
			f0.setup.connect((f,o) => {
					Gtk.ListItem list_item = (Gtk.ListItem)o;
					var label=new Gtk.Label("");
					list_item.set_child(label);
				});
			f0.bind.connect((f,o) => {
					Gtk.ListItem list_item =  (Gtk.ListItem)o;
					RadarPlot r = list_item.get_item() as RadarPlot;
					var label = list_item.get_child() as Gtk.Label;
					label.label = PosFormat.lon(r.longitude, Mwp.conf.dms);
					r.notify["longitude"].connect((s,p) => {
							label.label = PosFormat.lon(((RadarPlot)s).longitude, Mwp.conf.dms);
						});
					r.notify["alert"].connect((s,p) => {label_alert((RadarPlot)s, label);});
				});
			cv.append_column(c0);

			f0 = new Gtk.SignalListItemFactory();
			c0 = new Gtk.ColumnViewColumn("Altitude", f0);
			c0.expand = true;
			f0.setup.connect((f,o) => {
					Gtk.ListItem list_item = (Gtk.ListItem)o;
					var label=new Gtk.Label("");
					list_item.set_child(label);
				});
			f0.bind.connect((f,o) => {
					Gtk.ListItem list_item =  (Gtk.ListItem)o;
					RadarPlot r = list_item.get_item() as RadarPlot;
					var label = list_item.get_child() as Gtk.Label;
					label.label = format_alt(r);
					r.notify["altitude"].connect((s,p) => {
							label.label = format_alt((RadarPlot)s);
						});
					r.notify["alert"].connect((s,p) => {label_alert((RadarPlot)s, label);});
				});
			cv.append_column(c0);

			f0 = new Gtk.SignalListItemFactory();
			c0 = new Gtk.ColumnViewColumn("Course", f0);
			c0.expand = true;
			f0.setup.connect((f,o) => {
					Gtk.ListItem list_item = (Gtk.ListItem)o;
					var label=new Gtk.Label("");
					list_item.set_child(label);
				});
			f0.bind.connect((f,o) => {
					Gtk.ListItem list_item =  (Gtk.ListItem)o;
					RadarPlot r = list_item.get_item() as RadarPlot;
					var label = list_item.get_child() as Gtk.Label;
					label.label = format_course(r);
					r.notify["heading"].connect((s,p) => {
							label.label = format_course((RadarPlot)s);
						});
					r.notify["alert"].connect((s,p) => {label_alert((RadarPlot)s, label);});
				});
			cv.append_column(c0);

			f0 = new Gtk.SignalListItemFactory();
			c0 = new Gtk.ColumnViewColumn("Speed", f0);
			c0.expand = true;
			f0.setup.connect((f,o) => {
					Gtk.ListItem list_item = (Gtk.ListItem)o;
					var label=new Gtk.Label("");
					list_item.set_child(label);
				});
			f0.bind.connect((f,o) => {
					Gtk.ListItem list_item =  (Gtk.ListItem)o;
					RadarPlot r = list_item.get_item() as RadarPlot;
					var label = list_item.get_child() as Gtk.Label;
					label.label = format_speed(r);
					r.notify["speed"].connect((s,p) => {
							label.label = format_speed((RadarPlot)s);
						});
					r.notify["alert"].connect((s,p) => {label_alert((RadarPlot)s, label);});
				});
			cv.append_column(c0);

			f0 = new Gtk.SignalListItemFactory();
			c0 = new Gtk.ColumnViewColumn("Status", f0);
			expression = new Gtk.PropertyExpression(typeof(RadarPlot), null, "state");
			c0.set_sorter(new Gtk.NumericSorter(expression));
			f0.setup.connect((f,o) => {
					Gtk.ListItem list_item = (Gtk.ListItem)o;
					var label=new Gtk.Label("");
					list_item.set_child(label);

				});
			f0.bind.connect((f,o) => {
					Gtk.ListItem list_item =  (Gtk.ListItem)o;
					RadarPlot r = list_item.get_item() as RadarPlot;
					var label = list_item.get_child() as Gtk.Label;
					label.label = format_status(r);
					r.notify["state"].connect((s,p) => {
							label.label = format_status((RadarPlot)s);
						});
					r.notify["lq"].connect((s,p) => {
							label.label = format_status((RadarPlot)s);
						});
					r.notify["alert"].connect((s,p) => {label_alert((RadarPlot)s, label);});
				});
			cv.append_column(c0);

			f0 = new Gtk.SignalListItemFactory();
			c0 = new Gtk.ColumnViewColumn("Last", f0);
			c0.expand = true;
			var dtsorter = new Gtk.CustomSorter((a,b) => {
					return (int)((RadarPlot)a).dt.difference(((RadarPlot)b).dt);
				});
			c0.set_sorter(dtsorter);
			f0.setup.connect((f,o) => {
					Gtk.ListItem list_item = (Gtk.ListItem)o;
					var label=new Gtk.Label("");
					list_item.set_child(label);
				});
			f0.bind.connect((f,o) => {
					Gtk.ListItem list_item =  (Gtk.ListItem)o;
					RadarPlot r = list_item.get_item() as RadarPlot;
					var label = list_item.get_child() as Gtk.Label;
					label.label = format_last(r);
					r.notify["dt"].connect((s,p) => {
							label.label = format_last((RadarPlot)s);
						});
					r.notify["alert"].connect((s,p) => {label_alert((RadarPlot)s, label);});
				});
			cv.append_column(c0);

			f0 = new Gtk.SignalListItemFactory();
			c0 = new Gtk.ColumnViewColumn("Range", f0);
			c0.expand = true;
			expression = new Gtk.PropertyExpression(typeof(RadarPlot), null, "range");
			c0.set_sorter(new Gtk.NumericSorter(expression));

			f0.setup.connect((f,o) => {
					Gtk.ListItem list_item = (Gtk.ListItem)o;
					var label=new Gtk.Label("");
					list_item.set_child(label);
				});
			f0.bind.connect((f,o) => {
					Gtk.ListItem list_item =  (Gtk.ListItem)o;
					RadarPlot r = list_item.get_item() as RadarPlot;
					var label = list_item.get_child() as Gtk.Label;
					label.label = format_range(r);
					r.notify["range"].connect((s,p) => {
							label.label = format_range((RadarPlot)s);
						});
					r.notify["alert"].connect((s,p) => {label_alert((RadarPlot)s, label);});
				});
			cv.append_column(c0);

			f0 = new Gtk.SignalListItemFactory();
			c0 = new Gtk.ColumnViewColumn("Bearing", f0);
			c0.expand = true;
			f0.setup.connect((f,o) => {
					Gtk.ListItem list_item = (Gtk.ListItem)o;
					var label=new Gtk.Label("");
					list_item.set_child(label);
				});
			f0.bind.connect((f,o) => {
					Gtk.ListItem list_item =  (Gtk.ListItem)o;
					RadarPlot r = list_item.get_item() as RadarPlot;
					var label = list_item.get_child() as Gtk.Label;
					label.label = format_bearing(r);
					r.notify["bearing"].connect((s,p) => {
							label.label = format_bearing((RadarPlot)s);
						});
					r.notify["alert"].connect((s,p) => {label_alert((RadarPlot)s, label);});
				});
			cv.append_column(c0);

			f0 = new Gtk.SignalListItemFactory();
			c0 = new Gtk.ColumnViewColumn("Cat", f0);
			c0.expand = true;
			expression = new Gtk.PropertyExpression(typeof(RadarPlot), null, "etype");
			c0.set_sorter(new Gtk.NumericSorter(expression));
			f0.setup.connect((f,o) => {
					Gtk.ListItem list_item = (Gtk.ListItem)o;
					var label=new Gtk.Label("");
					list_item.set_child(label);
				});
			f0.bind.connect((f,o) => {
					Gtk.ListItem list_item =  (Gtk.ListItem)o;
					RadarPlot r = list_item.get_item() as RadarPlot;
					var label = list_item.get_child() as Gtk.Label;
					label.label = format_cat(r);
					r.notify["etype"].connect((s,p) => {
							label.label = format_cat((RadarPlot)s);
						});
					r.notify["alert"].connect((s,p) => {label_alert((RadarPlot)s, label);});
				});
			cv.append_column(c0);

			var clm = cv.get_columns();
			//               * Nm  La  Lo  Al  Cse Spd Sts Lst Rng Brg Cat
			//               0  1   2   3   4   5   6   7   8 , 9, 19, 11
			int [] widths = {0 ,10, 14, 15, 10, 9, 10, 15, 11, 11,  9, 6};
			for (var j = 0; j < clm.get_n_items(); j++) {
				if(widths[j] != 0) {
					var cw = clm.get_item(j) as Gtk.ColumnViewColumn;
					cw.set_fixed_width(7*widths[j]);
					cw.resizable = true;
				}
			}
		}

		public RadarView () {
			set_transient_for(Mwp.window);
			vis = false;
			last_sec = 0;

			var sbox = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
			var tbox = new Adw.ToolbarView();
			var header_bar = new Adw.HeaderBar();
			var achkb = new Gtk.CheckButton.with_label("Audio Alerts");
			achkb.active = Radar.do_audio;
			achkb.toggled.connect(() => {
					Radar.do_audio = achkb.active;
				});

			header_bar.pack_end(achkb);
			tbox.add_top_bar(header_bar);

			var scrolled = new Gtk.ScrolledWindow ();
			set_default_size (900, 400);
			title = "Radar & Telemetry Tracking";
			label = new Gtk.Label ("");
			create_cv();
			cv.hexpand = true;
			cv.vexpand = true;
			scrolled.propagate_natural_height = true;
			scrolled.propagate_natural_width = true;
			scrolled.set_child(cv);

			buttons = {
				new Gtk.Button.with_label ("Centre on swarm"),
				new Gtk.Button.with_label ("Hide symbols"),
				new Gtk.Button.with_label ("Close")
			};

			vhidden = false;

			buttons[Buttons.HIDE].clicked.connect (() => {
					if(!vhidden) {
						buttons[Buttons.HIDE].label = "Show symbols";
						Gis.rm_layer.set_visible(false);
					} else {
						buttons[Buttons.HIDE].label = "Hide symbols";
						Gis.rm_layer.set_visible(true);
					}
					vhidden = !vhidden;
				});

			buttons[Buttons.CLOSE].clicked.connect (() => {
					visible=false;
					vis = false;
				});

			buttons[Buttons.CENTRE].clicked.connect (() => {
					zoom_to_swarm();
				});

			buttons[Buttons.CENTRE].sensitive = false;
			var bbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
            // The number of pixels to place between children:
			bbox.set_spacing (5);

            // Add buttons to our ButtonBox:
			foreach (unowned Gtk.Button button in buttons) {
				button.halign = Gtk.Align.END;
				bbox.append (button);
			}

			Gtk.Box box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 5);
			box.append(label);
			label.xalign = 0;
			label.hexpand = true;

			bbox.halign = Gtk.Align.END;
			bbox.hexpand = true;

			sbox.append(scrolled);

			box.add_css_class("toolbar");
			box.append(bbox);

			tbox.add_bottom_bar(box);

			tbox.set_content (sbox);
			set_content (tbox);
			close_request.connect (() => {
					visible=false;
					vis = false;
					return true;
				});
		}

		private void zoom_to_swarm() {
			int n = 0;
			double alat = 0;
			double alon = 0;

			for(var j = 0; j < Radar.radar_cache.size(); j++) {
				var r = Radar.radar_cache.get_item(j) as RadarPlot;
				alat += r.latitude;
				alon += r.longitude;
				n++;
			}
			if(n != 0) {
				alat /= n;
				alon /= n;
				MapUtils.centre_on(alat, alon);
			}
		}

		private void show_number() {
			uint n_rows = Radar.radar_cache.size();
			uint stale = 0;
			uint hidden = 0;

			buttons[Buttons.CENTRE].sensitive = (n_rows != 0);

			//print("--------------- Start Cache -----------------\n");
			for(var j = 0; j < n_rows; j++) {
				var r = Radar.radar_cache.get_item(j);
				if(r.state == Radar.Status.STALE) {
					stale++;
				} else if(r.state == Radar.Status.HIDDEN) {
					hidden++;
				}
				/*
				var m0 = Radar.find_radar_item(r.id);
				string status= " ";
				if(m0 == null) {
					status = "*";
				}
				print (" %s %s %x %x %d", status, r.name, r.state, r.id, r.lq);
				if(m0 != null) {
					print(" %.3f %.3f", m0.latitude, m0.longitude);
				}
				print("\n");
				*/
			}
			var sb = new StringBuilder("Targets: ");
			uint live = n_rows - stale - hidden;
			sb.append_printf("%u", n_rows);
			if (live > 0 && (stale+hidden) > 0)
				sb.append_printf("\tLive: %u", live);
			if (stale > 0)
				sb.append_printf("\tStale: %u", stale);
			if (hidden > 0)
				sb.append_printf("\tHidden: %u", hidden);
			label.set_text (sb.str);
			//print ("%s\n", sb.str);
			//print("--------------- done Cache -----------------\n");
		}

		public void remove (uint rid) {
			var found = Radar.radar_cache.remove (rid);
			if (found) {
				show_number();
			} else {
				MWPLog.message("Radar view failed for %X\n", rid);
			}
		}

		public void update (uint rk, bool verbose = false) {
			double idm = TOTHEMOON;

			var r = Radar.radar_cache.lookup(rk);
			if (r == null)
				return;

			var alert = r.alert;
			var xalert = r.alert;

			r.last_range = r.range;
			if(Radar.astat > Radar.AStatus.C_MAP) {
				double c,d;
				Geo.csedist(Radar.lat, Radar.lon, r.latitude, r.longitude, out d, out c);
				idm = d*1852.0; // nm to m
				r.range = idm;
				r.bearing = (uint16)c;
			} else {
				if(r.srange != 0xffffffff) {
					r.range = (double)(r.srange);
				}
				r.bearing = 0xffff;
			}

			if(!vhidden && (r.source & RadarSource.M_ADSB) != 0 && r.bearing != 0xffff) {
				if(r.speed > Mwp.conf.radar_alert_minspeed  &&
				   Mwp.conf.radar_alert_altitude > 0 && Mwp.conf.radar_alert_range > 0 &&
				   r.altitude < Mwp.conf.radar_alert_altitude && r.range < Mwp.conf.radar_alert_range) {
					xalert = RadarAlert.ALERT;
				} else {
					xalert = RadarAlert.NONE;
				}
			}
			if (alert != xalert) {
				xalert |= RadarAlert.SET;
				r.alert = xalert;
			}
			if(r.state >= RadarView.status.length)
				r.state = Status.UNDEF;
			show_number();
		}
	}
}
