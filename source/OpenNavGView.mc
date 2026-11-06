import Toybox.Activity;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.WatchUi;

// Full-screen Open NavG data field (recommended as the LAST data screen of Run/Bike).
class OpenNavGView extends WatchUi.DataField {
    const PH_IDLE = 0;      // no route: arrow back to start
    const PH_LOADING = 1;   // waiting for the routing server / processing
    const PH_ERROR = 2;
    const PH_ROUTE = 3;     // route loaded (ready screen before Start, navigation after)

    var state as NavState = new NavState();

    hidden var _phase as Number = PH_IDLE;
    hidden var _requested as Boolean = false;
    hidden var _route as Route? = null;
    hidden var _nav as Navigator? = null;
    hidden var _slot as Number = 0;
    hidden var _mode as Number = Settings.MODE_RUN;
    hidden var _explore as Boolean = false;
    hidden var _timerOn as Boolean = false;
    hidden var _picker as Boolean = false;
    hidden var _pickerSlots as Array<Number> = [] as Array<Number>;
    hidden var _err as Array<Symbol> = [] as Array<Symbol>;
    hidden var _errRetry as Boolean = false;
    hidden var _fetcher as RouteFetcher?;
    hidden var _map as StreetMap = new StreetMap();

    // Route processing is split over several compute() calls to stay under the watchdog.
    hidden var _stage as Number = 0;
    hidden var _raw as Array<Float>? = null;
    hidden var _pendingSlot as Number = 0;
    hidden var _pendingName as String = "";

    hidden var _strings as Dictionary = {};
    hidden var _probe = null;
    hidden var _mapProbe = null;

    function initialize() {
        DataField.initialize();
        _fetcher = new RouteFetcher(method(:onRouteResult));
        startProbe();
    }

    (:debug)
    hidden function startProbe() as Void {
        _probe = new FetchProbe();
        (_probe as FetchProbe).start();
        _mapProbe = new MapProbe();
        (_mapProbe as MapProbe).start();
    }

    (:release)
    hidden function startProbe() as Void {
    }

    (:debug)
    hidden function probeTick() as Void {
        if (_probe != null) {
            (_probe as FetchProbe).tick();
        }
        if (_mapProbe != null) {
            (_mapProbe as MapProbe).tick();
        }
    }

    (:release)
    hidden function probeTick() as Void {
    }

    // Test hooks (debug builds only, never in the released app).
    (:debug)
    function testLoad(r as Route, timerOn as Boolean) as Navigator {
        _route = r;
        _nav = new Navigator(r, _mode);
        _slot = 1;
        _phase = PH_ROUTE;
        _requested = true;
        _timerOn = timerOn;
        return _nav as Navigator;
    }

    (:debug)
    function testPhase(phase as Number, picker as Boolean) as Void {
        _phase = phase;
        _requested = true;
        _picker = picker;
        if (phase == PH_ERROR) {
            _err = [:NoConnection, :UseSaved, :OrArrowToStart];
            _errRetry = true;
        }
    }

    (:debug)
    function testSetExplore(on as Boolean) as Void {
        _explore = on;
    }

    // Runs the real settings → route pipeline without GPS/activity.
    (:debug)
    function testPipeline(steps as Number) as Number {
        if (!_requested) {
            startRoute();
        }
        for (var i = 0; i < steps && _stage > 0; i++) {
            processStage();
        }
        return _phase;
    }

    (:debug)
    function testProject(lat as Float, lon as Float) as [Float, Float] {
        project(lat, lon);
        return [_px, _py];
    }

    (:debug)
    function testMap() as StreetMap {
        return _map;
    }

    (:debug)
    function testRouteName() as String? {
        var r = _route;
        return (r == null) ? null : r.name;
    }

    function settingsChanged() as Void {
        _requested = false;
        _picker = false;
    }

    // ------------------------------------------------------------ compute

    function compute(info as Activity.Info) as Void {
        var ts = info.timerState;
        _timerOn = (ts != null && ts != Activity.TIMER_STATE_OFF);

        var loc = info.currentLocation;
        var quality = info.currentLocationAccuracy;
        if (loc == null || quality == null || quality < Position.QUALITY_POOR) {
            state.lostFix();
        } else {
            var rad = loc.toRadians();
            var startLat = null;
            var startLon = null;
            var start = info.startLocation;
            if (start != null) {
                var s = start.toRadians();
                startLat = s[0];
                startLon = s[1];
            }
            state.update(rad[0], rad[1], info.currentSpeed, info.currentHeading, startLat, startLon);
        }

        probeTick();
        if (!_requested) {
            startRoute();
        }
        if (_stage > 0) {
            processStage();
        }
        _map.tick(System.getTimer());

        var nav = _nav;
        if (nav != null && state.hasFix && _timerOn) {
            handleEvent(nav.update(state.lat, state.lon, state.speed, System.getTimer()));
        }
    }

    // ------------------------------------------------------------ route loading

    hidden function startRoute() as Void {
        _map.clear();
        RouteStore.applyPhoneDeletes();
        _mode = Settings.mode();
        _explore = Settings.flag("exploreMode");

        var active = Settings.get("activeSlot", 0);
        var dest = Settings.str("destination");
        if (dest.length() == 0 && active instanceof Number && active > 0) {
            _requested = true;
            loadSlot(active);
            return;
        }
        if (dest.length() == 0) {
            _requested = true;
            _phase = PH_IDLE;
            return;
        }

        var name = Settings.str("routeName");
        if (name.length() == 0) {
            _requested = true;
            showError([:NameMissing, :InPhoneSettings], false);
            return;
        }
        var slot = RouteStore.freeSlot();
        if (slot < 0) {
            _requested = true;
            showError([:SlotsFull, :DeleteOnPhone], false);
            return;
        }

        var kind = RouteCode.kind(dest);
        if (kind == RouteCode.KIND_LINE) {
            var pts = RouteCode.points(dest);
            _requested = true;
            if (pts == null) {
                showError([:BadDestination, :InPhoneSettings], false);
            } else {
                beginProcessing(pts, slot, name);
            }
            return;
        }
        if (kind == RouteCode.KIND_VIA) {
            var via = RouteCode.points(dest);
            _requested = true;
            if (via == null) {
                showError([:BadDestination, :InPhoneSettings], false);
                return;
            }
            _pendingSlot = slot;
            _pendingName = name;
            _phase = PH_LOADING;
            (_fetcher as RouteFetcher).fetchOsrm(via, _mode);
            return;
        }

        var target = Destination.parse(dest);
        if (target == null) {
            _requested = true;
            showError([:BadDestination, :InPhoneSettings], false);
            return;
        }
        // Destination routes start where we are: wait for a GPS fix.
        if (!state.hasFix) {
            _phase = PH_IDLE;
            return;
        }
        _requested = true;
        var here = [Math.toDegrees(state.lat).toFloat(), Math.toDegrees(state.lon).toFloat()];
        var points = [here, target];
        if (Settings.flag("returnToStart")) {
            points.add(here);
        }
        _pendingSlot = slot;
        _pendingName = name;
        _phase = PH_LOADING;
        (_fetcher as RouteFetcher).fetchValhalla(Settings.str("serverUrl"), points, _mode);
    }

    function onRouteResult(pts as Array<Float>?, err as Number) as Void {
        if (pts == null || Polyline.count(pts) < 2) {
            showError([(err == 1) ? :NoConnection : :RouteFailed, :UseSaved, :OrArrowToStart], true);
            WatchUi.requestUpdate();
            return;
        }
        beginProcessing(pts, _pendingSlot, _pendingName);
    }

    hidden function beginProcessing(pts as Array<Float>, slot as Number, name as String) as Void {
        _raw = pts;
        _pendingSlot = slot;
        _pendingName = name;
        _stage = 1;
        _phase = PH_LOADING;
    }

    // Work per compute() call, kept well under the watchdog limit.
    const SIMPLIFY_BUDGET = 2500;
    const ROUTE_BUDGET = 300;
    hidden var _simp as Simplifier? = null;
    hidden var _tol as Float = 5.0;
    hidden var _building as Route? = null;

    // One small step per compute() call:
    // 1 thin → 2 simplify (several calls) → 3 save → 4 build route (several calls).
    hidden function processStage() as Void {
        if (_stage == 1) {
            _tol = 5.0;
            _raw = Polyline.thin(_raw as Array<Float>, _tol);
            _simp = new Simplifier(_raw as Array<Float>, _tol);
            _stage = 2;
        } else if (_stage == 2) {
            var simp = _simp as Simplifier;
            if (simp.step(SIMPLIFY_BUDGET)) {
                var result = simp.result();
                if (Polyline.count(result) > 1000 && _tol < 5000) {
                    _tol *= 2;
                    _raw = Polyline.thin(result, _tol);
                    _simp = new Simplifier(_raw as Array<Float>, _tol);
                } else {
                    _raw = result;
                    _simp = null;
                    _stage = 3;
                }
            }
        } else if (_stage == 3) {
            _stage = 0;
            if (!RouteStore.save(_pendingSlot, _pendingName, _raw as Array<Float>, _mode)) {
                _raw = null;
                showError([:StorageFull, :DeleteOnPhone], false);
                return;
            }
            Settings.set("activeSlot", _pendingSlot);
            Settings.set("destination", "");
            Settings.set("routeName", "");
            _raw = null;
            loadSlot(_pendingSlot);
        } else if (_stage == 4) {
            var r = _building as Route;
            if (r.build(ROUTE_BUDGET)) {
                _route = r;
                _nav = new Navigator(r, _mode);
                _building = null;
                _stage = 0;
                _phase = PH_ROUTE;
                _map.prepare(_slot, r, _mode, Settings.get("mapEnabled", true) != false, Settings.str("serverUrl"));
            }
        }
    }

    // Start building a saved route; it becomes active a few seconds later.
    hidden function loadSlot(slot as Number) as Void {
        var d = RouteStore.load(slot);
        if (d == null) {
            showError([:SlotEmpty, :UseSaved], false);
            return;
        }
        _building = new Route(d["name"] as String, d["pts"] as Array<Float>, true);
        _route = null;
        _nav = null;
        _slot = slot;
        _stage = 4;
        _phase = PH_LOADING;
    }

    hidden function showError(lines as Array<Symbol>, retry as Boolean) as Void {
        _err = lines;
        _errRetry = retry;
        _phase = PH_ERROR;
    }

    hidden function handleEvent(ev as Number) as Void {
        if (!(Attention has :vibrate)) {
            return;
        }
        var nav = _nav as Navigator;
        if (ev == nav.EV_TURN) {
            Attention.vibrate([new Attention.VibeProfile(100, 400)]);
        } else if (ev == nav.EV_ARRIVED) {
            Attention.vibrate([new Attention.VibeProfile(100, 1200)]);
        } else if (!_explore && ev == nav.EV_OFF_ROUTE) {
            Attention.vibrate([new Attention.VibeProfile(80, 300)]);
        } else if (!_explore && ev == nav.EV_BACK_ON_ROUTE) {
            Attention.vibrate([new Attention.VibeProfile(60, 200)]);
        }
    }

    // ------------------------------------------------------------ touch

    function handleTap(x as Number, y as Number) as Boolean {
        if (_picker) {
            var h = 416.0;
            var step = h * 0.105;
            var row = ((y - (h * 0.30 - step / 2)) / step).toNumber();
            if (row >= 0 && row < _pickerSlots.size()) {
                var s = _pickerSlots[row];
                Settings.set("activeSlot", s);
                _requested = true;
                loadSlot(s);
            } else if (row == _pickerSlots.size()) {
                _map.clear();
                _route = null;
                _nav = null;
                _phase = PH_IDLE;
            }
            _picker = false;
            WatchUi.requestUpdate();
            return true;
        }
        if (_phase == PH_ERROR && _errRetry) {
            _requested = false;
            _phase = PH_IDLE;
            WatchUi.requestUpdate();
            return true;
        }
        _pickerSlots = RouteStore.usedSlots();
        _picker = true;
        WatchUi.requestUpdate();
        return true;
    }

    // ------------------------------------------------------------ drawing

    hidden function s(id as Symbol) as String {
        var v = _strings[id];
        if (v == null) {
            v = WatchUi.loadResource(Rez.Strings[id]) as String;
            _strings[id] = v;
        }
        return v as String;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setAntiAlias(true);
        if (_picker) {
            drawPicker(dc);
        } else if (_phase == PH_LOADING) {
            Draw.line(dc, dc.getHeight() * 0.47, s(:GettingRoute), Graphics.FONT_MEDIUM, 0xDDDDDD);
        } else if (_phase == PH_ERROR) {
            drawError(dc);
        } else if (_phase == PH_ROUTE) {
            var nav = _nav as Navigator;
            if (nav.arrived) {
                drawArrived(dc, nav);
            } else if (!_timerOn) {
                drawReady(dc);
            } else {
                drawNav(dc, nav);
            }
        } else {
            drawStartArrow(dc);
        }
    }

    hidden function drawStartArrow(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        if (!state.hasFix || !state.hasStart()) {
            Draw.line(dc, h * 0.47, s(:WaitingGps), Graphics.FONT_MEDIUM, 0xDDDDDD);
            return;
        }
        Draw.line(dc, h * 0.19, s(:ToStart), Graphics.FONT_SMALL, 0xAAAAAA);
        if (state.arrived()) {
            dc.setColor(Draw.GREEN, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(w / 2, h / 2, w * 0.08);
        } else {
            Draw.arrow(dc, w / 2, h / 2, w * 0.22, state.relativeBearingToStart());
        }
        Draw.line(dc, h * 0.80, Geo.formatDistance(state.distanceToStart()), Graphics.FONT_LARGE, Graphics.COLOR_WHITE);
    }

    hidden function drawError(dc as Dc) as Void {
        var h = dc.getHeight();
        var ys = [0.36, 0.48, 0.58];
        for (var i = 0; i < _err.size() && i < 3; i++) {
            Draw.line(dc, h * ys[i], s(_err[i]), i == 0 ? Graphics.FONT_MEDIUM : Graphics.FONT_SMALL,
                      i == 0 ? Draw.YELLOW : 0xDDDDDD);
        }
        if (_errRetry) {
            Draw.line(dc, h * 0.75, s(:TapRetry), Graphics.FONT_SMALL, 0xBBBBBB);
        }
    }

    hidden function drawPicker(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        Draw.line(dc, h * 0.19, s(:ChooseRoute), Graphics.FONT_SMALL, 0xBBBBBB);
        var step = h * 0.105;
        for (var i = 0; i <= _pickerSlots.size(); i++) {
            var y = h * 0.30 + i * step;
            var label;
            if (i < _pickerSlots.size()) {
                var d = RouteStore.load(_pickerSlots[i]);
                label = (d == null) ? "-" : d["name"] as String;
                if (_pickerSlots[i] == _slot && _phase == PH_ROUTE) {
                    dc.setColor(0x16324F, Graphics.COLOR_TRANSPARENT);
                    dc.fillRoundedRectangle(w * 0.18, y - step * 0.42, w * 0.64, step * 0.84, step * 0.25);
                }
            } else {
                label = s(:ArrowToStart);
            }
            Draw.line(dc, y, label, Graphics.FONT_SMALL, Graphics.COLOR_WHITE);
        }
    }

    hidden function drawReady(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var r = _route as Route;
        Draw.line(dc, h * 0.20, s(:RouteReady), Graphics.FONT_SMALL, Draw.GREEN);
        drawMiniRoute(dc, r, w / 2, h * 0.45, w * 0.36);
        Draw.line(dc, h * 0.70, r.name, Graphics.FONT_SMALL, Graphics.COLOR_WHITE);
        Draw.line(dc, h * 0.80, Geo.formatDistance(r.total) + " · " + s(:TapToChange), Graphics.FONT_XTINY, 0xBBBBBB);
        drawMapStatus(dc, h * 0.89);
    }

    // Map download progress, so a slow download is not mistaken for an error.
    hidden function drawMapStatus(dc as Dc, y as Numeric) as Void {
        var st = _map.status;
        if (st == _map.ST_LOADING) {
            Draw.line(dc, y, s(:Map) + " " + _map.done + "/" + _map.total + " · " + s(:KeepPhoneClose), Graphics.FONT_XTINY, Draw.YELLOW);
        } else if (st == _map.ST_WAIT_PHONE) {
            Draw.line(dc, y, s(:WaitingPhone), Graphics.FONT_XTINY, Draw.YELLOW);
        } else if (st == _map.ST_READY) {
            Draw.line(dc, y, s(:MapReady), Graphics.FONT_XTINY, Draw.GREEN);
        } else if (st == _map.ST_FULL) {
            Draw.line(dc, y, s(:MapFull), Graphics.FONT_XTINY, 0xBBBBBB);
        }
    }

    // Whole route, north-up, fitted into a box of size `size` centred at (cx, cy).
    hidden function drawMiniRoute(dc as Dc, r as Route, cx as Numeric, cy as Numeric, size as Numeric) as Void {
        var minLat = 9.0; var maxLat = -9.0; var minLon = 9.0; var maxLon = -9.0;
        for (var i = 0; i < r.n; i++) {
            var la = r.lat(i); var lo = r.lon(i);
            if (la < minLat) { minLat = la; } if (la > maxLat) { maxLat = la; }
            if (lo < minLon) { minLon = lo; } if (lo > maxLon) { maxLon = lo; }
        }
        var cosLat = Math.cos((minLat + maxLat) / 2);
        var spanX = (maxLon - minLon) * cosLat;
        var spanY = maxLat - minLat;
        var span = (spanX > spanY) ? spanX : spanY;
        if (span <= 0) {
            return;
        }
        var k = size / span;
        var midLon = (minLon + maxLon) / 2;
        var midLat = (minLat + maxLat) / 2;
        dc.setColor(Draw.BLUE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(6);
        var px = 0; var py = 0;
        for (var i = 0; i < r.n; i++) {
            var x = cx + (r.lon(i) - midLon) * cosLat * k;
            var y = cy - (r.lat(i) - midLat) * k;
            if (i > 0) {
                dc.drawLine(px, py, x, y);
            }
            px = x; py = y;
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx + (r.lon(0) - midLon) * cosLat * k, cy - (r.lat(0) - midLat) * k, 6);
    }

    hidden function drawArrived(dc as Dc, nav as Navigator) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var k = w / 200.0;
        Draw.pin(dc, w / 2, h * 0.20, k * 1.3);
        Draw.line(dc, h * 0.45, s(:Arrived), Graphics.FONT_LARGE, Draw.GREEN);
        Draw.line(dc, h * 0.58, Geo.formatDistance(nav.route.total), Graphics.FONT_MEDIUM, Graphics.COLOR_WHITE);
        Draw.line(dc, h * 0.70, s(:SavedInSlot) + " " + _slot, Graphics.FONT_XTINY, 0xBBBBBB);
    }

    // ---------- navigation screen ----------

    // Heading-up projection, kept in members so drawing helpers stay small
    // (the watch has a small stack).
    hidden var _tcx as Float = 0.0;
    hidden var _tmeY as Float = 0.0;
    hidden var _tscale as Float = 1.0;
    hidden var _tsin as Float = 0.0;
    hidden var _tcos as Float = 1.0;
    hidden var _tcosLat as Float = 1.0;
    hidden var _px as Float = 0.0;
    hidden var _py as Float = 0.0;

    hidden function project(lat as Float, lon as Float) as Void {
        var dx = (lon - state.lon) * _tcosLat * Geo.EARTH_RADIUS_M;
        var dy = (lat - state.lat) * Geo.EARTH_RADIUS_M;
        _px = (_tcx + (dx * _tcos - dy * _tsin) * _tscale).toFloat();
        _py = (_tmeY - (dx * _tsin + dy * _tcos) * _tscale).toFloat();
    }

    hidden function drawNav(dc as Dc, nav as Navigator) as Void {
        var h = dc.getHeight();
        var k = dc.getWidth() / 200.0;
        _tcx = dc.getWidth() / 2.0;
        _tmeY = h * 0.66;
        var range = (_mode == Settings.MODE_MOTO) ? 1000.0 : ((_mode == Settings.MODE_BIKE) ? 500.0 : 250.0);
        _tscale = ((_tmeY - h * 0.05) / range).toFloat();
        _tsin = Math.sin(state.heading).toFloat();
        _tcos = Math.cos(state.heading).toFloat();
        _tcosLat = Math.cos(state.lat).toFloat();

        _map.draw(dc, state.lat, state.lon, _tcx, _tmeY, _tscale, _tsin, _tcos, k, _mode == Settings.MODE_MOTO);
        drawRouteLine(dc, nav);
        if (nav.isOff) {
            drawOffOverlay(dc, nav, k);
        }
        Draw.youAreHere(dc, _tcx, _tmeY - 10 * k, k);

        // Header last, so it sits on top of the route.
        if (nav.isOff) {
            drawOffHeader(dc, nav, k);
        } else if (System.getTimer() < nav.backUntilMs) {
            drawBackHeader(dc, k);
        } else {
            drawTurnHeader(dc, nav, k);
        }
        drawFooter(dc, nav);
    }

    // Grey behind us, blue ahead.
    hidden function drawRouteLine(dc as Dc, nav as Navigator) as Void {
        var r = nav.route;
        var lim = dc.getWidth() * 1.5;
        var from = nav.seg - 150;
        if (from < 0) { from = 0; }
        var to = nav.seg + 400;
        if (to > r.n - 1) { to = r.n - 1; }
        dc.setPenWidth(10);
        var lx = 0.0;
        var ly = 0.0;
        for (var i = from; i <= to; i++) {
            project(r.lat(i), r.lon(i));
            if (i > from && (_px.abs() < lim || lx.abs() < lim) && (_py.abs() < lim || ly.abs() < lim)) {
                dc.setColor(i <= nav.seg ? Draw.GREY : Draw.BLUE, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(lx, ly, _px, _py);
            }
            lx = _px;
            ly = _py;
        }
    }

    // Our trail (green dots) and the way back to the route (red dashes + dot).
    hidden function drawOffOverlay(dc as Dc, nav as Navigator, k as Float) as Void {
        var t = nav.trail;
        dc.setColor(Draw.GREEN, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < t.size(); i += 4) {
            project(t[i], t[i + 1]);
            dc.fillCircle(_px, _py, 3);
        }
        project(nav.rejoinLat, nav.rejoinLon);
        dc.setColor(Draw.RED, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(6);
        Draw.dashed(dc, _tcx, _tmeY, _px, _py, 6 * k, 4 * k);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_px, _py, 6 * k);
        dc.setColor(Draw.RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_px, _py, 5 * k);
    }

    hidden function drawBackHeader(dc as Dc, k as Float) as Void {
        var text = s(:BackOnRoute);
        var f = Draw.fitFont(dc, text, 36 * k, Graphics.FONT_SMALL);
        var total = 16 * k + dc.getTextWidthInPixels(text, f);
        var x0 = dc.getWidth() / 2 - total / 2;
        Draw.check(dc, x0, 28 * k, k, Draw.GREEN);
        Draw.haloText(dc, x0 + 16 * k, 36 * k, f, text, Draw.GREEN,
                      Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawFooter(dc as Dc, nav as Navigator) as Void {
        var h = dc.getHeight();
        if (_mode == Settings.MODE_MOTO) {
            Draw.line(dc, h * 0.80, (state.speed * 3.6).format("%d") + " km/h", Graphics.FONT_XTINY, 0xBBBBBB);
        }
        Draw.line(dc, h * 0.87, Geo.formatDistance(nav.remaining) + " " + s(:Left), Graphics.FONT_XTINY, 0xBBBBBB);
    }

    // Icon + distance as one measured, centred group; yellow bar under it.
    hidden function drawTurnHeader(dc as Dc, nav as Navigator, k as Float) as Void {
        var cx = dc.getWidth() / 2;
        var cy = 36 * k;
        var type = nav.headerType();
        var text = Geo.formatDistance(nav.distToNext);
        var font = Draw.fontForHeight(20 * k);
        var iconW = 24 * k;
        var iconH = 28 * k;
        var gap = 7 * k;
        var tw = dc.getTextWidthInPixels(text, font);
        var total = iconW + gap + tw;
        // Keep the group inside the 90% circle: shrink the font if needed.
        var r = dc.getWidth() / 2.0 * 0.90;
        var dy = cy - dc.getHeight() / 2.0;
        var chord = 2 * Math.sqrt(r * r - dy * dy);
        while (total > chord && font != Graphics.FONT_XTINY) {
            font = (font == Graphics.FONT_LARGE) ? Graphics.FONT_MEDIUM
                 : (font == Graphics.FONT_MEDIUM) ? Graphics.FONT_SMALL
                 : (font == Graphics.FONT_SMALL) ? Graphics.FONT_TINY : Graphics.FONT_XTINY;
            tw = dc.getTextWidthInPixels(text, font);
            total = iconW + gap + tw;
        }
        var x0 = cx - total / 2;
        Draw.turnIcon(dc, type, x0, cy - iconH / 2, k);
        Draw.haloText(dc, x0 + iconW + gap, cy, font, text, Graphics.COLOR_WHITE,
                      Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        var th = Graphics.getFontHeight(font);
        var barY = cy + ((iconH > th) ? iconH : th) / 2 + 6 * k;
        var barW = (total > 70 * k) ? total : 70 * k;
        Draw.bar(dc, cx - barW / 2, barY, barW, 4 * k, nav.barFraction());
    }

    hidden function drawOffHeader(dc as Dc, nav as Navigator, k as Float) as Void {
        var cx = dc.getWidth() / 2;
        var cy = 36 * k;
        var text = Geo.formatDistance(nav.rejoinDist);
        var font = Draw.fontForHeight(20 * k);
        var iconW = 24 * k * 0.8;
        var gap = 6 * k;
        var tw = dc.getTextWidthInPixels(text, font);
        var total = iconW + gap + tw;
        var x0 = cx - total / 2;
        Draw.returnIcon(dc, x0, cy - 28 * k * 0.8 / 2, k * 0.8);
        Draw.haloText(dc, x0 + iconW + gap, cy, font, text, Draw.RED,
                      Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        if (_explore) {
            Draw.compass(dc, cx + 40 * k, cy + 30 * k, k);
        }
    }
}
