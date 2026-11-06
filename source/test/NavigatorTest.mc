import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;

// Scenario tests for Route (turn detection) and Navigator (guidance).
(:test)
module NavigatorTest {
    const LAT0 = -0.10778;
    const LON0 = 1.86450;
    const M = 1.0 / 6371000.0;

    function p(northM as Numeric, eastM as Numeric) as [Float, Float] {
        return [(LAT0 + northM * M).toFloat(), (LON0 + eastM * M / Math.cos(LAT0)).toFloat()];
    }

    // Route: 300 m north, then right 200 m east, then left 300 m north.
    function sampleRoute() as Route {
        var pts = [] as Array<Float>;
        var corners = [[0, 0], [300, 0], [300, 200], [600, 200]];
        for (var c = 0; c < corners.size(); c++) {
            var q = p(corners[c][0], corners[c][1]);
            pts.add(q[0]);
            pts.add(q[1]);
        }
        return new Route("test", pts, false);
    }

    (:test)
    function detectsRightThenLeft(logger as Logger) as Boolean {
        var r = sampleRoute();
        logger.debug("turns=" + r.turnType + " along=" + r.turnAlong + " total=" + r.total);
        return r.turnType.size() == 2
            && r.turnType[0] == r.RIGHT && r.turnType[1] == r.LEFT
            && (r.turnAlong[0] - 300).abs() < 1 && (r.turnAlong[1] - 500).abs() < 1
            && (r.total - 800).abs() < 2;
    }

    (:test)
    function detectsUturn(logger as Logger) as Boolean {
        var pts = [] as Array<Float>;
        var a = p(0, 0); var b = p(200, 0); var c = p(0, 5);
        pts.addAll([a[0], a[1], b[0], b[1], c[0], c[1]]);
        var r = new Route("u", pts, false);
        return r.turnType.size() == 1 && r.turnType[0] == r.UTURN;
    }

    (:test)
    function gentleCurveIsNotATurn(logger as Logger) as Boolean {
        var pts = [] as Array<Float>;
        for (var i = 0; i <= 20; i++) {
            // 20 deg total bend spread over 400 m
            var ang = Math.toRadians(i);
            var q = p(i * 20 * Math.cos(ang), i * 20 * Math.sin(ang));
            pts.add(q[0]);
            pts.add(q[1]);
        }
        var r = new Route("curve", pts, false);
        logger.debug("turns=" + r.turnType.size());
        return r.turnType.size() == 0;
    }

    // Run the whole route at 3 m/s: exactly one turn event per turn, then arrival.
    (:test)
    function runFollowsRoute(logger as Logger) as Boolean {
        var nav = new Navigator(sampleRoute(), Settings.MODE_RUN);
        var path = [] as Array;
        for (var m = 0; m <= 300; m += 3) { path.add(p(m, 0)); }
        for (var m = 3; m <= 200; m += 3) { path.add(p(300, m)); }
        for (var m = 3; m <= 300; m += 3) { path.add(p(300 + m, 200)); }
        var turnEvents = 0;
        var arrived = false;
        var offEvents = 0;
        for (var i = 0; i < path.size(); i++) {
            var ev = nav.update(path[i][0], path[i][1], 3.0, i * 1000);
            if (ev == nav.EV_TURN) { turnEvents++; }
            if (ev == nav.EV_OFF_ROUTE) { offEvents++; }
            if (ev == nav.EV_ARRIVED) { arrived = true; }
        }
        logger.debug("turnEvents=" + turnEvents + " off=" + offEvents + " arrived=" + arrived);
        return turnEvents == 2 && offEvents == 0 && arrived;
    }

    // Turn alert fires at ~20 m, not earlier.
    (:test)
    function turnAlertAt20m(logger as Logger) as Boolean {
        var nav = new Navigator(sampleRoute(), Settings.MODE_RUN);
        nav.update(p(250, 0)[0], p(250, 0)[1], 3.0, 0);
        var at50 = nav.update(p(250, 0)[0], p(250, 0)[1], 3.0, 1000);
        var at25 = nav.update(p(275, 0)[0], p(275, 0)[1], 3.0, 2000);
        var at18 = nav.update(p(282, 0)[0], p(282, 0)[1], 3.0, 3000);
        logger.debug("dist=" + nav.distToNext + " bar=" + nav.barFraction());
        return at50 == nav.EV_NONE && at25 == nav.EV_NONE && at18 == nav.EV_TURN
            && nav.barFraction() > 0.9 && nav.headerType() == nav.route.RIGHT;
    }

    // Wide road: running 30 m beside the line never counts as off-route.
    (:test)
    function wideRoadIsNotOffRoute(logger as Logger) as Boolean {
        var nav = new Navigator(sampleRoute(), Settings.MODE_RUN);
        var off = false;
        for (var i = 0; i < 60; i++) {
            var q = p(i * 4, 30);
            if (nav.update(q[0], q[1], 3.0, i * 1000) == nav.EV_OFF_ROUTE) { off = true; }
        }
        return !off && !nav.isOff;
    }

    // Detour into a side street: off after 10 s, rejoin point is ahead, back on route later.
    (:test)
    function detourAndRejoin(logger as Logger) as Boolean {
        var nav = new Navigator(sampleRoute(), Settings.MODE_RUN);
        var t = 0;
        for (var m = 0; m <= 100; m += 3) { var q = p(m, 0); nav.update(q[0], q[1], 3.0, t); t += 1000; }
        // Step 80 m to the west and stay there
        var offAt = -1;
        for (var s = 0; s < 15; s++) {
            var q = p(100 + s, -80);
            if (nav.update(q[0], q[1], 3.0, t) == nav.EV_OFF_ROUTE) { offAt = s; }
            t += 1000;
        }
        var rejoinAhead = nav.isOff && Math.toDegrees(nav.rejoinLat) >= Math.toDegrees(p(99, 0)[0]);
        // Walk back onto the route further north
        var backEvent = false;
        for (var s = 0; s < 5; s++) {
            var q = p(140, 0);
            if (nav.update(q[0], q[1], 3.0, t) == nav.EV_BACK_ON_ROUTE) { backEvent = true; }
            t += 1000;
        }
        logger.debug("offAt=" + offAt + " rejoinDist=" + nav.rejoinDist + " back=" + backEvent + " along=" + nav.along);
        return offAt >= 9 && offAt <= 11 && rejoinAhead && backEvent && !nav.isOff && (nav.along - 140).abs() < 5;
    }

    // Motorbike: wider threshold and earlier, speed-based alert.
    (:test)
    function motoThresholds(logger as Logger) as Boolean {
        var nav = new Navigator(sampleRoute(), Settings.MODE_MOTO);
        return nav.offThresholdM() == 50.0 && nav.turnAlertM(15.0) == 45.0 && nav.barStartM() == 600.0;
    }

    // Code produced by the planner web page (docs/planner) for Monas → Bundaran HI → GBK.
    (:test)
    function plannerCodeRoundTrip(logger as Logger) as Boolean {
        var pts = RouteCode.points("NAVG1L:fcud@_u_kSnyBfYzqCzbC") as Array<Float>;
        var ok = Polyline.count(pts) == 3;
        var expect = [[-6.1754, 106.8272], [-6.1950, 106.8230], [-6.2185, 106.8019]];
        for (var i = 0; i < 3 && ok; i++) {
            ok = (Math.toDegrees(pts[2 * i]) - expect[i][0]).abs() < 0.00002
              && (Math.toDegrees(pts[2 * i + 1]) - expect[i][1]).abs() < 0.00002;
        }
        return ok;
    }

    (:test)
    function routeCodes(logger as Logger) as Boolean {
        var line = RouteCode.kind("NAVG1L:_p~iF~ps|U_ulLnnqC");
        var via = RouteCode.kind(" NAVG1V:_p~iF~ps|U_ulLnnqC ");
        var none = RouteCode.kind("-6.2, 106.8");
        var pts = RouteCode.points("NAVG1L:_p~iF~ps|U_ulLnnqC_mqNvxq`@");
        return line == RouteCode.KIND_LINE && via == RouteCode.KIND_VIA && none == RouteCode.KIND_NONE
            && pts != null && Polyline.count(pts) == 3;
    }

    // A bend just before the finish is not announced: the finish flag takes over.
    (:test)
    function bendAtFinishIsDropped(logger as Logger) as Boolean {
        var pts = [] as Array<Float>;
        var c = [[0, 0], [300, 0], [300, 22]];
        for (var k = 0; k < c.size(); k++) {
            var q = p(c[k][0], c[k][1]);
            pts.add(q[0]);
            pts.add(q[1]);
        }
        var r = new Route("end", pts, false);
        var nav = new Navigator(r, Settings.MODE_RUN);
        nav.update(p(100, 0)[0], p(100, 0)[1], 3.0, 0);
        logger.debug("turns=" + r.turnType.size() + " header=" + nav.headerType());
        return r.turnType.size() == 0 && nav.headerType() == r.FINISH;
    }

    // The green trail starts on the route where we left it, not 40 m away.
    (:test)
    function trailStartsOnRoute(logger as Logger) as Boolean {
        var nav = new Navigator(sampleRoute(), Settings.MODE_RUN);
        var t = 0;
        for (var m = 0; m <= 150; m += 3) {
            nav.update(p(m, 0)[0], p(m, 0)[1], 3.0, t);
            t += 1000;
        }
        // walk away east, 4 m per second, until the off-route alarm
        for (var e = 4; e <= 120; e += 4) {
            nav.update(p(150, e)[0], p(150, e)[1], 3.0, t);
            t += 1000;
        }
        var tr = nav.trail;
        var d0 = Geo.distance(tr[0], tr[1], p(150, 0)[0], p(150, 0)[1]);
        logger.debug("off=" + nav.isOff + " pts=" + tr.size() / 2 + " firstFromRoute=" + d0);
        // second dot must be close to the route too (no 40 m gap)
        var d1 = Geo.distance(tr[2], tr[3], p(150, 0)[0], p(150, 0)[1]);
        logger.debug("secondFromRoute=" + d1);
        return nav.isOff && d0 < 5.0 && d1 < 16.0 && tr.size() >= 10;
    }
}
