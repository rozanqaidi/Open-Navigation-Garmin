import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// Debug-only live check of the street-map download in the simulator, inside the real
// data-field memory limit. Set RUN = true, build, run the .prg, read the console.
// Route: ~10 km through central Jakarta (Monas → Sudirman → GBK → Senayan).
(:debug)
class MapProbe {
    const RUN = false;
    const SLOT = 5;

    hidden var _map as StreetMap = new StreetMap();
    hidden var _peak as Number = 0;
    hidden var _t0 as Number = 0;
    hidden var _lastDone as Number = -1;
    hidden var _reported as Boolean = false;
    hidden var _maxWork as Number = 0;

    function start() as Void {
        if (!RUN) {
            return;
        }
        MapStore.erase(SLOT);
        var c = [[-6.1754, 106.8272], [-6.1860, 106.8230], [-6.1950, 106.8230], [-6.2080, 106.8180], [-6.2185, 106.8019], [-6.2300, 106.8000], [-6.2260, 106.8150]];
        var pts = [] as Array<Float>;
        for (var i = 0; i < c.size(); i++) {
            pts.add(Math.toRadians(c[i][0]).toFloat());
            pts.add(Math.toRadians(c[i][1]).toFloat());
        }
        _map.prepare(SLOT, new Route("probe", pts, false), Settings.MODE_RUN, true,
                     "https://valhalla1.openstreetmap.de/route");
        _t0 = System.getTimer();
        System.println("MAPPROBE start total=" + _map.total + " mem=" + System.getSystemStats().usedMemory
            + "/" + System.getSystemStats().totalMemory);
    }

    function tick() as Void {
        if (!RUN || _reported) {
            return;
        }
        var t = System.getTimer();
        _map.tick(t);
        var used = System.getSystemStats().usedMemory;
        if (used > _peak) {
            _peak = used;
        }
        if (_map.lastWorkMs > _maxWork) {
            _maxWork = _map.lastWorkMs;
        }
        if (_map.done != _lastDone) {
            _lastDone = _map.done;
            System.println("MAPPROBE " + _map.done + "/" + _map.total + " status=" + _map.status
                + " s=" + (t - _t0) / 1000 + " peakMem=" + _peak);
        }
        if (_map.status == _map.ST_READY || _map.status == _map.ST_FULL) {
            var m = MapStore.meta(SLOT) as Dictionary;
            System.println("MAPPROBE DONE status=" + _map.status + " bytes=" + m["b"] + " chunks=" + m["c"]
                + " seconds=" + (t - _t0) / 1000 + " maxTickMs=" + _maxWork + " peakMem=" + _peak + " responsePeakMem=" + _map.peakMem + "/" + System.getSystemStats().totalMemory);
            _reported = true;
        }
    }

    // Called right after the response is parsed (peak memory while the JSON is alive).
    function sample() as Void {
        var used = System.getSystemStats().usedMemory;
        if (used > _peak) {
            _peak = used;
        }
    }
}
