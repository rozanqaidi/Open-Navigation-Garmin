import Toybox.Lang;
import Toybox.Math;

// A loaded route plus everything precomputed for navigation:
// cumulative distances and the turns found from the line's angles.
class Route {
    // Turn types
    const STRAIGHT = 0;
    const LEFT = 1;
    const RIGHT = 2;
    const UTURN = 3;
    const FINISH = 4;

    const TURN_MIN_DEG = 35.0;      // smaller bends are just curves in the road
    const UTURN_MIN_DEG = 150.0;
    const LOOK_M = 15.0;            // look this far back/ahead to measure a bend
    const MERGE_M = 25.0;           // bends closer than this count as one turn
    const END_M = 40.0;             // a bend this close to the finish is not announced:
                                    // the finish flag (and "Arrived" at 25 m) takes over

    var name as String;
    var pts as Array<Float>;        // flat lat/lon radians
    var n as Number;
    var cum as Array<Float>;        // distance from start to each point (m)
    var total as Float;
    var turnAlong as Array<Float> = [] as Array<Float>;  // distance along route of each turn
    var turnType as Array<Number> = [] as Array<Number>;
    var turnIdx as Array<Number> = [] as Array<Number>;

    // Building is split into steps so the watch app can spread it over
    // several seconds (watchdog). lazy = false builds everything right away.
    hidden var _bi as Number = 1;          // next point for distances
    hidden var _ti as Number = 1;          // next point for turn search
    hidden var _lastTurnAlong as Float = -1000.0;
    var ready as Boolean = false;

    function initialize(routeName as String, points as Array<Float>, lazy as Boolean) {
        name = routeName;
        pts = points;
        n = points.size() / 2;
        cum = new Array<Float>[n];
        cum[0] = 0.0;
        total = 0.0;
        if (!lazy) {
            while (!build(1000000)) {
            }
        }
    }

    // Do up to `budget` points of work. Returns true when the route is ready.
    function build(budget as Number) as Boolean {
        var work = 0;
        while (_bi < n && work < budget) {
            cum[_bi] = cum[_bi - 1] + Geo.distance(pts[2 * _bi - 2], pts[2 * _bi - 1], pts[2 * _bi], pts[2 * _bi + 1]);
            _bi++;
            work++;
        }
        if (_bi < n) {
            return false;
        }
        total = cum[n - 1];
        while (_ti < n - 1 && work < budget) {
            turnAt(_ti);
            _ti++;
            work += 3;
        }
        ready = (_ti >= n - 1);
        if (ready) {
            while (turnAlong.size() > 0 && turnAlong[turnAlong.size() - 1] > total - END_M) {
                var last = turnAlong.size() - 1;
                turnAlong = turnAlong.slice(0, last);
                turnType = turnType.slice(0, last);
                turnIdx = turnIdx.slice(0, last);
            }
        }
        return ready;
    }

    function lat(i as Number) as Float {
        return pts[2 * i];
    }

    function lon(i as Number) as Float {
        return pts[2 * i + 1];
    }

    hidden function turnAt(i as Number) as Void {
        if (cum[i] - _lastTurnAlong >= MERGE_M) {
            var j = i - 1;
            while (j > 0 && cum[i] - cum[j] < LOOK_M) {
                j--;
            }
            var k = i + 1;
            while (k < n - 1 && cum[k] - cum[i] < LOOK_M) {
                k++;
            }
            var bin = Geo.bearing(lat(j), lon(j), lat(i), lon(i));
            var bout = Geo.bearing(lat(i), lon(i), lat(k), lon(k));
            var deg = Math.toDegrees(Geo.wrap(bout - bin));
            var mag = deg.abs();
            if (mag >= TURN_MIN_DEG) {
                turnIdx.add(i);
                turnAlong.add(cum[i]);
                turnType.add(mag >= UTURN_MIN_DEG ? UTURN : (deg > 0 ? RIGHT : LEFT));
                _lastTurnAlong = cum[i];
            }
        }
    }

    // Index of the first turn strictly ahead of `along`, or -1 for none.
    function nextTurn(along as Float, from as Number) as Number {
        for (var t = (from < 0 ? 0 : from); t < turnAlong.size(); t++) {
            if (turnAlong[t] > along + 1.0) {
                return t;
            }
        }
        return -1;
    }
}
