import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;

// Encoded-polyline decoding (Google / Valhalla format) and route simplification.
// Routes are kept as a flat Array<Float>: [lat0, lon0, lat1, lon1, ...] in radians.
module Polyline {
    // Decode an encoded polyline. precision = 6 for Valhalla, 5 for OSRM/Google.
    function decode(encoded as String, precision as Number) as Array<Float> {
        var chars = encoded.toCharArray();
        var factor = Math.pow(10, precision).toDouble();
        var out = [] as Array<Float>;
        var i = 0;
        var lat = 0;
        var lon = 0;
        var n = chars.size();
        while (i < n) {
            var result = 0;
            var shift = 0;
            var b = 0;
            do {
                b = chars[i].toNumber() - 63;
                i++;
                result |= (b & 0x1f) << shift;
                shift += 5;
            } while (b >= 0x20 && i < n);
            lat += ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);

            result = 0;
            shift = 0;
            do {
                b = chars[i].toNumber() - 63;
                i++;
                result |= (b & 0x1f) << shift;
                shift += 5;
            } while (b >= 0x20 && i < n);
            lon += ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);

            out.add(Math.toRadians(lat / factor).toFloat());
            out.add(Math.toRadians(lon / factor).toFloat());
        }
        return out;
    }

    // Number of points in a flat route array.
    function count(pts as Array<Float>) as Number {
        return pts.size() / 2;
    }

    // Douglas-Peucker simplification that keeps at most maxPoints points.
    // Starts at toleranceM metres and doubles it until the route fits.
    function simplify(pts as Array<Float>, toleranceM as Float, maxPoints as Number) as Array<Float> {
        var n = count(pts);
        if (n <= 2) {
            return pts;
        }
        // Synchronous version (tests, small inputs). The watch app uses
        // Simplifier step by step instead, to stay under the watchdog.
        var tol = toleranceM;
        var result = thin(pts, tol);
        while (true) {
            var s = new Simplifier(result, tol);
            while (!s.step(1000000)) {
            }
            result = s.result();
            if (count(result) <= maxPoints || tol >= 5000) {
                break;
            }
            tol *= 2;
            result = thin(result, tol);
        }
        return result;
    }

    // One fast pass: drop points closer than minM to the previous kept point.
    // Keeps the work for Douglas-Peucker small on dense server geometry.
    function thin(pts as Array<Float>, minM as Float) as Array<Float> {
        var n = count(pts);
        if (n <= 2) {
            return pts;
        }
        var cosLat = Math.cos(pts[0]);
        var R = Geo.EARTH_RADIUS_M;
        var out = [pts[0], pts[1]] as Array<Float>;
        var lastLat = pts[0];
        var lastLon = pts[1];
        var min2 = minM * minM;
        for (var k = 1; k < n - 1; k++) {
            var dy = (pts[2 * k] - lastLat) * R;
            var dx = (pts[2 * k + 1] - lastLon) * cosLat * R;
            if (dx * dx + dy * dy >= min2) {
                out.add(pts[2 * k]);
                out.add(pts[2 * k + 1]);
                lastLat = pts[2 * k];
                lastLon = pts[2 * k + 1];
            }
        }
        out.add(pts[2 * n - 2]);
        out.add(pts[2 * n - 1]);
        return out;
    }

    // Total route length in metres.
    function lengthM(pts as Array<Float>) as Float {
        var total = 0.0;
        for (var k = 2; k < pts.size(); k += 2) {
            total += Geo.distance(pts[k - 2], pts[k - 1], pts[k], pts[k + 1]);
        }
        return total.toFloat();
    }
}
