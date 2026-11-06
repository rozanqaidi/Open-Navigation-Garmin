import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// Storage keys and housekeeping for the street maps saved with each route slot.
module MapStore {
    const BUDGET_BYTES = 80000;     // all maps together; keeps room for the routes

    function metaKey(slot as Number) as String {
        return "map" + slot;
    }

    function chunkKey(slot as Number, c as Number) as String {
        return "map" + slot + "_" + c;
    }

    function meta(slot as Number) as Dictionary? {
        if (slot < 1) {
            return null;
        }
        return Application.Storage.getValue(metaKey(slot)) as Dictionary?;
    }

    // Delete the map of a slot (all chunks + meta).
    function erase(slot as Number) as Void {
        var m = meta(slot);
        var c0 = (m == null) ? null : m["c"];
        var chunks = (c0 instanceof Number) ? c0 + 1 : 60;
        for (var c = 0; c < chunks; c++) {
            Application.Storage.deleteValue(chunkKey(slot, c));
        }
        Application.Storage.deleteValue(metaKey(slot));
    }

    // Bytes used by the maps of all slots except `except`.
    function bytesUsed(except as Number) as Number {
        var sum = 0;
        for (var s = 1; s <= RouteStore.MAX_SLOTS; s++) {
            if (s != except) {
                var m = meta(s);
                var b = (m == null) ? null : m["b"];
                if (b instanceof Number) {
                    sum += b;
                }
            }
        }
        return sum;
    }
}

// Light street map: the streets around a route as plain lines.
// Downloaded once from the Valhalla server (the same server that makes the routes),
// through the phone, and saved with the route slot. After that it is fully offline.
//
// Download: one sample point every ~400 m along the route; for each point Valhalla's
// /expansion service returns the streets reachable within a few hundred metres.
// "auto" gives roads (drawn thicker), "pedestrian" adds alleys and footpaths (thin).
// FOSSGIS allows at most one request per second: one request per compute() call at most.
//
// Storage per slot: meta dictionary + chunks (ByteArray, ~3 sample points each).
// Chunk format, repeated: uint16 header (point count | 0x8000 for roads),
// then count × (int16 x, int16 y) in 2 m units east/north of the map origin.
class StreetMap {
    const ST_NONE = 0;
    const ST_LOADING = 1;
    const ST_WAIT_PHONE = 2;
    const ST_READY = 3;
    const ST_FULL = 4;

    const UNIT_M = 2.0;
    const SPACING_M = 400.0;
    const MAX_SAMPLES = 130;
    const SAMPLES_PER_CHUNK = 3;
    const ROAD_KM = 0.3;
    const PATH_KM = 0.2;
    const SEND_GAP_MS = 900;        // FOSSGIS: at most one request per second (compute() runs once per second)
    const RETRY_MS = 4000;
    const WAIT_PHONE_MS = 15000;
    const BUSY_SERVER_MS = 10000;
    const FEATURES_PER_TICK = 150;
    const BUF_BYTES = 12000;
    const MIN_STEP = 3;             // keep points at least ~6 m apart
    const MIN_PATH = 6;             // drop footpath stubs shorter than ~12 m
    const LIMIT = 32000;            // int16 range in 2 m units ≈ ±64 km
    const DEG_M = 111194.93;        // metres per degree on the sphere used by Geo
    const ROAD_COLOR = 0x505050;
    const PATH_COLOR = 0x343434;

    var status as Number = ST_NONE;
    var drawMs as Number = 0;            // last map drawing time (ms)
    var done as Number = 0;
    var total as Number = 0;

    hidden var _slot as Number = 0;
    hidden var _meta as Dictionary? = null;
    hidden var _olat as Float = 0.0;    // map origin, degrees
    hidden var _olon as Float = 0.0;
    hidden var _kx as Float = 1.0;       // metres per degree of longitude at the origin
    hidden var _server as String = "";
    hidden var _withPaths as Boolean = true;
    hidden var _enabled as Boolean = true;

    // download state
    hidden var _layer as Number = 0;     // 0 = roads, 1 = paths
    hidden var _busy as Boolean = false;
    hidden var _stale as Boolean = false;
    hidden var _nextMs as Number = 0;
    hidden var _lastSentMs as Number = -100000;
    hidden var _tries as Number = 0;
    hidden var _shrink as Boolean = false;
    hidden var _features as Array? = null;
    hidden var _fi as Number = 0;
    hidden var _keys as Dictionary = {};
    hidden var _prevKeys as Dictionary = {};
    hidden var _buf as ByteArray? = null;
    hidden var _len as Number = 0;
    hidden var _bb as Array<Number> = [0, 0, 0, 0] as Array<Number>;
    hidden var _inChunk as Number = 0;
    hidden var _budget as Number = 0;

    // drawing state (members keep the drawing helpers small: small stack)
    hidden var _cache as Dictionary = {};
    hidden var _mx as Float = 0.0;
    hidden var _my as Float = 0.0;
    hidden var _f as Float = 1.0;
    hidden var _sin as Float = 0.0;
    hidden var _cos as Float = 1.0;
    hidden var _cx as Float = 0.0;
    hidden var _cy as Float = 0.0;
    hidden var _lim as Float = 600.0;
    hidden var _slow as Number = 0;     // frames that took too long
    const SLOW_MS = 150;

    function initialize() {
        resetBox();
    }

    // Forget the current slot (route closed or deleted). A request still in flight is discarded.
    function clear() as Void {
        if (_busy) {
            _stale = true;
        }
        _slot = 0;
        _meta = null;
        _features = null;
        _cache = {};
        _buf = null;
        status = ST_NONE;
        done = 0;
        total = 0;
        _len = 0;
        resetBox();
    }

    // Attach to a slot whose route is built. Starts or resumes the download if needed.
    function prepare(slot as Number, route as Route, mode as Number, enabled as Boolean, routeServer as String) as Void {
        clear();
        _slot = slot;
        _enabled = enabled;
        _server = expansionUrl(routeServer);
        var m = MapStore.meta(slot);
        if (m != null && !validMeta(m)) {
            MapStore.erase(slot);
            m = null;
        }
        if (m == null) {
            if (!enabled) {
                return;
            }
            m = newMeta(route, mode);
            try {
                Application.Storage.setValue(MapStore.metaKey(slot), m);
            } catch (e) {
                status = ST_FULL;
                return;
            }
        }
        _meta = m;
        _olat = m["olat"] as Float;
        _olon = m["olon"] as Float;
        _kx = (DEG_M * Math.cos(Math.toRadians(_olat))).toFloat();
        _withPaths = m["p"] as Boolean;
        total = m["n"] as Number;
        done = m["d"] as Number;
        _budget = MapStore.BUDGET_BYTES - MapStore.bytesUsed(slot);
        // Was full, but another route (and its map) has been deleted since: carry on.
        if (m["full"] == true && enabled && _budget - (m["b"] as Number) > BUF_BYTES) {
            m["full"] = false;
        }
        if (m["full"] == true) {
            status = ST_FULL;
        } else if (done >= total) {
            status = ST_READY;
        } else if (enabled) {
            status = ST_LOADING;
            _layer = 0;
            _inChunk = 0;
            _keys = {};
            _prevKeys = {};
            _nextMs = 0;
        }
    }

    hidden function validMeta(m as Dictionary) as Boolean {
        return m["s"] instanceof Array && m["n"] instanceof Number && m["d"] instanceof Number
            && m["c"] instanceof Number && m["b"] instanceof Number && m["bb"] instanceof Array
            && m["olat"] instanceof Float && m["olon"] instanceof Float && m["p"] instanceof Boolean
            && (m["bb"] as Array).size() == 4 * (m["c"] as Number);
    }

    // "https://host/route" → "https://host/expansion". Unknown formats use the public server.
    function expansionUrl(routeServer as String) as String {
        var tail = "/route";
        var n = routeServer.length();
        if (n > tail.length() && routeServer.substring(n - tail.length(), n).equals(tail)) {
            return routeServer.substring(0, n - tail.length()) + "/expansion";
        }
        return "https://valhalla1.openstreetmap.de/expansion";
    }

    // Sample points every ~400 m along the route (degrees), origin at the first one.
    function newMeta(route as Route, mode as Number) as Dictionary {
        var spacing = SPACING_M;
        if (route.total / spacing > MAX_SAMPLES - 1) {
            spacing = route.total / (MAX_SAMPLES - 1);
        }
        var s = [] as Array<Float>;
        var next = 0.0;
        for (var i = 0; i < route.n - 1; i++) {
            var a = route.cum[i];
            var b = route.cum[i + 1];
            while (next <= b && s.size() < 2 * MAX_SAMPLES) {
                var t = (b > a) ? (next - a) / (b - a) : 0.0;
                s.add(Math.toDegrees(route.lat(i) + t * (route.lat(i + 1) - route.lat(i))).toFloat());
                s.add(Math.toDegrees(route.lon(i) + t * (route.lon(i + 1) - route.lon(i))).toFloat());
                next += spacing;
            }
        }
        // Make sure the finish is covered.
        if (route.total - (next - spacing) > spacing / 4 && s.size() < 2 * MAX_SAMPLES) {
            s.add(Math.toDegrees(route.lat(route.n - 1)).toFloat());
            s.add(Math.toDegrees(route.lon(route.n - 1)).toFloat());
        }
        return {
            "olat" => s[0], "olon" => s[1], "s" => s, "n" => s.size() / 2, "d" => 0,
            "c" => 0, "bb" => [] as Array<Number>, "b" => 0, "full" => false,
            "p" => (mode != Settings.MODE_MOTO)
        };
    }

    // ------------------------------------------------------------ download

    // Called once per second from compute().
    function tick(nowMs as Number) as Void {
        if (status != ST_LOADING && status != ST_WAIT_PHONE) {
            return;
        }
        if (_features != null) {
            processSome(nowMs);
            if (_features != null) {
                return;
            }
        }
        if (_busy || nowMs < _nextMs || nowMs - _lastSentMs < SEND_GAP_MS || status == ST_FULL || done >= total) {
            return;
        }
        request();
    }

    hidden function request() as Void {
        var s = (_meta as Dictionary)["s"] as Array<Float>;
        var km = (_layer == 0) ? ROAD_KM : PATH_KM;
        if (_shrink) {
            km = km / 2;
        }
        var body = {
            "locations" => [{ "lat" => s[2 * done], "lon" => s[2 * done + 1] }],
            "costing" => (_layer == 0) ? "auto" : "pedestrian",
            "contours" => [{ "distance" => km }],
            "action" => "isochrone",
            "skip_opposites" => true,
            "dedupe" => true,
            "expansion_properties" => []
        };
        _busy = true;
        _lastSentMs = System.getTimer();
        Communications.makeWebRequest(_server, body, {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:onResponse));
    }

    function onResponse(code as Number, data as Dictionary or String or Null) as Void {
        _busy = false;
        if (_stale) {
            _stale = false;
            return;
        }
        if (_meta == null) {
            return;
        }
        var now = System.getTimer();
        var used = System.getSystemStats().usedMemory;
        if (used > peakMem) {
            peakMem = used;
        }
        if (code == 200) {
            var f = (data instanceof Dictionary) ? data["features"] : null;
            status = ST_LOADING;
            if (f instanceof Array) {
                _features = f;
                _fi = 0;
                processSome(now);
            } else {
                finishLayer(now);
            }
            return;
        }
        if (code == -402 || code == -403) {
            // Response too big for the watch: retry this point with half the radius, then skip it.
            if (!_shrink) {
                _shrink = true;
                _nextMs = now;
            } else {
                finishLayer(now);
            }
            return;
        }
        if (code == 429) {
            _nextMs = now + BUSY_SERVER_MS;
            return;
        }
        if (code < 0 && code > -400) {
            // Phone not reachable (Bluetooth / Garmin Connect closed / timeout): wait, keep trying.
            status = ST_WAIT_PHONE;
            _nextMs = now + WAIT_PHONE_MS;
            return;
        }
        _tries++;
        if (_tries >= 3) {
            finishLayer(now);
        } else {
            _nextMs = now + RETRY_MS;
        }
    }

    // Turn a few features into stored lines per call (watchdog).
    var lastWorkMs as Number = 0;
    var peakMem as Number = 0;          // memory in use while a server response is held

    hidden function processSome(nowMs as Number) as Void {
        var t0 = System.getTimer();
        processBatch(nowMs);
        lastWorkMs = System.getTimer() - t0;
    }

    hidden function processBatch(nowMs as Number) as Void {
        var f = _features as Array;
        var end = _fi + FEATURES_PER_TICK;
        if (end > f.size()) {
            end = f.size();
        }
        while (_fi < end) {
            var feat = f[_fi];
            _fi++;
            if (feat instanceof Dictionary) {
                var g = feat["geometry"];
                if (g instanceof Dictionary && g["coordinates"] instanceof Array) {
                    addEdge(g["coordinates"] as Array, _layer == 0);
                }
            }
            if (status == ST_FULL) {
                _features = null;
                return;
            }
        }
        if (_fi >= f.size()) {
            _features = null;
            finishLayer(nowMs);
        }
    }

    hidden function finishLayer(nowMs as Number) as Void {
        _shrink = false;
        _tries = 0;
        _nextMs = nowMs;
        if (_layer == 0 && _withPaths) {
            _layer = 1;
            return;
        }
        _layer = 0;
        _prevKeys = _keys;
        _keys = {};
        done++;
        _inChunk++;
        if (_inChunk >= SAMPLES_PER_CHUNK || done >= total) {
            flush();
        }
        if (status == ST_FULL) {
            return;
        }
        if (done >= total) {
            status = ST_READY;
            _buf = null;
            _prevKeys = {};
        }
    }

    hidden function saveMeta() as Boolean {
        try {
            Application.Storage.setValue(MapStore.metaKey(_slot), _meta as Dictionary);
            return true;
        } catch (e) {
            status = ST_FULL;
            return false;
        }
    }

    hidden function toX(lon as Numeric) as Number {
        return Math.round((lon - _olon) * _kx / UNIT_M).toNumber();
    }

    hidden function toY(lat as Numeric) as Number {
        return Math.round((lat - _olat) * DEG_M / UNIT_M).toNumber();
    }

    // One street segment from Valhalla: [[lon, lat], ...] in degrees.
    hidden function addEdge(coords as Array, road as Boolean) as Void {
        var n = coords.size();
        if (n < 2) {
            return;
        }
        var a = coords[0] as Array;
        var b = coords[n - 1] as Array;
        var x1 = toX(a[0] as Numeric);
        var y1 = toY(a[1] as Numeric);
        var x2 = toX(b[0] as Numeric);
        var y2 = toY(b[1] as Numeric);
        if (x1.abs() > LIMIT || y1.abs() > LIMIT || x2.abs() > LIMIT || y2.abs() > LIMIT) {
            return;
        }
        // Same street from the previous point or from the roads layer: skip.
        var key = ((x1 * 7919 + y1) * 31) ^ ((x2 * 7919 + y2) * 31);
        if (_keys.hasKey(key) || _prevKeys.hasKey(key)) {
            return;
        }
        _keys[key] = true;
        if (!road && n == 2 && (x2 - x1).abs() + (y2 - y1).abs() < MIN_PATH) {
            return;
        }
        var need = 2 + 4 * n;
        if (need > BUF_BYTES) {
            return;     // absurdly long single edge: skip rather than overflow
        }
        if (_buf == null) {
            _buf = new [BUF_BYTES]b;
            _len = 0;
        }
        if (_len + need > BUF_BYTES) {
            flush();
            if (status == ST_FULL) {
                return;
            }
            _buf = new [BUF_BYTES]b;
        }
        var hdr = _len;
        _len += 2;
        var cnt = 0;
        var lx = 0;
        var ly = 0;
        for (var i = 0; i < n; i++) {
            var c = coords[i] as Array;
            var x = toX(c[0] as Numeric);
            var y = toY(c[1] as Numeric);
            if (i == 0 || i == n - 1 || (x - lx).abs() + (y - ly).abs() >= MIN_STEP) {
                put(x, y);
                cnt++;
                lx = x;
                ly = y;
            }
        }
        var v = cnt | (road ? 0x8000 : 0);
        var buf = _buf as ByteArray;
        buf[hdr] = v & 0xFF;
        buf[hdr + 1] = (v >> 8) & 0xFF;
    }

    hidden function put(x as Number, y as Number) as Void {
        var buf = _buf as ByteArray;
        buf[_len] = x & 0xFF;
        buf[_len + 1] = (x >> 8) & 0xFF;
        buf[_len + 2] = y & 0xFF;
        buf[_len + 3] = (y >> 8) & 0xFF;
        _len += 4;
        if (x < _bb[0]) { _bb[0] = x; }
        if (y < _bb[1]) { _bb[1] = y; }
        if (x > _bb[2]) { _bb[2] = x; }
        if (y > _bb[3]) { _bb[3] = y; }
    }

    // Save the collected lines as one chunk.
    hidden function flush() as Void {
        _inChunk = 0;
        if (_buf == null || _len == 0) {
            resetBox();
            saveProgress();
            return;
        }
        var m = _meta as Dictionary;
        var used = m["b"] as Number;
        if (used + _len > _budget) {
            m["full"] = true;
            status = ST_FULL;
            saveMeta();
            status = ST_FULL;
            _buf = null;
            return;
        }
        var c = m["c"] as Number;
        try {
            Application.Storage.setValue(MapStore.chunkKey(_slot, c), (_buf as ByteArray).slice(0, _len));
        } catch (e) {
            m["full"] = true;
            saveMeta();
            status = ST_FULL;
            _buf = null;
            return;
        }
        (m["bb"] as Array<Number>).addAll(_bb);
        m["c"] = c + 1;
        m["b"] = used + _len;
        _len = 0;
        resetBox();
        saveProgress();
    }

    // Progress is saved only together with the lines it produced, so an interrupted
    // download resumes at the first point whose lines are not stored yet.
    hidden function saveProgress() as Void {
        if (_inChunk == 0 && _len == 0) {
            (_meta as Dictionary)["d"] = done;
        }
        saveMeta();
    }

    hidden function resetBox() as Void {
        _bb = [LIMIT, LIMIT, -LIMIT, -LIMIT] as Array<Number>;
    }

    // ------------------------------------------------------------ drawing

    // Draw the streets around us, heading-up, with the same projection as the route.
    // latR/lonR: our position (radians); scale: px per metre; (cx, cy): our position on screen.
    function draw(dc as Dc, latR as Float, lonR as Float, cx as Float, cy as Float, scale as Float,
                  sin as Float, cos as Float, k as Float, roadsOnly as Boolean) as Void {
        var m = _meta;
        if (m == null || (m["c"] as Number) == 0) {
            return;
        }
        _mx = ((Math.toDegrees(lonR) - _olon) * _kx / UNIT_M).toFloat();
        _my = ((Math.toDegrees(latR) - _olat) * DEG_M / UNIT_M).toFloat();
        _f = (UNIT_M * scale).toFloat();
        _sin = sin;
        _cos = cos;
        _cx = cx;
        _cy = cy;
        _lim = (dc.getWidth() * 1.5).toFloat();
        // Visible radius in map units (screen diagonal from our position).
        var r = dc.getWidth() * 1.2 / _f;
        var bb = m["bb"] as Array<Number>;
        var chunks = m["c"] as Number;
        var visible = [] as Array<ByteArray>;
        var cache = {};
        for (var c = 0; c < chunks; c++) {
            var i = 4 * c;
            if (bb[i] - r > _mx || bb[i + 2] + r < _mx || bb[i + 1] - r > _my || bb[i + 3] + r < _my) {
                continue;
            }
            var ba = _cache[c];
            if (ba == null) {
                ba = Application.Storage.getValue(MapStore.chunkKey(_slot, c));
            }
            if (ba instanceof ByteArray) {
                cache[c] = ba;
                visible.add(ba);
            }
        }
        _cache = cache;
        var t0 = System.getTimer();
        // Safety net: if the watch draws the map too slowly, keep only the roads.
        if (!roadsOnly && _slow < 3) {
            dc.setColor(PATH_COLOR, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth((1.4 * k).toNumber());
            for (var j = 0; j < visible.size(); j++) {
                drawChunk(dc, visible[j], false);
            }
        }
        dc.setColor(ROAD_COLOR, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((3.1 * k).toNumber());
        for (var j = 0; j < visible.size(); j++) {
            drawChunk(dc, visible[j], true);
        }
        drawMs = System.getTimer() - t0;
        if (drawMs > SLOW_MS && _slow < 3) {
            _slow++;
        }
    }

    hidden function drawChunk(dc as Dc, ba as ByteArray, roads as Boolean) as Void {
        var size = ba.size();
        var p = 0;
        while (p + 2 <= size) {
            var h = ba[p] | (ba[p + 1] << 8);
            var n = h & 0x7FFF;
            p += 2;
            if (((h & 0x8000) != 0) != roads) {
                p += 4 * n;
                continue;
            }
            var lx = 0.0;
            var ly = 0.0;
            for (var i = 0; i < n; i++) {
                var x = ba[p] | (ba[p + 1] << 8);
                var y = ba[p + 2] | (ba[p + 3] << 8);
                p += 4;
                if (x >= 32768) { x -= 65536; }
                if (y >= 32768) { y -= 65536; }
                var dx = x - _mx;
                var dy = y - _my;
                var sx = _cx + (dx * _cos - dy * _sin) * _f;
                var sy = _cy - (dx * _sin + dy * _cos) * _f;
                if (i > 0 && (sx.abs() < _lim || lx.abs() < _lim) && (sy.abs() < _lim || ly.abs() < _lim)) {
                    dc.drawLine(lx, ly, sx, sy);
                }
                lx = sx;
                ly = sy;
            }
        }
    }

    // ------------------------------------------------------------ test hooks

    // Feed a ready-made server response for the current point (unit tests).
    (:debug)
    function testFeed(features as Array) as Void {
        _features = features;
        _fi = 0;
        var now = 0;
        while (_features != null) {
            processSome(now);
        }
    }

    // Screen position of a stored point (2 m units) with the last draw() parameters.
    (:debug)
    function testScreen(x as Number, y as Number) as [Float, Float] {
        var dx = x - _mx;
        var dy = y - _my;
        return [_cx + (dx * _cos - dy * _sin) * _f, _cy - (dx * _sin + dy * _cos) * _f];
    }

    (:debug)
    function testUnits(latDeg as Float, lonDeg as Float) as [Number, Number] {
        return [toX(lonDeg), toY(latDeg)];
    }

    (:debug)
    function testMeta() as Dictionary? {
        return _meta;
    }

    (:debug)
    function testLayer() as Number {
        return _layer;
    }
}
