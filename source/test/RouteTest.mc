import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Test;

(:test)
module RouteTest {
    function nearDeg(rad as Float, deg as Float, tol as Float) as Boolean {
        return (Math.toDegrees(rad) - deg).abs() <= tol;
    }

    // Google's reference example (precision 5).
    (:test)
    function decodeGoogleExample(logger as Logger) as Boolean {
        var p = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@", 5);
        logger.debug("points=" + Polyline.count(p));
        return Polyline.count(p) == 3
            && nearDeg(p[0], 38.5, 0.0001) && nearDeg(p[1], -120.2, 0.0001)
            && nearDeg(p[2], 40.7, 0.0001) && nearDeg(p[3], -120.95, 0.0001)
            && nearDeg(p[4], 43.252, 0.0001) && nearDeg(p[5], -126.453, 0.0001);
    }

    // Same string read as precision 6 is ten times smaller (Valhalla format check).
    (:test)
    function decodePrecision6(logger as Logger) as Boolean {
        var p = Polyline.decode("_p~iF~ps|U", 6);
        return nearDeg(p[0], 3.85, 0.00001) && nearDeg(p[1], -12.02, 0.00001);
    }

    // A straight line with 101 points collapses to its two ends.
    (:test)
    function simplifyStraightLine(logger as Logger) as Boolean {
        var pts = [] as Array<Float>;
        for (var i = 0; i <= 100; i++) {
            pts.add(Math.toRadians(-6.2 + i * 0.0001).toFloat());
            pts.add(Math.toRadians(106.8).toFloat());
        }
        var s = Polyline.simplify(pts, 5.0, 400);
        logger.debug("kept=" + Polyline.count(s));
        return Polyline.count(s) == 2;
    }

    // An L-shaped route keeps its corner.
    (:test)
    function simplifyKeepsCorner(logger as Logger) as Boolean {
        var pts = [] as Array<Float>;
        for (var i = 0; i <= 50; i++) {
            pts.add(Math.toRadians(-6.2 + i * 0.0001).toFloat());
            pts.add(Math.toRadians(106.8).toFloat());
        }
        for (var i = 1; i <= 50; i++) {
            pts.add(Math.toRadians(-6.195).toFloat());
            pts.add(Math.toRadians(106.8 + i * 0.0001).toFloat());
        }
        var s = Polyline.simplify(pts, 5.0, 400);
        logger.debug("kept=" + Polyline.count(s));
        return Polyline.count(s) == 3;
    }

    // Realistic city route: 9 km, a point every 3 m, a corner every 200 m,
    // with 1 m GPS-like wobble. Must stay under the cap and be fast.
    (:test)
    function simplifyCityRouteFast(logger as Logger) as Boolean {
        var pts = [] as Array<Float>;
        var lat = -6.2;
        var lon = 106.8;
        var dir = 0;
        var step = 3.0 / 111320.0;
        for (var i = 0; i < 3000; i++) {
            if (i % 67 == 66) {
                dir = (dir + ((i / 67) % 2 == 0 ? 1 : 3)) % 4;
            }
            var wob = ((i * 7919) % 11 - 5) * 0.2 / 111320.0;
            lat += (dir == 0 ? step : (dir == 2 ? -step : 0)) + (dir % 2 == 1 ? wob : 0);
            lon += (dir == 1 ? step : (dir == 3 ? -step : 0)) + (dir % 2 == 0 ? wob : 0);
            pts.add(Math.toRadians(lat).toFloat());
            pts.add(Math.toRadians(lon).toFloat());
        }
        var t0 = System.getTimer();
        var s = Polyline.simplify(pts, 5.0, 1000);
        var ms = System.getTimer() - t0;
        var r = new Route("city", s, false);
        logger.debug("in=3000 kept=" + Polyline.count(s) + " turns=" + r.turnType.size() + " ms=" + ms);
        return Polyline.count(s) <= 1000 && r.turnType.size() >= 40 && ms < 8000;
    }

    (:test)
    function lengthOfKnownRoute(logger as Logger) as Boolean {
        // 0.009 deg of latitude ~ 1000 m
        var pts = [Math.toRadians(-6.2).toFloat(), Math.toRadians(106.8).toFloat(),
                   Math.toRadians(-6.191).toFloat(), Math.toRadians(106.8).toFloat()] as Array<Float>;
        var len = Polyline.lengthM(pts);
        logger.debug("len=" + len);
        return (len - 1000.8).abs() < 5;
    }

    (:test)
    function destinationPlain(logger as Logger) as Boolean {
        var d = Destination.parse("-6.2185, 106.8019");
        return d != null && (d[0] + 6.2185).abs() < 0.0001 && (d[1] - 106.8019).abs() < 0.0001;
    }

    (:test)
    function destinationNoSpace(logger as Logger) as Boolean {
        var d = Destination.parse("-6.2185,106.8019");
        return d != null && (d[1] - 106.8019).abs() < 0.0001;
    }

    (:test)
    function destinationMapsAtLink(logger as Logger) as Boolean {
        var d = Destination.parse("https://www.google.com/maps/place/GBK/@-6.2185,106.8019,17z/data=x");
        return d != null && (d[0] + 6.2185).abs() < 0.0001 && (d[1] - 106.8019).abs() < 0.0001;
    }

    (:test)
    function destinationMapsQueryLink(logger as Logger) as Boolean {
        var d = Destination.parse("https://maps.google.com/?q=-8.6705,115.2126");
        return d != null && (d[0] + 8.6705).abs() < 0.0001 && (d[1] - 115.2126).abs() < 0.0001;
    }

    (:test)
    function destinationRejectsJunk(logger as Logger) as Boolean {
        return Destination.parse("hotel dekat pantai") == null
            && Destination.parse("") == null
            && Destination.parse("200, 500") == null
            && Destination.parse(null) == null;
    }
}
