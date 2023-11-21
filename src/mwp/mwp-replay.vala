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

public class ReplayThread : GLib.Object {
    private const int MAXSLEEP = 500*1000;
    private bool playon  {get; set;}
    private Cancellable cancellable;
    private bool paused = false;

	/*
	private uint8 parsehex(string t) {
		return (to_hexbin(t.data[0]) << 4) | (to_hexbin(t.data[1]) &0xf);
	}

	private uint8 to_hexbin(uint8 c) {
		if (c >= '0' && c <= '9')
			c = c - '0';
		else if (c >= 'A' && c <= 'F') {
			c = c - 'A' + 10;
		}
		else if (c >= 'a' && c <= 'f') {
			c = c - 'a' + 10;
		}
		return c;
	}
	*/
	private size_t serialise_sf(LTM_SFRAME b, uint8 []tx) {
        uint8 *p;
        p = SEDE.serialise_u16(tx, b.vbat);
        p = SEDE.serialise_u16(p, b.vcurr);
        *p++ = b.rssi;
        *p++ = b.airspeed;
        *p++ = b.flags;
        return (p - &tx[0]);
    }

    private size_t serialise_of(LTM_OFRAME o, uint8 []tx) {
        uint8 *p;
        p = SEDE.serialise_i32(tx, o.lat);
        p = SEDE.serialise_i32(p, o.lon);
        *p++ = 0;
        *p++ = 0;
        *p++ = 0;
        *p++ = 0;
        *p++ = 1;
        *p++ = o.fix;
        return (p - &tx[0]);
    }

    private size_t serialise_xf(LTM_XFRAME x, uint8 []tx) {
        uint8 *p;
        p = SEDE.serialise_u16(tx, x.hdop);
        *p++ = x.sensorok;
        *p++ = x.ltm_x_count;
        *p++ = x.disarm_reason;
        return (p - &tx[0]);
    }

    private size_t serialise_misc(MSP_MISC misc, uint8 [] tbuf) {
        uint8 *rp;
        rp = SEDE.serialise_u16(tbuf, misc.intPowerTrigger1);
        rp = SEDE.serialise_u16(rp, misc.conf_minthrottle);
        rp = SEDE.serialise_u16(rp, misc.maxthrottle);
        rp = SEDE.serialise_u16(rp, misc.mincommand);
        rp = SEDE.serialise_u16(rp, misc.failsafe_throttle);
        rp = SEDE.serialise_u16(rp, misc.plog_arm_counter);
        rp = SEDE.serialise_u32(rp, misc.plog_lifetime);
        rp = SEDE.serialise_i16(rp, misc.conf_mag_declination);
        *rp++ = misc.conf_vbatscale;
        *rp++ = misc.conf_vbatlevel_warn1;
        *rp++ = misc.conf_vbatlevel_warn2;
        *rp++ = misc.conf_vbatlevel_crit;
        return (rp - &tbuf[0]);
    }

    private size_t serialise_nav_status(MSP_NAV_STATUS b, uint8 []tx) {
        uint8 *p = tx;
        *p++ = b.gps_mode;
        *p++ = b.nav_mode;
        *p++ = b.action;
        *p++ = b.wp_number;
        *p++ = b.nav_error;
        p = SEDE.serialise_u16(p, b.target_bearing);
        return (p - &tx[0]);
    }

    private size_t serialise_alt(MSP_ALTITUDE b, uint8 []tx) {
        uint8 *p;
        p = SEDE.serialise_i32(tx, b.estalt);
        p = SEDE.serialise_i16(p, b.vario);
        return (p - &tx[0]);
    }

    private size_t serialise_raw_gps(MSP_RAW_GPS b, uint8 []tx) {
        uint8 *p = tx;
        *p++ = b.gps_fix;
        *p++ = b.gps_numsat;
        p = SEDE.serialise_i32(p, b.gps_lat);
        p = SEDE.serialise_i32(p, b.gps_lon);
        p = SEDE.serialise_i16(p, b.gps_altitude);
        p = SEDE.serialise_u16(p, b.gps_speed);
        p = SEDE.serialise_u16(p, b.gps_ground_course);
        p = SEDE.serialise_u16(p, b.gps_hdop);
        return (p - &tx[0]);
    }

    private size_t serialise_status(MSP_STATUS b, uint8 []tx) {
        uint8 *p;
        p = SEDE.serialise_u16(tx, b.cycle_time);
        p = SEDE.serialise_u16(p, b.i2c_errors_count);
        p = SEDE.serialise_u16(p, b.sensor);
        p = SEDE.serialise_u32(p, b.flag);
        *p++ = b.global_conf;
        return (p - &tx[0]);
    }

    private size_t serialise_radio(MSP_RADIO b, uint8 []tx) {
        uint8 *p;
        p = SEDE.serialise_u16(tx, b.rxerrors);
        p = SEDE.serialise_u16(p, b.fixed_errors);
        *p++ = b.localrssi;
        *p++ = b.remrssi;
        *p++ = b.txbuf;
        *p++ = b.noise;
        *p++ = b.remnoise;
        return (p - &tx[0]);
    }

    private size_t serialise_analogue(MSP_ANALOG b, uint8 []tx) {
        uint8 *p = tx;
        *p++ = b.vbat;
        p = SEDE.serialise_u16(p, b.powermetersum);
        p = SEDE.serialise_u16(p, b.rssi);
        p = SEDE.serialise_u16(p, b.amps);
        return (p - &tx[0]);
    }

    private size_t serialise_comp_gps(MSP_COMP_GPS b, uint8 []tx) {
        uint8 *p;
        p = SEDE.serialise_u16(tx, b.range);
        p = SEDE.serialise_i16(p, b.direction);
        *p++ = b.update;
        return (p - &tx[0]);
    }

    private size_t serialise_atti(MSP_ATTITUDE b, uint8 []tx) {
        uint8 *p;
        p = SEDE.serialise_i16(tx, b.angx);
        p = SEDE.serialise_i16(p, b.angy);
        p = SEDE.serialise_u16(p, b.heading);
        return (p - &tx[0]);
    }

    private void send_rec(MWSerial msp, MSP.Cmds cmd, size_t len, void *buf) {
        if(cmd < MSP.Cmds.LTM_BASE) {
            msp.send_command(cmd, buf, len);
        } else if (cmd < MSP.Cmds.MAV_BASE) {
            msp.send_ltm((uint8)(cmd - MSP.Cmds.LTM_BASE), buf, len);
        } else {
            msp.send_mav((uint8)(cmd - MSP.Cmds.MAV_BASE), buf, len);
        }
    }

    public ReplayThread() {
        cancellable = new Cancellable ();
    }

    public void stop() {
        playon = false;
        cancellable.cancel();
    }

    public void pause(bool _paused) {
        paused = _paused;
    }

    public Thread<int> run(int fd, string relog, bool delay=true) {
        MWSerial msp =  new MWSerial.forwarder();
        msp.open_fd(fd,115200);
        return run_msp(msp, relog, delay);
    }

    public Thread<int> run_msp (MWSerial msp, string relog, bool delay=true) {
        playon = true;
        var thr = new Thread<int> ("relog", () => {
                bool armed = false;
                double start_tm = 0;
                double utime = 0;
                uint16 lq = 0;
                double variodiv = 100.0;

                uint8 buf[1024];
                MSP_STATUS xa = MSP_STATUS();
                msp.set_mode(MWSerial.Mode.SIM);

                var file = File.new_for_path (relog);
                if (!file.query_exists ()) {
                    MWPLog.message ("File '%s' doesn't exist.\n", file.get_path ());
                } else {
                    string line=null;
                    try {
                        Thread.usleep(100000);
                        double lt = 0;
                        var dis = FileStream.open(relog,"r");
                        var parser = new Json.Parser ();
                        bool have_data = false;
                        bool have_init = false;
                        var telem = false;
                        uint profile = 0;
                        string fcvar = null;
                        uint fcvers = 0;
                        string vname  = null;

                        while (playon && (line = dis.read_line ()) != null) {
                            parser.load_from_data (line);
                            var obj = parser.get_root ().get_object ();
                            utime = obj.get_double_member ("utime");
                            if(start_tm == 0) {
                                start_tm = utime;
                                if (utime < 1610807618) { // vario log bug fixed 2021-01-16
                                    variodiv = 10;
                                }
                            }
                            if(lt != 0) {
                                ulong ms = 0;
                                if (delay  && have_data) {
                                    var dly = (utime - lt);
                                    ms = (ulong)(dly * 1000 *1000);
                                    if(dly > 10) {
                                        MWPLog.message("No data: replay sleeping for %.1f s\n", dly);
                                        ms = 2*1000;
                                    }
                                } else
                                    ms = 2*1000;
                                while(ms != 0) {
                                    cancellable.set_error_if_cancelled ();
                                    ulong st = (ms > MAXSLEEP) ? MAXSLEEP : ms;
                                    Thread.usleep(st);
                                    ms -= st;
                                }
                            }

                            var typ = obj.get_string_member("type");
                            have_data = (typ != "init");
                            switch(typ) {
                                case "init":
                                    if( !have_init) {
                                        have_init = true;
                                        var mrtype = obj.get_int_member ("mrtype");
                                        var mwvers = obj.get_int_member ("mwvers");
                                        var cap = obj.get_int_member ("capability");
                                        uint fctype = 42;
                                        string fcboard="UNKN";
                                        string fcname="";

                                        if(mwvers == 0)
                                            mwvers = 255;

                                        buf[0] = (uint8)mwvers;
                                        buf[1] = (uint8)mrtype;
                                        buf[2] = 42;
                                        SEDE.serialise_u32(&buf[3], (uint32)cap);
                                        send_rec(msp,MSP.Cmds.IDENT, 7, buf);

                                        if(obj.has_member("fctype"))
                                            fctype = (uint)obj.get_int_member ("fctype");
                                        if(obj.has_member("profile"))
                                            profile = (uint)obj.get_int_member ("profile");
                                        if(obj.has_member("fc_var")) {
                                            fcvar =  obj.get_string_member("fc_var");
                                            fcvers = (uint)obj.get_int_member ("fc_vers");
                                        } else if (fctype == 3) {
                                            fcvar = " CF ";
                                            fcvers = 0x010501;
                                        }

                                        if(obj.has_member("fcboard")) {
                                            fcboard = obj.get_string_member ("fcboard");
                                        }
                                        if (fcboard != null) {
                                            uint8 mlen = 6;
                                            buf[0] = fcboard[0];
                                            buf[1] = fcboard[1];
                                            buf[2] = fcboard[2];
                                            buf[3] = fcboard[3];
                                            buf[4] = buf[5] = 0;
                                            if(obj.has_member("fcname")) {
                                                fcname=obj.get_string_member ("fcname");
                                                if (fcname != null) {
                                                    buf[6] = buf[7] = 0;
                                                    buf[8] = (uint8)fcname.length;
                                                    for(var k = 0; k < buf[8]; k++)
                                                        buf[k+9] = fcname[k];
                                                    mlen = 9+buf[8];
                                                }
                                            }
                                            send_rec(msp,MSP.Cmds.BOARD_INFO, mlen, buf);
                                        }
                                        if(obj.has_member("vname")) {
                                            vname = obj.get_string_member ("vname");
                                            if(vname != null && vname.length > 0) {
                                                send_rec(msp,MSP.Cmds.NAME, vname.length,
                                                         vname.data);
                                            }
                                        }

                                        if(fcvar != null) {
                                            buf[0] = fcvar[0];
                                            buf[1] = fcvar[1];
                                            buf[2] = fcvar[2];
                                            buf[3] = fcvar[3];
                                            buf[4] = '!';
                                            send_rec(msp,MSP.Cmds.FC_VARIANT, 4, buf);

                                            buf[0] = (uint8)((fcvers & 0xff0000) >> 16);
                                            buf[1] = (uint8)((fcvers & 0xff00) >> 8);
                                            buf[2] = (uint8)(fcvers & 0xff);
                                            send_rec(msp,MSP.Cmds.FC_VERSION, 3, buf);
                                        }

                                        if(obj.has_member("git_info")) {
                                            var git = obj.get_string_member("git_info");
                                            for(var i = 0; i < 7; i++)
                                                buf[19+i] = git[i];
                                            buf[26] = 0;
                                            send_rec(msp,MSP.Cmds.BUILD_INFO, 32, buf);
                                        }

                                        string bx;
                                        if(obj.has_member("boxnames")) {
                                            bx = obj.get_string_member("boxnames");
                                        } else {
                                            if (fctype == 3) {
                                                if(fcvar == "INAV") {
                                                        // hackety hack time
                                                    if (utime < 1449360000)
                                                        bx = "ARM;ANGLE;HORIZON;MAG;HEADFREE;HEADADJ;NAV ALTHOLD;NAV POSHOLD;NAV RTH;NAV WP;BEEPER;OSD SW;BLACKBOX;FAILSAFE;";
                                                    else
                                                        bx = "ARM;ANGLE;HORIZON;AIR MODE;MAG;HEADFREE;HEADADJ;NAV ALTHOLD;NAV POSHOLD;NAV RTH;NAV WP;BEEPER;OSD SW;BLACKBOX;FAILSAFE;";
                                                } else {
                                                    bx= "ARM;ANGLE;HORIZON;BARO;MAG;HEADFREE;HEADADJ;GPS HOME;GPS HOLD;BEEPER;OSD SW;AUTOTUNE;";
                                                }
                                            } else {
                                                bx = "ARM;ANGLE;HORIZON;BARO;MAG;GPS HOME;GPS HOLD;BEEPER;MISSION;LAND;";
                                            }
                                        }

                                        send_rec(msp,MSP.Cmds.BOXNAMES, bx.length, bx.data);
                                        MSP_MISC a = MSP_MISC();
                                        a.conf_minthrottle=1064;
                                        a.maxthrottle=1864;
                                        a.mincommand=900;
                                        a.conf_mag_declination = 0;
                                        if (fctype == 3) {
                                            a.conf_vbatscale = 110;
                                            a.conf_vbatlevel_warn1 = 33;
                                            a.conf_vbatlevel_warn2 = 43;
                                        } else {
                                            a.conf_vbatscale = 131;
                                            a.conf_vbatlevel_warn1 = 107;
                                            a.conf_vbatlevel_warn2 = 99;
                                            a.conf_vbatlevel_crit = 93;
                                        }

                                        var nb = serialise_misc(a, buf);
                                        send_rec(msp,MSP.Cmds.MISC, (uint)nb, buf);
                                    }
                                    break;
                                case "armed":
                                    if(!telem) {
                                        var a = MSP_STATUS();
                                        armed = obj.get_boolean_member("armed");
                                        a.flag = (armed)  ? 1 : 0;
                                        if(obj.has_member("flags")) {
                                            var flag =  obj.get_int_member("flags");
                                            a.flag |= (uint32)flag;
                                        } else
                                            a.flag |= 4;

                                        if(obj.has_member("sensors")) {
                                            var s =  obj.get_int_member("sensors");
                                            a.sensor = (uint16)s;
                                        } else
                                            a.sensor=(MSP.Sensors.ACC|
                                                      MSP.Sensors.MAG|
                                                      MSP.Sensors.BARO|
                                                      MSP.Sensors.GPS);
                                        a.i2c_errors_count = 0;
                                        a.cycle_time=0;
                                        a.global_conf=(uint8)profile;
                                        xa = a;
                                        var nb = serialise_status(a, buf);
                                        send_rec(msp,MSP.Cmds.STATUS, (uint)nb, buf);
                                    }
                                    if(obj.has_member("telem")) {
                                        telem = obj.get_boolean_member("telem");
                                    }
                                    break;
                                case "analog":
                                    var volts = obj.get_double_member("voltage");
                                    var amps = obj.get_double_member("amps");
                                    var power = obj.get_int_member("power");
                                    var rssi = obj.get_int_member("rssi");
                                    MSP_ANALOG a = MSP_ANALOG();
                                    a.vbat = (uint8)(Math.lround(volts*10));
                                    a.amps = (uint16)amps;
                                    a.rssi = (uint16)rssi;
                                    a.powermetersum = (uint16)power;
                                    serialise_analogue(a, buf);
                                    send_rec(msp,MSP.Cmds.ANALOG, MSize.MSP_ANALOG, buf);
                                    break;
                                case "attitude":
                                        //{"type":"attitude","utime":1408382805,"angx":0,"angy":0,"heading"":0}
                                    var hdr =  obj.get_int_member("heading");
                                    if (hdr > 180)
                                        hdr -= 360;
                                    var dangx = obj.get_double_member("angx");
                                    var dangy = obj.get_double_member("angy");
                                    var a = MSP_ATTITUDE();
                                    a.heading=(int16)hdr;
                                    a.angx = (int16)Math.lround(dangx*10);
                                    a.angy = (int16)Math.lround(dangy*10);
                                    serialise_atti(a, buf);
                                    send_rec (msp,MSP.Cmds.ATTITUDE, MSize.MSP_ATTITUDE,buf);
                                    break;
                                case "altitude":
                                        //{"type":"altitude","utime":1404717912,"estalt":4.4199999999999999,"vario":20.399999999999999}
                                    var a = MSP_ALTITUDE();
                                    a.estalt = (int32)(Math.lround(obj.get_double_member("estalt")*100));
                                    a.vario = (int16)(Math.lround(obj.get_double_member("vario")* variodiv));
                                    var nb = serialise_alt(a, buf);
                                    send_rec(msp,MSP.Cmds.ALTITUDE, (uint)nb, buf);
                                    break;
                                case "status":
                                        //{"type":"status","utime":1404717912,"gps_mode":0,"nav_mode":0,"action":0,"wp_number":0,"nav_error":10,"target_bearing":0}
                                    var a = MSP_NAV_STATUS();
                                    a.gps_mode = (uint8)obj.get_int_member("gps_mode");
                                    a.nav_mode = (uint8)obj.get_int_member("nav_mode");
                                    a.action = (uint8)obj.get_int_member("action");
                                    a.wp_number = (uint8)obj.get_int_member("wp_number");
                                    a.nav_error = (uint8)obj.get_int_member("nav_error");
                                    a.target_bearing = (uint16)obj.get_int_member("target_bearing");
                                    serialise_nav_status(a, buf);
                                    send_rec(msp,MSP.Cmds.NAV_STATUS, MSize.MSP_NAV_STATUS,buf);
                                    break;
                                case "raw_gps":
                                        // {"type":"raw_gps","utime":1404717910,"lat":50.805089199999998,"lon":-1.4939248999999999,"cse":50.899999999999999,"spd":0.22,"alt":41,"fix":1,"numsat":8}
                                    var a = MSP_RAW_GPS();
                                    a.gps_lat = (int32)(Math.lround(obj.get_double_member("lat")*10000000));
                                    a.gps_lon = (int32)(Math.lround(obj.get_double_member("lon")*10000000));
                                    a.gps_altitude = (int16)obj.get_int_member("alt");
                                    a.gps_speed = (int16)(Math.lround(obj.get_double_member("spd")*100));
                                    a.gps_ground_course = (int16)(Math.lround(obj.get_double_member("cse")*10));
                                    a.gps_fix = (uint8)obj.get_int_member("fix");
                                    a.gps_numsat = (uint8)obj.get_int_member("numsat");
                                    if(obj.has_member("hdop"))
                                        a.gps_hdop = (uint16)obj.get_int_member("hdop");

                                    serialise_raw_gps(a, buf);
                                    send_rec(msp,MSP.Cmds.RAW_GPS, MSize.MSP_RAW_GPS,buf);
                                    break;
                                case "comp_gps":
                                        // {"type":"comp_gps","utime":1408391119,"bearing":180,"range":0,"update":0}

                                    var a = MSP_COMP_GPS();
                                    a.range = (uint16)obj.get_int_member("range");
                                    var hdr =  obj.get_int_member("bearing");
                                    if (hdr > 180)
                                        hdr -= 360;
                                    a.direction = (int16)hdr;
                                    a.update = (uint8)obj.get_int_member("update");
                                    serialise_comp_gps(a, buf);
                                    send_rec(msp,MSP.Cmds.COMP_GPS, MSize.MSP_COMP_GPS,buf);
                                    break;
                                case "radio":
                                        //"type":"radio","utime":1404717910,"rxerrors":0,"fixed_errors":0,"localrssi":139,"remrssi":138,"txbuf":100,"noise":93,"remnoise":15}
                                    var a = MSP_RADIO();
                                    a.localrssi = (uint8)(obj.get_int_member("localrssi"));
                                    a.remrssi = (uint8)(obj.get_int_member("remrssi"));
                                    a.noise = (uint8)(obj.get_int_member("noise"));
                                    a.remnoise = (uint8)(obj.get_int_member("remnoise"));
                                    a.txbuf = (uint8)(obj.get_int_member("txbuf"));

                                    a.rxerrors = (uint16)(obj.get_int_member("rxerrors"));
                                    a.fixed_errors = (uint16)(obj.get_int_member("fixed_errors"));
                                    serialise_radio(a, buf);
                                    send_rec(msp,MSP.Cmds.RADIO, MSize.MSP_RADIO,buf);
                                    break;
                                case "ltm_raw_sframe":
                                    telem = true;
                                    var s = LTM_SFRAME();
                                    s.vbat = (uint16)(obj.get_int_member("vbat"));
                                    s.vcurr = (uint16)(obj.get_int_member("vcurr"));
                                    s.rssi = (uint8)(obj.get_int_member("rssi"));
                                    s.airspeed = (uint8)(obj.get_int_member("airspeed"));
                                    s.flags = (uint8)(obj.get_int_member("flags"));
                                    armed = (s.flags & 1) == 1;
                                    serialise_sf(s,buf);
                                    send_rec(msp,MSP.Cmds.TS_FRAME, MSize.LTM_SFRAME,buf);
                                    break;

                                case "ltm_raw_oframe":
                                    telem = true;
                                    var o = LTM_OFRAME();
                                    o.lat = (int32)(obj.get_int_member("lat"));
                                    o.lon = (int32)(obj.get_int_member("lon"));
                                    o.fix = (uint8)(obj.get_int_member("fix"));
                                    serialise_of(o,buf);
                                    send_rec(msp,MSP.Cmds.TO_FRAME, MSize.LTM_OFRAME,buf);
                                    break;

                                case "ltm_xframe":
                                    var x = LTM_XFRAME();
                                    x = {0};
                                    x.hdop = (uint16)(obj.get_int_member("hdop"));
                                    if(obj.has_member("sensorok"))
                                        x.sensorok = (uint8)(obj.get_int_member("sensorok"));
                                    if(obj.has_member("count"))
                                        x.ltm_x_count = (uint8)(obj.get_int_member("count"));
                                    if(obj.has_member("reason"))
                                        x.disarm_reason = (uint8)(obj.get_int_member("reason"));
                                    serialise_xf(x,buf);
                                    send_rec(msp,MSP.Cmds.TX_FRAME, MSize.LTM_XFRAME,buf);
                                    break;

                                case "wp_poll":
                                        /*
                                    var w = MSP_WP();
                                    w.wp_no = (uint8)(obj.get_int_member("wp_no"));
                                    var lat = obj.get_double_member("wp_lat");
                                    var lon = obj.get_double_member("wp_lon");
                                    w.lat = (int32)(lat*10000000);
                                    w.lon = (int32)(lon*10000000);
                                    w.altitude = (uint32)(obj.get_int_member("wp_alt"));
                                    serialise_wp(w,buf);
                                    send_rec(msp,MSP.Cmds.INFO_WP, MSize.MSP_WP,buf);
                                        */
                                    break;

                                case "mavlink_heartbeat":
                                    telem = true;
                                    var m = Mav.MAVLINK_HEARTBEAT();
                                    m.custom_mode =  (uint32)obj.get_int_member("custom_mode");
                                    m.type =  (uint8)obj.get_int_member("mavtype");
                                    m.autopilot =  (uint8)obj.get_int_member("autopilot");
                                    m.base_mode =  (uint8)obj.get_int_member("base_mode");
                                    m.system_status =  (uint8)obj.get_int_member("system_status");
                                    m.mavlink_version =  (uint8)obj.get_int_member("mavlink_version");
                                    send_rec(msp,MSP.Cmds.MAVLINK_MSG_ID_HEARTBEAT, sizeof(Mav.MAVLINK_HEARTBEAT),(uint8*)(&m));
                                    break;
                                case "mavlink_sys_status":
                                    telem = true;
                                    var m = Mav.MAVLINK_SYS_STATUS();
                                    m.onboard_control_sensors_present =  (uint32)obj.get_int_member("onboard_control_sensors_present");
                                    m.onboard_control_sensors_enabled =  (uint32)obj.get_int_member("onboard_control_sensors_enabled");
                                    m.onboard_control_sensors_health =  (uint32)obj.get_int_member("onboard_control_sensors_health");
                                    m.load =  (uint16)obj.get_int_member("load");
                                    m.voltage_battery =  (uint16)obj.get_int_member("voltage_battery");
                                    m.current_battery =  (int16)obj.get_int_member("current_battery");
                                    m.drop_rate_comm =  (uint16)obj.get_int_member("drop_rate_comm");
                                    m.errors_comm =  (uint16)obj.get_int_member("errors_comm");
                                    m.errors_count1 =  (uint16)obj.get_int_member("errors_count1");
                                    m.errors_count2 =  (uint16)obj.get_int_member("errors_count2");
                                    m.errors_count3 =  (uint16)obj.get_int_member("errors_count3");
                                    m.errors_count4 =  (uint16)obj.get_int_member("errors_count4");
                                    m.battery_remaining =  (int8)obj.get_int_member("battery_remaining");
                                    send_rec(msp,MSP.Cmds.MAVLINK_MSG_ID_SYS_STATUS, sizeof(Mav.MAVLINK_SYS_STATUS),(uint8*)(&m));
                                    break;
                                case "mavlink_gps_raw_int":
                                    telem = true;
                                    var m = Mav.MAVLINK_GPS_RAW_INT();
                                    m.time_usec =  (uint64)obj.get_int_member("time_usec");
                                    m.lat =  (int32)obj.get_int_member("lat");
                                    m.lon =  (int32)obj.get_int_member("lon");
                                    m.alt =  (int32)obj.get_int_member("alt");
                                    m.eph =  (uint16)obj.get_int_member("eph");
                                    m.epv =  (uint16)obj.get_int_member("epv");
                                    m.vel =  (uint16)obj.get_int_member("vel");
                                    m.cog =  (uint16)obj.get_int_member("cog");
                                    m.fix_type =  (uint8)obj.get_int_member("fix_type");
                                    m.satellites_visible =  (uint8)obj.get_int_member("satellites_visible");
                                    send_rec(msp,MSP.Cmds.MAVLINK_MSG_GPS_RAW_INT, sizeof(Mav.MAVLINK_GPS_RAW_INT), (uint8*)(&m));
                                    break;
                                case "mavlink_attitude":
                                    telem = true;
                                    var m = Mav.MAVLINK_ATTITUDE();
                                    m.time_boot_ms =  (uint32)obj.get_int_member("time_boot_ms");
                                    m.roll =  (float)obj.get_double_member("roll");
                                    m.pitch =  (float)obj.get_double_member("pitch");
                                    m.yaw =  (float)obj.get_double_member("yaw");
                                    m.rollspeed =  (float)obj.get_double_member("rollspeed");
                                    m.pitchspeed =  (float)obj.get_double_member("pitchspeed");
                                    m.yawspeed =  (float)obj.get_double_member("yawspeed");
                                    send_rec(msp,MSP.Cmds.MAVLINK_MSG_ATTITUDE, sizeof(Mav.MAVLINK_ATTITUDE), (uint8*)(&m));
                                    break;
                                case "mavlink_rc_channels":
                                    telem = true;
                                    var m = Mav.MAVLINK_RC_CHANNELS();
                                    m.time_boot_ms =  (uint32)obj.get_int_member("time_boot_ms");
                                    m.chan1_raw =  (uint16)obj.get_int_member("chan1_raw");
                                    m.chan2_raw =  (uint16)obj.get_int_member("chan2_raw");
                                    m.chan3_raw =  (uint16)obj.get_int_member("chan3_raw");
                                    m.chan4_raw =  (uint16)obj.get_int_member("chan4_raw");
                                    m.chan5_raw =  (uint16)obj.get_int_member("chan5_raw");
                                    m.chan6_raw =  (uint16)obj.get_int_member("chan6_raw");
                                    m.chan7_raw =  (uint16)obj.get_int_member("chan7_raw");
                                    m.chan8_raw =  (uint16)obj.get_int_member("chan8_raw");
                                    m.port =  (uint8)obj.get_int_member("port");
                                    m.rssi =  (uint8)obj.get_int_member("rssi");
                                    send_rec(msp,MSP.Cmds.MAVLINK_MSG_RC_CHANNELS_RAW, sizeof(Mav.MAVLINK_RC_CHANNELS), (uint8*)(&m));
                                    break;
                                case "mavlink_gps_global_origin":
                                    telem = true;
                                    var m = Mav.MAVLINK_GPS_GLOBAL_ORIGIN();
                                    m.latitude =  (int32)obj.get_int_member("latitude");
                                    m.longitude =  (int32)obj.get_int_member("longitude");
                                    m.altitude =  (int32)obj.get_int_member("altitude");
                                    send_rec(msp,MSP.Cmds.MAVLINK_MSG_GPS_GLOBAL_ORIGIN, sizeof(Mav.MAVLINK_GPS_GLOBAL_ORIGIN), (uint8*)(&m));
                                    break;
                                case "mavlink_vfr_hud":
                                    telem = true;
                                    var m = Mav.MAVLINK_VFR_HUD();
                                    m.airspeed =  (float)obj.get_double_member("airspeed");
                                    m.groundspeed =  (float)obj.get_double_member("groundspeed");
                                    m.alt =  (float)obj.get_double_member("alt");
                                    m.climb =  (float)obj.get_double_member("climb");
                                    m.heading =  (int16)obj.get_int_member("heading");
                                    m.throttle =  (uint16)obj.get_int_member("throttle");
                                    send_rec(msp, MSP.Cmds.MAVLINK_MSG_VFR_HUD, sizeof(Mav.MAVLINK_VFR_HUD), (uint8*)(&m));
                                    break;
							case "text":
								var id = obj.get_string_member("id");
								var txt = obj.get_string_member("content");
								switch(id) {
								case "summary":
									send_rec(msp, MSP.Cmds.PRIV_TEXT_EOM, txt.length, txt.data);
									break;
								case "geozone":
									send_rec(msp, MSP.Cmds.PRIV_TEXT_GEOZ, txt.length, txt.data);
									break;
								default:
									break;
								}
								break;
								/*
							case "rawdata":
								var cmd =  (uint16)obj.get_int_member("mid");
								var txt = obj.get_string_member("msg");
								var rbuf = new uint8[txt.length/2];
								var j = 0;
								for(var i = 0; i < txt.length; i += 2) {
									uint8 c = parsehex(txt[i:i+2]);
									rbuf[j] = c;
									j++;
								}
								send_rec(msp, cmd, j, rbuf);
								break;
								*/
                                default:
                                    break;
                            }
                            lt = utime;
                            uint16 q =  (uint16)(utime-start_tm);
                            if (lq != q) {
                                send_tq_frame(msp, q);
                                lq = q;
                            }
                            while (paused)
                                Thread.usleep(5);
                        }
                    } catch (Error e) {
                        if(e.matches(Quark.from_string("g-io-error-quark"),19))
                            MWPLog.message("scenario cancelled\n");
                        else
                            MWPLog.message("line: %s  %s \n",line, e.message);
                        playon = false;
                    }
                }
                MWPLog.message("end of scenario\n");
                send_tq_frame(msp, (uint16)(utime-start_tm));
                xa.flag = 0;
                var nb = serialise_status(xa, buf);
                send_rec(msp, MSP.Cmds.STATUS, (uint)nb, buf);
                uint8 x=0;
                send_rec(msp, MSP.Cmds.Tx_FRAME, 1, &x);
                Thread.usleep(1000*1000);
                msp.close();
                return 0;
            });
        return thr;
    }
    void send_tq_frame(MWSerial msp, uint16 q) {
        send_rec(msp, MSP.Cmds.Tq_FRAME, 2, &q);
    }
}
