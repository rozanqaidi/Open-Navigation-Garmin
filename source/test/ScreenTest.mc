import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Test;
import Toybox.WatchUi;

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

    // Every text on every screen must fit the round screen (90% circle)
    // without being cut. Draw.line counts texts that did not fit.
    (:test)
    function allTextFits(logger as Logger) as Boolean {
        var d = dc();
        Draw.overflows = 0;
        var v = new OpenNavGView();
        v.onUpdate(d);                                    // waiting for GPS
        v.state.update(LAT0, LON0, 0, null, null, null);
        v.state.update(p(1200, 50)[0], p(1200, 50)[1], 3.0, null, null, null);
        v.onUpdate(d);                                    // arrow to start
        v.testPhase(v.PH_LOADING, false);
        v.onUpdate(d);
        var errs = [[:NoConnection, :UseSaved, :OrArrowToStart], [:RouteFailed, :UseSaved, :OrArrowToStart],
                    [:SlotsFull, :DeleteOnPhone], [:NameMissing, :InPhoneSettings],
                    [:BadDestination, :InPhoneSettings], [:SlotEmpty, :UseSaved],
                    [:StorageFull, :DeleteOnPhone]];
        for (var i = 0; i < errs.size(); i++) {
            v.testError(errs[i] as Array<Symbol>, i < 2);
            v.onUpdate(d);
        }
        var nav = v.testLoad(route(), false);
        var m = v.testMap();
        var sts = [m.ST_NONE, m.ST_LOADING, m.ST_WAIT_PHONE, m.ST_READY, m.ST_FULL];
        for (var i = 0; i < sts.size(); i++) {
            m.status = sts[i];
            m.done = 188;
            m.total = 188;
            v.onUpdate(d);                                // ready screen, each map state
        }
        m.status = m.ST_NONE;
        v.testPhase(v.PH_ROUTE, true);
        v.onUpdate(d);                                    // picker
        var modes = [Settings.MODE_RUN, Settings.MODE_BIKE, Settings.MODE_MOTO];
        for (var mi = 0; mi < modes.size(); mi++) {
            v = new OpenNavGView();
            v.testMode(modes[mi]);
            nav = v.testLoad(route(), true);
            walk(v, nav, 0, 0, 150, 0, 15, 0);
            v.onUpdate(d);                                // nav
            for (var s = 0; s < 14; s++) {
                move(v, nav, 290 + s * 2, -60 - s * 3, 40000 + s * 1000);
            }
            v.onUpdate(d);                                // off route
            for (var s = 0; s < 4; s++) {
                move(v, nav, 300, 60, 60000 + s * 1000);
            }
            v.onUpdate(d);                                // back on route
        }
        v = new OpenNavGView();
        nav = v.testLoad(route(), true);
        var t = walk(v, nav, 0, 0, 300, 0, 30, 0);
        t = walk(v, nav, 300, 0, 300, 200, 20, t);
        t = walk(v, nav, 300, 200, 600, 200, 30, t);
        t = walk(v, nav, 600, 200, 600, -100, 30, t);
        walk(v, nav, 600, -100, 900, -100, 30, t);
        v.onUpdate(d);                                    // arrived
        logger.debug("overflows (device language)=" + Draw.overflows);

        // Indonesian texts, measured at the same rows with the smallest font they may use.
        // [text, row as fraction of the height]
        var id = [["Rute siap", 0.17], ["tap untuk ganti", 0.70], ["10.5 km · tap untuk ganti", 0.70],
                  ["Peta 188/188", 0.79], ["dekatkan HP", 0.87], ["Menunggu HP", 0.79],
                  ["Peta siap", 0.79], ["Memori peta penuh", 0.79], ["hapus satu rute", 0.87],
                  ["Mengambil rute...", 0.47], ["Menunggu GPS", 0.47], ["KE START", 0.19],
                  ["Tidak ada koneksi", 0.36], ["Gagal ambil rute", 0.36], ["Pakai rute tersimpan", 0.48],
                  ["atau panah ke start", 0.58], ["Tap untuk coba lagi", 0.75], ["5 slot sudah penuh", 0.36],
                  ["Hapus satu di HP", 0.48], ["Isi nama rute", 0.36], ["di pengaturan HP", 0.48],
                  ["Tujuan tidak dikenali", 0.36], ["Rute tersimpan kosong", 0.36], ["Memori jam penuh", 0.36],
                  ["Sampai", 0.45], ["Tersimpan di slot 5", 0.70], ["Pilih rute", 0.17],
                  ["Panah ke start", 0.86], ["99.9 km lagi", 0.87], ["123 km/h", 0.80]];
        // English texts, same rows (the watch shows English or Indonesian depending on its language).
        var en = [["Route ready", 0.17], ["188.8 km · tap to change", 0.70],
                  ["Map 188/188", 0.79], ["keep phone close", 0.87], ["Waiting for phone", 0.79],
                  ["Map ready", 0.79], ["Map memory full", 0.79], ["delete a route", 0.87],
                  ["Getting route...", 0.47], ["Waiting for GPS", 0.47], ["TO START", 0.19],
                  ["No connection", 0.36], ["Route failed", 0.36], ["Use a saved route", 0.48],
                  ["or the arrow to start", 0.58], ["Tap to retry", 0.75], ["All 5 slots are full", 0.36],
                  ["Delete one on your phone", 0.48], ["Add a route name", 0.36], ["in the phone settings", 0.48],
                  ["Destination not recognised", 0.36], ["Saved route is empty", 0.36], ["Watch memory full", 0.36],
                  ["Arrived", 0.45], ["Saved in slot 5", 0.70], ["Choose route", 0.17],
                  ["Arrow to start", 0.86], ["99.9 km left", 0.87], ["123 km/h", 0.80]];
        id.addAll(en);
        id.addAll([["99.9 km · tap untuk ganti", 0.70]]);
        logger.debug("device language sample: '" + WatchUi.loadResource(Rez.Strings.Left) + "'");
        var bad = 0;
        for (var i = 0; i < id.size(); i++) {
            var y = 416 * (id[i][1] as Float);
            var w = d.getTextWidthInPixels(id[i][0] as String, Graphics.FONT_XTINY);
            if (w > Draw.chordAt(d, y)) {
                logger.debug("too wide: " + id[i][0] + " w=" + w + " room=" + Draw.chordAt(d, y));
                bad++;
            }
        }
        // Self-check: the 0.3.1 one-line map status (cut off on the watch) must be caught.
        var old = d.getTextWidthInPixels("Map 12/40 · keep phone close", Graphics.FONT_XTINY);
        var caught = old > Draw.chordAt(d, 416 * 0.89);
        logger.debug("old 0.3.1 line w=" + old + " room=" + Draw.chordAt(d, 416 * 0.89) + " caught=" + caught);
        return Draw.overflows == 0 && bad == 0 && caught;
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
