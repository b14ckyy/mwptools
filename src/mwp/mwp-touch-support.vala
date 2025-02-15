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

namespace Touch {
	internal int8 is_touch = -1;
	internal Gdk.Display dpy = null;
	public bool has_touch_screen() {
		if (is_touch == -1) {
			dpy = Gdk.Display.get_default();
			var seat = dpy.get_default_seat();
			var cap = seat.get_capabilities();
			is_touch = (int8)(cap & Gdk.SeatCapabilities.TOUCH);
		}
		return (bool)is_touch;
	}

	public double get_scale() {
		if (dpy == null) {
			dpy = Gdk.Display.get_default();
		}
		var surf = Mwp.window.get_surface();
		var mon = dpy.get_monitor_at_surface(surf);
		if (mon != null) {
			return mon.get_scale();
		}
		return 1.0;
	}
}
