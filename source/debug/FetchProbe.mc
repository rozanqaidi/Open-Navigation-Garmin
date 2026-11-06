import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// Debug-only live check of the routing servers from the simulator.
// Set RUN = true, build, and run the .prg in the simulator; read the console.
// Processes the result in the same stages as the app (one per compute() call)
// so watchdog problems show up here first.
(:debug)
class FetchProbe {
    const RUN = false;

    hidden var _valhalla as RouteFetcher;
    hidden var _osrm as RouteFetcher;
    hidden var _queue as Array = [];
    hidden var _job as Array? = null;   // [tag, pts, stage]

    function initialize() {
        _valhalla = new RouteFetcher(method(:onValhalla));
        _osrm = new RouteFetcher(method(:onOsrm));
    }

    function start() as Void {
        if (!RUN) {
            return;
        }
        _valhalla.fetchValhalla("https://valhalla1.openstreetmap.de/route",
            [[-6.1754, 106.8272], [-6.2185, 106.8019]], Settings.MODE_RUN);
        var via = [Math.toRadians(-6.1754).toFloat(), Math.toRadians(106.8272).toFloat(),
                   Math.toRadians(-6.1950).toFloat(), Math.toRadians(106.8230).toFloat(),
                   Math.toRadians(-6.2185).toFloat(), Math.toRadians(106.8019).toFloat()] as Array<Float>;
        _osrm.fetchOsrm(via, Settings.MODE_RUN);
        System.println("PROBE started");
    }

    function onValhalla(pts as Array<Float>?, err as Number) as Void {
        queue("VALHALLA", pts, err);
    }

    function onOsrm(pts as Array<Float>?, err as Number) as Void {
        queue("OSRM", pts, err);
    }

    hidden function queue(tag as String, pts as Array<Float>?, err as Number) as Void {
        if (pts == null) {
            System.println("PROBE " + tag + " FAILED err=" + err);
            return;
        }
        System.println("PROBE " + tag + " received raw=" + Polyline.count(pts));
        _queue.add([tag, pts, 1]);
    }

    hidden var _simp as Simplifier? = null;

    // Same stages and budgets as the app.
    function tick() as Void {
        if (_job == null) {
            if (_queue.size() == 0) {
                return;
            }
            _job = _queue[0];
            _queue = _queue.slice(1, _queue.size());
        }
        var job = _job as Array;
        var t0 = System.getTimer();
        if (job[2] == 1) {
            job[1] = Polyline.thin(job[1] as Array<Float>, 5.0);
            _simp = new Simplifier(job[1] as Array<Float>, 5.0);
            System.println("PROBE " + job[0] + " thin -> " + Polyline.count(job[1]) + " ms=" + (System.getTimer() - t0));
            job[2] = 2;
        } else if (job[2] == 2) {
            if ((_simp as Simplifier).step(2500)) {
                job[1] = (_simp as Simplifier).result();
                job.add(new Route(job[0] as String, job[1] as Array<Float>, true));
                job[2] = 3;
            }
            System.println("PROBE " + job[0] + " simplify step ms=" + (System.getTimer() - t0));
        } else {
            var r = job[3] as Route;
            var ready = r.build(300);
            System.println("PROBE " + job[0] + " route step ms=" + (System.getTimer() - t0));
            if (ready) {
                System.println("PROBE " + job[0] + " OK kept=" + r.n + " km=" + (r.total / 1000).format("%.2f")
                    + " turns=" + r.turnType.size());
                _job = null;
            }
        }
    }
}
