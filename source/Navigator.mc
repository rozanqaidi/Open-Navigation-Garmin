import Toybox.Lang;
import Toybox.Math;

// Follows the user along a Route: progress, next turn, off-route, arrival.
// Pure logic (no Toybox.Activity / Attention), so it can be unit tested.
// update() returns an event the view turns into a vibration / message.
class Navigator {
    const EV_NONE = 0;
    const EV_TURN = 1;          // ~20 m before a turn
    const EV_OFF_ROUTE = 2;
    const EV_BACK_ON_ROUTE = 3;
    const EV_ARRIVED = 4;

    const OFF_HOLD_MS = 10000;  // must stay off this long before it counts
    const BACK_HOLD_MS = 2000;
    const ARRIVE_M = 25.0;
    const TRAIL_STEP_M = 5.0;
    const TRAIL_MAX = 120;

    var route as Route;
    var mode as Number;

    // Live state for the view
    var seg as Number = 0;              // segment index we are on (seg → seg+1)
    var along as Float = 0.0;           // metres along the route
    var offDist as Float = 0.0;         // metres from the route line
    var isOff as Boolean = false;
    var rejoinLat as Float = 0.0;
    var rejoinLon as Float = 0.0;
    var rejoinDist as Float = 0.0;
    var nextTurn as Number = -1;        // index into route.turn* arrays, -1 = finish
    var distToNext as Float = 0.0;
    var remaining as Float = 0.0;
    var arrived as Boolean = false;
    var trail as Array<Float> = [] as Array<Float>;   // flat lat/lon while off route
    var backUntilMs as Number = 0;      // show "back on route" until this time

    hidden var _offSinceMs as Number? = null;
    hidden var _onSinceMs as Number? = null;
    hidden var _vibedTurn as Number = -1;
    hidden var _rejoinSeg as Number = 0;
    hidden var _located as Boolean = false;

    function initialize(r as Route, navMode as Number) {
        route = r;
        mode = navMode;
        remaining = r.total;
    }

    function offThresholdM() as Float {
        return (mode == Settings.MODE_MOTO) ? 50.0 : 40.0;
    }

    // Distance before a turn at which the single "turn now" vibration fires.
    function turnAlertM(speed as Float) as Float {
        if (mode == Settings.MODE_MOTO) {
            var d = speed * 3.0;
            return d < 30.0 ? 30.0 : d;
        }
        return 20.0;
    }

    // Distance at which the yellow bar starts filling.
    function barStartM() as Float {
        return (mode == Settings.MODE_MOTO) ? 600.0 : 300.0;
    }

    // 0 = empty, 1 = turn now.
    function barFraction() as Float {
        var start = barStartM();
        if (distToNext >= start) {
            return 0.0;
        }
        var f = 1.0 - distToNext / start;
        return (f < 0.0) ? 0.0 : (f > 1.0 ? 1.0 : f);
    }

    function update(lat as Float, lon as Float, speed as Float, nowMs as Number) as Number {
        var event = EV_NONE;
        if (arrived) {
            return event;
        }

        // 1. Where are we on the route?
        var best;
        if (!_located) {
            best = nearest(lat, lon, 0, route.n - 2);
            _located = true;
        } else {
            var lo = seg - 5;
            var hi = seg + 80;
            best = nearest(lat, lon, lo < 0 ? 0 : lo, hi > route.n - 2 ? route.n - 2 : hi);
        }
        var d = best[1] as Float;
        offDist = d;

        // 2. Off-route with hysteresis
        var thr = offThresholdM();
        if (d > thr) {
            _onSinceMs = null;
            if (_offSinceMs == null) {
                _offSinceMs = nowMs;
            }
            if (!isOff && nowMs - (_offSinceMs as Number) >= OFF_HOLD_MS) {
                isOff = true;
                trail = [] as Array<Float>;
                event = EV_OFF_ROUTE;
            }
        } else {
            _offSinceMs = null;
            if (isOff) {
                if (_onSinceMs == null) {
                    _onSinceMs = nowMs;
                }
                if (nowMs - (_onSinceMs as Number) >= BACK_HOLD_MS) {
                    isOff = false;
                    trail = [] as Array<Float>;
                    backUntilMs = nowMs + 3000;
                    event = EV_BACK_ON_ROUTE;
                }
            }
        }

        if (isOff || _offSinceMs != null) {
            addTrail(lat, lon);
        }

        if (isOff) {
            // Rejoin point: nearest point on the route AHEAD of our last progress.
            var ahead = nearest(lat, lon, seg, (seg + 300 > route.n - 2) ? route.n - 2 : seg + 300);
            if ((ahead[1] as Float) > 1500.0) {
                ahead = nearest(lat, lon, 0, route.n - 2);
            }
            _rejoinSeg = ahead[0] as Number;
            rejoinLat = ahead[2] as Float;
            rejoinLon = ahead[3] as Float;
            rejoinDist = ahead[1] as Float;
        } else {
            // Progress only moves forward while on the route.
            var newAlong = best[4] as Float;
            if (newAlong >= along - 30.0 || event == EV_BACK_ON_ROUTE) {
                seg = best[0] as Number;
                along = newAlong;
            }
        }

        // 3. Next turn and remaining distance
        remaining = route.total - along;
        nextTurn = route.nextTurn(along, nextTurn < 0 ? 0 : nextTurn);
        distToNext = (nextTurn >= 0) ? (route.turnAlong[nextTurn] - along) : remaining;

        if (!isOff && nextTurn >= 0 && nextTurn != _vibedTurn && distToNext <= turnAlertM(speed)) {
            _vibedTurn = nextTurn;
            if (event == EV_NONE) {
                event = EV_TURN;
            }
        }

        // 4. Arrival
        if (!isOff && remaining <= ARRIVE_M) {
            arrived = true;
            event = EV_ARRIVED;
        }
        return event;
    }

    // Nearest point on segments [from..to]: [segIndex, distM, lat, lon, alongM]
    function nearest(lat as Float, lon as Float, from as Number, to as Number) as Array {
        var cosLat = Math.cos(lat);
        var R = Geo.EARTH_RADIUS_M;
        var bestD = 1.0e12;
        var res = [0, 0.0, route.lat(0), route.lon(0), 0.0];
        for (var i = from; i <= to; i++) {
            var ax = (route.lon(i) - lon) * cosLat * R;
            var ay = (route.lat(i) - lat) * R;
            var bx = (route.lon(i + 1) - lon) * cosLat * R;
            var by = (route.lat(i + 1) - lat) * R;
            var dx = bx - ax;
            var dy = by - ay;
            var len2 = dx * dx + dy * dy;
            var t = 0.0;
            if (len2 > 0) {
                t = -(ax * dx + ay * dy) / len2;
                t = (t < 0) ? 0.0 : ((t > 1) ? 1.0 : t);
            }
            var px = ax + t * dx;
            var py = ay + t * dy;
            var d2 = px * px + py * py;
            if (d2 < bestD) {
                bestD = d2;
                var segLen = route.cum[i + 1] - route.cum[i];
                res = [i, Math.sqrt(d2).toFloat(),
                       (route.lat(i) + t * (route.lat(i + 1) - route.lat(i))).toFloat(),
                       (route.lon(i) + t * (route.lon(i + 1) - route.lon(i))).toFloat(),
                       (route.cum[i] + t * segLen).toFloat()];
            }
        }
        return res;
    }

    hidden function addTrail(lat as Float, lon as Float) as Void {
        var k = trail.size();
        if (k >= 2 && Geo.distance(trail[k - 2], trail[k - 1], lat, lon) < TRAIL_STEP_M) {
            return;
        }
        trail.add(lat);
        trail.add(lon);
        if (trail.size() > TRAIL_MAX * 2) {
            trail = trail.slice(2, trail.size());
        }
    }

    // Turn type for the header icon.
    function headerType() as Number {
        if (nextTurn < 0) {
            return route.FINISH;
        }
        if (distToNext >= barStartM()) {
            return route.STRAIGHT;
        }
        return route.turnType[nextTurn];
    }
}
