import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;

// Small geodesy helpers. All angles are radians.
// Bearings: 0 = north, increasing clockwise, range (-PI, PI].
module Geo {
    const EARTH_RADIUS_M = 6371000.0;

    // Great-circle distance in metres (haversine).
    function distance(lat1 as Numeric, lon1 as Numeric, lat2 as Numeric, lon2 as Numeric) as Float {
        var sLat = Math.sin((lat2 - lat1) / 2.0);
        var sLon = Math.sin((lon2 - lon1) / 2.0);
        var a = sLat * sLat + Math.cos(lat1) * Math.cos(lat2) * sLon * sLon;
        if (a > 1.0) {
            a = 1.0;
        }
        return (2.0 * EARTH_RADIUS_M * Math.atan2(Math.sqrt(a), Math.sqrt(1.0 - a))).toFloat();
    }

    // Initial bearing from point 1 to point 2.
    function bearing(lat1 as Numeric, lon1 as Numeric, lat2 as Numeric, lon2 as Numeric) as Float {
        var dLon = lon2 - lon1;
        var y = Math.sin(dLon) * Math.cos(lat2);
        var x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
        return Math.atan2(y, x).toFloat();
    }

    // Wrap an angle into (-PI, PI].
    function wrap(a as Numeric) as Float {
        var pi = Math.PI;
        var r = a.toFloat();
        while (r > pi) {
            r -= 2 * pi;
        }
        while (r <= -pi) {
            r += 2 * pi;
        }
        return r.toFloat();
    }

    // "850 m", "1.2 km", "12 km"
    function formatDistance(m as Numeric) as String {
        if (m < 1000) {
            var rounded = (m < 100) ? m.toNumber() : ((m / 10).toNumber() * 10);
            return rounded.format("%d") + " m";
        }
        if (m < 10000) {
            return (m / 1000.0).format("%.1f") + " km";
        }
        return (m / 1000.0).format("%d") + " km";
    }

    // ---- unit tests (only compiled with `scripts/build.sh --test`) ----

    (:test)
    function testDistanceMonasToGbk(logger as Logger) as Boolean {
        // Monas -> GBK, straight line ~5.5 km
        var d = distance(Math.toRadians(-6.1754), Math.toRadians(106.8272),
                         Math.toRadians(-6.2185), Math.toRadians(106.8019));
        logger.debug("distance=" + d);
        return d > 5400 && d < 5700;
    }

    (:test)
    function testBearingCardinal(logger as Logger) as Boolean {
        var lat = Math.toRadians(-6.2);
        var lon = Math.toRadians(106.8);
        var north = bearing(lat, lon, lat + 0.001, lon);
        var east = bearing(lat, lon, lat, lon + 0.001);
        var south = bearing(lat, lon, lat - 0.001, lon);
        logger.debug("n=" + north + " e=" + east + " s=" + south);
        return north.abs() < 0.01
            && (east - Math.PI / 2).abs() < 0.01
            && (south.abs() - Math.PI).abs() < 0.01;
    }

    (:test)
    function testWrap(logger as Logger) as Boolean {
        return (wrap(3 * Math.PI / 2) + Math.PI / 2).abs() < 0.001
            && (wrap(-3 * Math.PI / 2) - Math.PI / 2).abs() < 0.001;
    }

    (:test)
    function testFormatDistance(logger as Logger) as Boolean {
        return formatDistance(42).equals("42 m")
            && formatDistance(857).equals("850 m")
            && formatDistance(1234).equals("1.2 km")
            && formatDistance(15400).equals("15 km");
    }
}
