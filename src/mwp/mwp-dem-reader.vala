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
 * Ported from:     https://github.com/zbycz/srtm-hgt-reader.git
 * Original Author: (c) 2013 Pavel Zbytovský MIT Licence
 */

namespace Hgt {
	public const double NODATA=-32768.0;
}

public class HgtHandle {
	public int fd;
	public int blat;
	public int blon;
	private int width;
	private int arc;
	private string fname;

	public static string getbase(double lat, double lon, out int? _oblat, out int? _oblon) {
		var oblat = (int)Math.floor(lat);
		var oblon = (int)Math.floor(lon);
		var _blat = oblat.abs();
		var _blon = oblon.abs();
		char latc = (lat >= 0.0) ? 'N' : 'S';
		char lonc = (lon >= 0.0) ? 'E' : 'W';
		_oblat = oblat;
		_oblon = oblon;
		return "%c%02d%c%03d.hgt".printf(latc, _blat, lonc, _blon);
	}

	public HgtHandle (double lat, double lon) {
		fname = getbase(lat, lon, out blat, out blon);
		var _fname = Path.build_filename(DemManager.demdir, fname);
		fd = Posix.open(_fname, Posix.O_RDONLY);
		if (fd != -1) {
			Posix.Stat st;
			if(Posix.fstat(fd, out st) == 0) {
				var ssz = st.st_size /2;
				if (ssz/1201 == 1201) {
					width = 1201;
					arc = 3;
				} else if (ssz/3601 == 3601) {
					width = 3601;
					arc = 1;
				} else {
					Posix.close(fd);
					fd = -1;
				}
			}
		}
	}

	private int16 readpt(int y, int x) {
        int16 hgt = 0xffff;
        var row = width - 1 - y;
		var pos = (2 * (row*width + x));
		uint8 buf[2];
		Posix.lseek(fd, pos, Posix.SEEK_SET);
		var n = Posix.read(fd, buf, 2);
		if (n == 2) {
			hgt = (buf[0]<<8) | buf[1];
        }
        return hgt;
	}

	public double get_elevation(double lat, double lon) {
        var dslat = 3600.0 * (lat - blat);
        var dslon = 3600.0 * (lon - blon);

        var y = (int)dslat / arc;
		var x = (int)dslon / arc;

        int16 elevs[4];
        elevs[0] = readpt(y+1, x);
        elevs[1] = readpt(y+1, x+1);
        elevs[2] = readpt(y, x);
        elevs[3] = readpt(y, x+1);

        var dy = Math.fmod(dslat, arc) / arc;
		var dx = Math.fmod(dslon, arc) / arc;

    // Bilinear interpolation
    // h0------------h1
    // |
    // |--dx-- .
    // |       |
    // |      dy
    // |       |
    // h2------------h3

		var e = elevs[0]*dy*(1-dx) +
			elevs[1]*dy*(dx) +
			elevs[2]*(1-dy)*(1-dx) +
			elevs[3]*(1-dy)*dx;
        return e;
	}
}

public class DEMMgr {
	private const size_t HGT_SIZE_30M = 25934402; // 3601*3601
	private const size_t HGT_SIZE_90M =  2884802; // 1201*1201
	private HgtHandle [] hgts;
	public DEMMgr() {
		hgts = {};
		string? name = null;
		try {
			Dir dir = Dir.open (DemManager.demdir, 0);
			while ((name = dir.read_name ()) != null) {
				string path = Path.build_filename (DemManager.demdir, name);
				if (FileUtils.test (path, FileTest.IS_REGULAR)) {
					Posix.Stat st;
					if (Posix.stat(path, out st) == 0) {
						if(st.st_size != HGT_SIZE_30M && st.st_size != HGT_SIZE_90M) {
							Posix.unlink(path);
						}
					}
				}
			}
		} catch (Error e) {
			MWPLog.message("Failed to read %s %s\n", DemManager.demdir, e.message);
		}
	}

	~DEMMgr() {
		foreach (var hh in hgts) {
			if (hh.fd != -1) {
				Posix.close(hh.fd);
			}
		}
	}

	public HgtHandle? findHgt(double lat, double lon) {
		int blat;
		int blon;
        HgtHandle.getbase(lat, lon, out blat, out blon);
		foreach (var hh in hgts) {
			if (hh.blat == blat && hh.blon == blon) {
				return hh;
			}
        }
        return null;
	}

	public double lookup(double lat, double lon) {
		if(Gis.map.viewport.zoom_level < Mwp.conf.min_dem_zoom) {
			return Hgt.NODATA;
		}
		var  hh = findHgt(lat, lon);
        if (hh == null) {
			hh  = new HgtHandle(lat, lon);
			if (hh.fd != -1) {
				hgts +=  hh;
			} else {
				hh = null;
				var fn = HgtHandle.getbase(lat, lon, null, null);
				DemManager.asyncdl.add_queue(fn);
				return Hgt.NODATA;
			}
		}
		return hh.get_elevation(lat, lon);
	}
}
