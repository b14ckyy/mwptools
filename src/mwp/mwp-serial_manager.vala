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

namespace Mwp  {
    Mwp.MQI lastmsg;
    Queue<Mwp.MQI?> mq;
	MWSerial msp;
	Forwarder fwddev;
	bool mqtt_available;
	int autocount;
#if MQTT
    MwpMQTT mqtt;
#endif

}

namespace Msp {
	public void init(TrackDataSet v=0xff) {
		Mwp.mqtt_available = false;
		Mwp.autocount= 0;
		Mwp.msp = new MWSerial();
        Mwp.lastp = new Timer();
		Mwp.lastp.start();
		Mwp.msp.is_main = true;
		Mwp.msp.td = new TrackData(v);
		Mwp.mq = new Queue<Mwp.MQI?>();
        Mwp.lastmsg = Mwp.MQI(); //{cmd = Msp.Cmds.INVALID};
		Mwp.csdq = new Queue<string>();
		Mwp.fwddev = new Forwarder(Mwp.forward_device);
        Mwp.msp.serial_lost.connect(() => {
				close_serial();
			});

        Mwp.msp.serial_event.connect((cmd,raw,len,xflags,errs) => {
                Mwp.handle_serial(Mwp.msp, cmd,raw,len,xflags,errs);
            });

        Mwp.msp.crsf_event.connect((raw) => {
				CRSF.ProcessCRSF(Mwp.msp, raw);
            });

        Mwp.msp.flysky_event.connect((raw) => {
				Flysky.ProcessFlysky(Mwp.msp, raw);
            });

        Mwp.msp.sport_event.connect((id,val) => {
                Frsky.process_sport_message (Mwp.msp, (SportDev.FrID)id, val);
            });

		if(Mwp.serial != null) {
            Mwp.prepend_combo(Mwp.dev_combox, Mwp.serial);
            Mwp.dev_combox.active = 0;
        }

        Mwp.start_poll_timer();

#if MQTT
        Mwp.mqtt = newMwpMQTT();
		MQTT.init();
        Mwp.mqtt.mqtt_mission.connect((w,n) => {
				if(n > 0) {
					Mwp.wpmgr = {};
					for(var j = 0; j < n; j++) {
						Mwp.wpmgr.wps += w[j];
					}
					Mwp.wpmgr.npts = (uint8)n;
					var ms = MissionManager.current();
					if (ms != null) {
						MsnTools.clear(ms);
					}
					var mmsx = MultiM.wps_to_missonx(Mwp.wpmgr.wps);
					var nwp = MissionManager.check_mission_length(mmsx);
					if(nwp > 0) {
						MissionManager.msx = mmsx;
						MissionManager.mdx = 0;
						MissionManager.setup_mission_from_mm();
					}
				}
            });

		mqtt.mqtt_frame.connect((cmd, raw, len) => {
                Mwp.handle_serial(Mwp.msp, cmd, raw, (uint)len, 0, false);
            });

        mqtt.mqtt_craft_name.connect((s) => {
                Mwp.vname = s;
                Mwp.set_typlab();
            });
#endif
	}

	public void handle_connect() {
		//if(Mwp.msp.available || Mwp.mqtt_available) {
		if (Mwp.window.conbutton.label == "Disconnect") {
			close_serial();
		} else {
			connect_serial();
		}
	}

	public void close_serial() {
		// FIXME
		//        if(is_shutdown == true)
        //    return;

		if(!Mwp.zznopoll) {
			if(Mwp.xnopoll != Mwp.nopoll)
				Mwp.nopoll = Mwp.xnopoll;
		}
        MWPLog.message("Serial doom replay %d\n", Mwp.replayer);
		Mwp.csdq.clear();

        if(Mwp.inhibit_cookie != 0) {
            Mwp.window.application.uninhibit(Mwp.inhibit_cookie);
            Mwp.inhibit_cookie = 0;
            Mwp.dtnotify.send_notification("mwp", "Unhibit screen/idle/suspend");
            MWPLog.message("Not managing screen / power settings\n");
        }
		//        map_hide_wp(); // FIXME
        if(Mwp.replayer == Mwp.Player.NONE) {
            Safehome.manager.online_change(0);
            Mwp.window.arm_warn.hide();
            Mwp.serstate = Mwp.SERSTATE.NONE;
            Mwp.sflags = 0;
            if (Mwp.conf.audioarmed == true) {
                Mwp.window.audio_cb.active = false;
            }
            Mwp.show_serial_stats();
            if(Mwp.rawlog == true) {
                Mwp.msp.raw_logging(false);
            }

            Mwp.gpsstats = {0, 0, 0, 0, 9999, 9999, 9999};
            Mwp.nsats = 0;
            Mwp._nsats = 0;
            Mwp.last_tm = 0;
            Mwp.last_ga = 0;
            if (Mwp.msp.available) {
				Mwp.msp.td.alt.vario = 0;
                Mwp.msp.close();
                TelemTracker.ttrk.enable(Mwp.msp.get_devname());
#if MQTT
			} else if (Mwp.mqtt_available) {
				Mwp.mqtt_available = Mwp.mqtt.mdisconnect();
#endif
            } else {
				MWPLog.message(" Already closed %s\n", Mwp.msp.get_devname());
			}

            Mwp.window.conbutton.set_label("Connect");
            Mwp.set_mission_menus(false);
            MwpMenu.set_menu_state(Mwp.window, "navconfig", false);
            Mwp.duration = -1;
			//craft.remove_marker();
			//Mwp.init_have_home();
            Mwp.xsensor = 0;
            Mwp.clear_sensor_array();
        } else {
            Mwp.show_serial_stats();
            if (Mwp.msp.available)
                Mwp.msp.close();
            Mwp.replayer = Mwp.Player.NONE;
        }

		if(Mwp.fwddev != null && Mwp.fwddev.available()) {
			Mwp.fwddev.close();
		}
        Mwp.set_replay_menus(true);
        Mwp.reboot_status();
		if(Mwp.gzone != null) {
			if(Mwp.gz_from_msp) {
				Mwp.gzr.dump(Mwp.gzone, Mwp.vname);
				Mwp.gzone.remove();
				Mwp.gzone = null;
				Mwp.gzr.reset();
				Mwp.set_gzsave_state(false);
				Mwp.gz_from_msp = false;
			}
		}
        if((Mwp.replayer & (Mwp.Player.BBOX|Mwp.Player.OTX|Mwp.Player.RAW)) == 0) {
            if(Mwp.sh_load == "-FC-") {
                Safehome.manager.remove_homes();
            }
        }
		//markers.remove_rings(view);
		Mwp.window.verlab.label = Mwp.window.verlab.tooltip_text = "";
		Mwp.window.typlab.set_label("");
		Mwp.window.mmode.set_label("");
		MwpMenu.set_menu_state(Mwp.window, "followme", false);
	}

	private uint8 pmask_to_mask(uint j) {
		switch(j) {
		case 0:
			return 0xff;
		default:
			return (uint8)(1 << (j-1));
		}
	}

	private void serial_complete_setup(string serdev, bool ostat) {
		Mwp.window.conbutton.sensitive = true;
		if (ostat == true) {
			Mwp.xarm_flags=0xffff;
			Mwp.lastrx = Mwp.lastok = Mwp.nticks;
			Mwp.init_state();
			Mwp.init_sstats();
			MWPLog.message("Connected %s (nopoll %s)\n", serdev, Mwp.nopoll.to_string());
			Mwp.set_replay_menus(false);
			if(Mwp.rawlog == true) {
				Mwp.msp.raw_logging(true);
			}
			Mwp.window.conbutton.set_label("Disconnect");
			if(Mwp.forward_device != null) {
				Mwp.fwddev.try_open(Mwp.msp);
			}
			if (!Mwp.mqtt_available) {
				var pmsk = Mwp.window.protodrop.selected;
				var pmask = (MWSerial.PMask)pmask_to_mask(pmsk);
				set_pmask_poller(pmask);
				Mwp.msp.setup_reader();
				var cmode = Mwp.msp.get_commode();
				MWPLog.message("Serial %s (%x) ready %s\n", serdev, cmode, Mwp.nopoll.to_string());
				if(Mwp.nopoll == false && !Mwp.mqtt_available) {
					Mwp.serstate = Mwp.SERSTATE.NORMAL;
					Mwp.queue_cmd(Msp.Cmds.IDENT,null,0);
					Mwp.run_queue();
				} else
					Mwp.serstate = Mwp.SERSTATE.TELEM;
			}
		} else {
			string estr = null;
			Mwp.msp.get_error_message(out estr);
			if (Mwp.autocon == false || Mwp.autocount == 0) {
				Utils.warning_box("""Unable to open serial device:
Error: <i>%s</i>

* Check that <u>%s</u> is available / connected.
* Please verify you are a member of the owning group, typically 'dialout' or 'uucp'""".printf(estr, serdev), 0);
		   }
 		   Mwp.autocount = ((Mwp.autocount + 1) % 12);
		}
		Mwp.reboot_status();
	}

    private void connect_serial() {
		CRSF.teledata.setlab = false;
		//		SportDev.active = false;
		RSSI.set_title(RSSI.Title.RSSI);
		var serdev = Mwp.dev_entry.text;
		bool ostat = false;
		Mwp.serstate = Mwp.SERSTATE.NONE;
		if(Radar.lookup_radar(serdev) || serdev == Mwp.forward_device) {
			Utils.warning_box("The selected device is assigned to a special function (radar / forwarding).\nPlease choose another device", 60);
			return;
		} else if (serdev.has_prefix("mqtt://") ||
				   serdev.has_prefix("ssl://") ||
				   serdev.has_prefix("mqtts://") ||
				   serdev.has_prefix("ws://") ||
				   serdev.has_prefix("wss://") ) {
#if MQTT
			Mwp.mqtt_available = ostat = mqtt.setup(serdev);
			Mwp.rawlog = false;
			Mwp.nopoll = true;
			Mwp.window.autocon.active = false;
			Mwp.serstate = Mwp.SERSTATE.TELEM;
			serial_complete_setup(serdev, ostat);
#else
			Utils.warning_box("MQTT is not enabled in this build\nPlease see the wiki for more information\nhttps://github.com/stronnag/mwptools/wiki/mqtt---bulletgcss-telemetry\n", 60);
			return;
#endif
		} else {
			if (TelemTracker.ttrk.is_used(serdev)) {
				Utils.warning_box("The selected device is use for Telemetry Tracking\n", 60);
				return;
			}
			TelemTracker.ttrk.disable(serdev);
			MWPLog.message("Trying OS open for %s\n", serdev);
			Mwp.window.conbutton.sensitive = false;
			Mwp.msp.open_async.begin(serdev, Mwp.conf.baudrate, (obj,res) => {
					ostat = Mwp.msp.open_async.end(res);
					serial_complete_setup(serdev,ostat);
				});
		}
    }

	private void try_reopen(string devname) {
        if(!Mwp.autocon) {
			Timeout.add(2000, () => {
					var serdev = Mwp.dev_entry.text.split(" ")[0];
					if (serdev != devname) {
						return true;
					}
					if (!Mwp.msp.available) {
						connect_serial();
					}
					return false;
				});
		}
	}

	private void set_pmask_poller(MWSerial.PMask pmask) {
		if (pmask == MWSerial.PMask.AUTO || pmask == MWSerial.PMask.INAV) {
			if (!Mwp.zznopoll) {
				Mwp.nopoll = false; // FIXNOPOLL
			}
		} else {
			Mwp.xnopoll = Mwp.nopoll;
			Mwp.nopoll = true;
		}
		Mwp.msp.set_pmask(pmask);
		Mwp.msp.set_auto_mpm(pmask == MWSerial.PMask.AUTO);
	}
}