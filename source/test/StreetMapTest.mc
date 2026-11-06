import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Test;

// Street map: sampling, storage format, de-duplication, memory budget,
// connection errors and drawing time.
(:test)
module StreetMapTest {
    const LAT0 = -6.1965;      // Menteng, degrees
    const LON0 = 106.8345;
    const SLOT = 5;
    const SERVER = "https://valhalla1.openstreetmap.de/route";

    // Degrees for a point n metres north and e metres east of LAT0/LON0.
    function deg(n as Numeric, e as Numeric) as [Float, Float] {
        var lat = LAT0 + n / 111194.93;
        var lon = LON0 + e / (111194.93 * Math.cos(Math.toRadians(LAT0)));
        return [lat.toFloat(), lon.toFloat()];
    }

    // Straight route north, `m` metres long.
    function route(m as Number) as Route {
        var a = deg(0, 0);
        var b = deg(m, 0);
        var pts = [Math.toRadians(a[0]).toFloat(), Math.toRadians(a[1]).toFloat(),
                   Math.toRadians(b[0]).toFloat(), Math.toRadians(b[1]).toFloat()] as Array<Float>;
        return new Route("t", pts, false);
    }

    // One Valhalla feature: a street from (n1,e1) to (n2,e2) metres.
    function edge(n1 as Numeric, e1 as Numeric, n2 as Numeric, e2 as Numeric) as Dictionary {
        var a = deg(n1, e1);
        var b = deg(n2, e2);
        return { "type" => "Feature", "properties" => {},
                 "geometry" => { "type" => "LineString", "coordinates" => [[a[1], a[0]], [b[1], b[0]]] } };
    }

    function reset() as Void {
        for (var s = 1; s <= RouteStore.MAX_SLOTS; s++) {
            MapStore.erase(s);
        }
    }

    // Count stored lines per class in all chunks of a slot: [roads, paths, points].
    function census(slot as Number) as Array<Number> {
        var m = MapStore.meta(slot) as Dictionary;
        var out = [0, 0, 0] as Array<Number>;
        for (var c = 0; c < (m["c"] as Number); c++) {
            var ba = Application.Storage.getValue(MapStore.chunkKey(slot, c)) as ByteArray;
            var p = 0;
            while (p + 2 <= ba.size()) {
                var h = ba[p] | (ba[p + 1] << 8);
                var n = h & 0x7FFF;
                var cls = 1;
                if ((h & 0x8000) != 0) {
                    cls = 0;
                }
                out[cls] = out[cls] + 1;
                out[2] = out[2] + n;
                p += 2 + 4 * n;
            }
        }
        return out;
    }

    (:test)
    function samplesEvery400m(logger as Logger) as Boolean {
        var map = new StreetMap();
        var m1 = map.newMeta(route(1000), Settings.MODE_RUN);
        var m2 = map.newMeta(route(60000), Settings.MODE_MOTO);
        logger.debug("1km n=" + m1["n"] + " 60km n=" + m2["n"] + " paths=" + m1["p"] + "/" + m2["p"]);
        return m1["n"] == 4 && (m2["n"] as Number) <= map.MAX_SAMPLES && (m2["n"] as Number) >= 120
            && m1["p"] == true && m2["p"] == false;
    }

    (:test)
    function serverUrl(logger as Logger) as Boolean {
        var map = new StreetMap();
        return map.expansionUrl(SERVER).equals("https://valhalla1.openstreetmap.de/expansion")
            && map.expansionUrl("https://my.server/valhalla/route").equals("https://my.server/valhalla/expansion")
            && map.expansionUrl("garbage").equals("https://valhalla1.openstreetmap.de/expansion");
    }

    // Roads + paths for every sample point → stored chunks, duplicates and stubs dropped.
    (:test)
    function featuresBecomeChunks(logger as Logger) as Boolean {
        reset();
        var map = new StreetMap();
        map.prepare(SLOT, route(1000), Settings.MODE_RUN, true, SERVER);
        var ok = map.status == map.ST_LOADING && map.total == 4;
        // Point 1, roads: the route street, a cross street.
        map.testFeed([edge(0, 0, 200, 0), edge(100, -150, 100, 150)]);
        ok = ok && map.testLayer() == 1;
        // Point 1, paths: same route street reversed (duplicate), a 5 m stub, a real alley.
        map.testFeed([edge(200, 0, 0, 0), edge(50, 10, 50, 15), edge(150, 0, 150, 80)]);
        ok = ok && map.done == 1 && map.testLayer() == 0;
        // Point 2: the cross street again from the next point (duplicate), plus a new road.
        map.testFeed([edge(100, -150, 100, 150), edge(400, -100, 400, 100)]);
        map.testFeed([]);
        map.testFeed([]);
        map.testFeed([]);
        map.testFeed([edge(900, 0, 1000, 0)]);
        map.testFeed([]);
        var c = census(SLOT);
        var m = MapStore.meta(SLOT) as Dictionary;
        logger.debug("status=" + map.status + " done=" + map.done + " chunks=" + m["c"] + " roads=" + c[0]
            + " paths=" + c[1] + " pts=" + c[2] + " bytes=" + m["b"] + " bb=" + m["bb"]);
        ok = ok && map.status == map.ST_READY && map.done == 4 && c[0] == 4 && c[1] == 1
            && (m["bb"] as Array).size() == 4 * (m["c"] as Number);
        // A new session sees the finished map without downloading again.
        var again = new StreetMap();
        again.prepare(SLOT, route(1000), Settings.MODE_RUN, true, SERVER);
        ok = ok && again.status == again.ST_READY;
        // Deleting the route deletes its map.
        MapStore.erase(SLOT);
        ok = ok && MapStore.meta(SLOT) == null && Application.Storage.getValue(MapStore.chunkKey(SLOT, 0)) == null;
        return ok;
    }

    // All maps together stay under the budget; the download stops with "memory full".
    (:test)
    function budgetStopsDownload(logger as Logger) as Boolean {
        reset();
        Application.Storage.setValue(MapStore.metaKey(4), { "b" => MapStore.BUDGET_BYTES - 20, "c" => 0 });
        var map = new StreetMap();
        map.prepare(SLOT, route(1000), Settings.MODE_MOTO, true, SERVER);
        for (var i = 0; i < 8 && map.status == map.ST_LOADING; i++) {
            map.testFeed([edge(0, 0, 300, 0), edge(100, -150, 100, 150 + i)]);
        }
        logger.debug("status=" + map.status);
        var ok = map.status == map.ST_FULL;
        var again = new StreetMap();
        again.prepare(SLOT, route(1000), Settings.MODE_MOTO, true, SERVER);
        ok = ok && again.status == again.ST_FULL;
        // The other route is deleted: the download carries on by itself.
        MapStore.erase(4);
        var later = new StreetMap();
        later.prepare(SLOT, route(1000), Settings.MODE_MOTO, true, SERVER);
        logger.debug("after delete status=" + later.status);
        ok = ok && later.status == later.ST_LOADING;
        reset();
        return ok;
    }

    // Phone settings changed in the middle of a download: nothing is counted that was not saved.
    (:test)
    function interruptedDownloadResumes(logger as Logger) as Boolean {
        reset();
        var map = new StreetMap();
        map.prepare(SLOT, route(1000), Settings.MODE_MOTO, true, SERVER);
        map.testFeed([edge(0, 0, 300, 0)]);
        map.testFeed([edge(400, -100, 400, 100)]);
        var inMemory = map.done;
        map.clear();                                  // e.g. settings changed on the phone
        var again = new StreetMap();
        again.prepare(SLOT, route(1000), Settings.MODE_MOTO, true, SERVER);
        var resumedAt = again.done;
        again.testFeed([edge(0, 0, 300, 0)]);
        again.testFeed([edge(400, -100, 400, 100)]);
        again.testFeed([edge(700, -100, 700, 100)]);
        again.testFeed([edge(900, 0, 1000, 0)]);
        var c = census(SLOT);
        logger.debug("inMemory=" + inMemory + " resumedAt=" + resumedAt + " status=" + again.status + " roads=" + c[0]);
        reset();
        return inMemory == 2 && resumedAt == 0 && again.status == again.ST_READY && c[0] == 4;
    }

    // A damaged map entry is thrown away and downloaded again instead of crashing.
    (:test)
    function damagedMetaIsRebuilt(logger as Logger) as Boolean {
        reset();
        Application.Storage.setValue(MapStore.metaKey(SLOT), { "c" => "x" });
        var map = new StreetMap();
        map.prepare(SLOT, route(1000), Settings.MODE_RUN, true, SERVER);
        var ok = map.status == map.ST_LOADING && map.total == 4 && MapStore.bytesUsed(0) == 0;
        reset();
        return ok;
    }

    // Phone away, server busy, response too large: wait / retry / shrink, never a crash.
    (:test)
    function connectionErrors(logger as Logger) as Boolean {
        reset();
        var map = new StreetMap();
        map.prepare(SLOT, route(1000), Settings.MODE_RUN, true, SERVER);
        map.onResponse(-104, null);           // Bluetooth not connected
        var ok = map.status == map.ST_WAIT_PHONE && map.done == 0;
        map.onResponse(429, null);            // server busy
        ok = ok && map.done == 0;
        map.onResponse(-402, null);           // too large: shrink once
        ok = ok && map.done == 0 && map.testLayer() == 0;
        map.onResponse(-402, null);           // still too large: skip roads layer
        ok = ok && map.testLayer() == 1;
        map.onResponse(500, null);
        map.onResponse(500, null);
        map.onResponse(500, null);            // third failure: skip paths layer
        ok = ok && map.done == 1;
        map.onResponse(200, "not json");      // odd body: treated as empty
        ok = ok && map.testLayer() == 1 && map.status == map.ST_LOADING;
        // A response that arrives after the route was closed is ignored.
        map.clear();
        map.onResponse(200, { "features" => [edge(0, 0, 100, 0)] });
        ok = ok && map.status == map.ST_NONE;
        logger.debug("ok=" + ok);
        reset();
        return ok;
    }

    // The street map must sit exactly under the route line, for any heading.
    (:test)
    function mapAlignsWithRoute(logger as Logger) as Boolean {
        reset();
        var v = new OpenNavGView();
        var r = route(1200);
        var nav = v.testLoad(r, true);
        var map = v.testMap();
        map.prepare(SLOT, r, Settings.MODE_RUN, true, SERVER);
        map.testFeed([edge(0, 0, 300, 0)]);
        for (var i = 0; i < 20 && map.status == map.ST_LOADING; i++) {
            map.testFeed([]);
        }
        var d = Graphics.createBufferedBitmap({:width => 416, :height => 416}).get().getDc();
        var worst = 0.0;
        var headings = [0, 30, 135, 250];
        for (var h = 0; h < headings.size(); h++) {
            var here = deg(40, 20);
            var lat = Math.toRadians(here[0]).toFloat();
            var lon = Math.toRadians(here[1]).toFloat();
            v.state.update(lat, lon, 0.0, Math.toRadians(headings[h]).toFloat(), lat, lon);
            v.state.heading = Math.toRadians(headings[h]).toFloat();
            nav.update(lat, lon, 3.0, 1000 + h);
            v.onUpdate(d);
            // A street point 150 m north, 60 m west of the route start.
            var q = deg(150, -60);
            var a = v.testProject(Math.toRadians(q[0]).toFloat(), Math.toRadians(q[1]).toFloat());
            var u = map.testUnits(q[0], q[1]);
            var b = map.testScreen(u[0], u[1]);
            var err = Math.sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]));
            logger.debug("heading=" + headings[h] + " route=" + a + " map=" + b + " err px=" + err);
            if (err > worst) {
                worst = err;
            }
        }
        reset();
        return worst < 3.0;
    }

    // Dense street grid (worse than central Bandung) drawn on the navigation screen.
    (:test)
    function denseMapDrawTime(logger as Logger) as Boolean {
        reset();
        var v = new OpenNavGView();
        var r = route(1200);
        var nav = v.testLoad(r, true);
        var map = v.testMap();
        map.prepare(SLOT, r, Settings.MODE_RUN, true, SERVER);
        for (var s = 0; s < map.total; s++) {
            var roads = [] as Array;
            var paths = [] as Array;
            var base = s * 400 - 300;
            for (var i = 0; i < 16; i++) {
                roads.add(edge(base + i * 40, -300, base + i * 40, 300));
                for (var j = 0; j < 6; j++) {
                    paths.add(edge(base + i * 40, -300 + j * 100 + 20, base + i * 40 + 40, -300 + j * 100 + 20));
                }
            }
            map.testFeed(roads);
            map.testFeed(paths);
        }
        var c = census(SLOT);
        var d = Graphics.createBufferedBitmap({:width => 416, :height => 416}).get().getDc();
        var a = Math.toRadians(deg(0, 0)[0]).toFloat();
        var o = Math.toRadians(deg(0, 0)[1]).toFloat();
        var b = Math.toRadians(deg(10, 0)[0]).toFloat();
        v.state.update(a, o, 3.0, null, a, o);
        v.state.update(b, o, 3.0, null, a, o);
        nav.update(b, o, 3.0, 1000);
        var mem0 = System.getSystemStats().usedMemory;
        var t0 = System.getTimer();
        v.onUpdate(d);
        var first = System.getTimer() - t0;
        t0 = System.getTimer();
        for (var i = 0; i < 5; i++) {
            v.onUpdate(d);
        }
        var withMap = (System.getTimer() - t0) / 5;
        var mem1 = System.getSystemStats().usedMemory;
        map.clear();
        t0 = System.getTimer();
        for (var i = 0; i < 5; i++) {
            v.onUpdate(d);
        }
        var noMap = (System.getTimer() - t0) / 5;
        var m = MapStore.meta(SLOT) as Dictionary;
        logger.debug("status=" + map.status + " lines=" + (c[0] + c[1]) + " pts=" + c[2] + " bytes=" + m["b"]
            + " first ms=" + first + " map ms=" + withMap + " nomap ms=" + noMap
            + " mem before draw=" + mem0 + " after=" + mem1 + " total=" + System.getSystemStats().totalMemory);
        reset();
        return withMap < 1000;
    }
}
