import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Test;

// Draw every Open NavG screen into an off-screen 416x416 bitmap.
// Checks: no crash, and each frame is fast enough for the watchdog.
(:test)
module ScreenTest {
    const LAT0 = -0.10778;
    const LON0 = 1.86450;
    const M = 1.0 / 6371000.0;

    function p(n as Numeric, e as Numeric) as [Float, Float] {
        return [(LAT0 + n * M).toFloat(), (LON0 + e * M / Math.cos(LAT0)).toFloat()];
    }

    function route() as Route {
        var pts = [] as Array<Float>;
        var c = [[0, 0], [300, 0], [300, 200], [600, 200], [600, -100], [900, -100]];
        for (var i = 0; i < c.size(); i++) {
            var q = p(c[i][0], c[i][1]);
            pts.add(q[0]);
            pts.add(q[1]);
        }
        return new Route("Loop pantai 10K", pts, false);
    }

    function dc() as Graphics.Dc {
        return Graphics.createBufferedBitmap({:width => 416, :height => 416}).get().getDc();
    }

    function timed(logger as Logger, label as String, v as OpenNavGView, d as Graphics.Dc) as Number {
        var t0 = System.getTimer();
        v.onUpdate(d);
        var ms = System.getTimer() - t0;
        logger.debug(label + " ms=" + ms);
        return ms;
    }

    function move(v as OpenNavGView, nav as Navigator, n as Numeric, e as Numeric, t as Number) as Void {
        var q = p(n, e);
        v.state.update(q[0], q[1], 3.0, null, LAT0, LON0);
        nav.update(q[0], q[1], 3.0, t);
    }

    (:test)
    function staticScreensRender(logger as Logger) as Boolean {
        var d = dc();
        var v = new OpenNavGView();
        var worst = timed(logger, "idle-nogps", v, d);
        v.state.update(LAT0, LON0, 0, null, null, null);
        v.state.update(p(200, 50)[0], p(200, 50)[1], 3.0, null, null, null);
        worst = max(worst, timed(logger, "start-arrow", v, d));
        v.testPhase(v.PH_LOADING, false);
        worst = max(worst, timed(logger, "loading", v, d));
        v.testPhase(v.PH_ERROR, false);
        worst = max(worst, timed(logger, "error", v, d));
        v.testLoad(route(), false);
        worst = max(worst, timed(logger, "ready", v, d));
        v.testPhase(v.PH_ROUTE, true);
        worst = max(worst, timed(logger, "picker", v, d));
        return worst < 1000;
    }

    (:test)
    function navScreensRender(logger as Logger) as Boolean {
        var d = dc();
        var v = new OpenNavGView();
        var nav = v.testLoad(route(), true);
        move(v, nav, 0, 0, 0);
        move(v, nav, 10, 0, 1000);
        var worst = timed(logger, "nav-straight", v, d);
        move(v, nav, 150, 0, 2000);
        worst = max(worst, timed(logger, "nav-approach", v, d));
        move(v, nav, 285, 0, 3000);
        worst = max(worst, timed(logger, "nav-turn-now", v, d));
        return worst < 1000;
    }

    (:test)
    function offRouteScreensRender(logger as Logger) as Boolean {
        var d = dc();
        var v = new OpenNavGView();
        var nav = v.testLoad(route(), true);
        walk(v, nav, 0, 0, 290, 0, 30, 0);
        for (var s = 0; s < 14; s++) {
            move(v, nav, 290 + s * 2, -60 - s * 3, 40000 + s * 1000);
        }
        var worst = timed(logger, "off-route", v, d);
        var wasOff = nav.isOff;
        for (var s = 0; s < 4; s++) {
            move(v, nav, 300, 60, 60000 + s * 1000);
        }
        worst = max(worst, timed(logger, "back-on-route", v, d));
        logger.debug("off=" + wasOff + " back=" + !nav.isOff);
        return wasOff && !nav.isOff && worst < 1000;
    }

    (:test)
    function arrivedScreenRenders(logger as Logger) as Boolean {
        var d = dc();
        var v = new OpenNavGView();
        var nav = v.testLoad(route(), true);
        var t = walk(v, nav, 0, 0, 300, 0, 30, 0);
        t = walk(v, nav, 300, 0, 300, 200, 20, t);
        t = walk(v, nav, 300, 200, 600, 200, 30, t);
        t = walk(v, nav, 600, 200, 600, -100, 30, t);
        walk(v, nav, 600, -100, 900, -100, 30, t);
        var ms = timed(logger, "arrived", v, d);
        logger.debug("arrived=" + nav.arrived + " mem=" + System.getSystemStats().usedMemory);
        return nav.arrived && ms < 1000;
    }

    // Walk in `steps` steps from (n0,e0) to (n1,e1), one per second. Returns the end time.
    function walk(v as OpenNavGView, nav as Navigator, n0 as Numeric, e0 as Numeric,
                  n1 as Numeric, e1 as Numeric, steps as Number, t as Number) as Number {
        for (var i = 1; i <= steps; i++) {
            move(v, nav, n0 + (n1 - n0) * i / steps, e0 + (e1 - e0) * i / steps, t);
            t += 1000;
        }
        return t;
    }

    function max(a as Number, b as Number) as Number {
        return a > b ? a : b;
    }
}
