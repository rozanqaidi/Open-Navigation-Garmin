import Toybox.Lang;
import Toybox.Math;

// Douglas-Peucker that can be run a little at a time.
// The watch stops any single call that runs too long (watchdog), so
// the view calls step() once per second until done() is true.
class Simplifier {
    hidden var _pts as Array<Float>;
    hidden var _n as Number;
    hidden var _tol2 as Float;
    hidden var _keep as Array<Boolean>;
    hidden var _xs as Array<Float>;
    hidden var _ys as Array<Float>;
    hidden var _stack as Array<Number>;
    hidden var _top as Number;
    hidden var _done as Boolean = false;

    function initialize(pts as Array<Float>, tolM as Float) {
        _pts = pts;
        _n = pts.size() / 2;
        _tol2 = tolM * tolM;
        _keep = new Array<Boolean>[_n];
        _xs = new Array<Float>[_n];
        _ys = new Array<Float>[_n];
        var cosLat = Math.cos(pts[0]);
        var R = Geo.EARTH_RADIUS_M;
        for (var k = 0; k < _n; k++) {
            _keep[k] = false;
            _xs[k] = ((pts[2 * k + 1] - pts[1]) * cosLat * R).toFloat();
            _ys[k] = ((pts[2 * k] - pts[0]) * R).toFloat();
        }
        _stack = new Array<Number>[2 * _n + 2];
        _top = 0;
        if (_n <= 2) {
            _done = true;
            for (var k = 0; k < _n; k++) {
                _keep[k] = true;
            }
            return;
        }
        _keep[0] = true;
        _keep[_n - 1] = true;
        _stack[0] = 0;
        _stack[1] = _n - 1;
        _top = 2;
    }

    function done() as Boolean {
        return _done;
    }

    // Do at most `budget` point checks. Returns true when finished.
    function step(budget as Number) as Boolean {
        var work = 0;
        while (_top > 0 && work < budget) {
            _top -= 2;
            var first = _stack[_top];
            var last = _stack[_top + 1];
            var ax = _xs[first];
            var ay = _ys[first];
            var dx = _xs[last] - ax;
            var dy = _ys[last] - ay;
            var len2 = dx * dx + dy * dy;
            var maxD2 = 0.0;
            var idx = -1;
            for (var k = first + 1; k < last; k++) {
                var px = _xs[k] - ax;
                var py = _ys[k] - ay;
                var t = (len2 > 0) ? (px * dx + py * dy) / len2 : 0.0;
                if (t < 0) { t = 0.0; } else if (t > 1) { t = 1.0; }
                var qx = px - t * dx;
                var qy = py - t * dy;
                var d2 = qx * qx + qy * qy;
                if (d2 > maxD2) {
                    maxD2 = d2;
                    idx = k;
                }
            }
            work += last - first;
            if (idx >= 0 && maxD2 > _tol2) {
                _keep[idx] = true;
                _stack[_top] = first;
                _stack[_top + 1] = idx;
                _stack[_top + 2] = idx;
                _stack[_top + 3] = last;
                _top += 4;
            }
        }
        if (_top == 0) {
            _done = true;
        }
        return _done;
    }

    function result() as Array<Float> {
        var out = [] as Array<Float>;
        for (var k = 0; k < _n; k++) {
            if (_keep[k]) {
                out.add(_pts[2 * k]);
                out.add(_pts[2 * k + 1]);
            }
        }
        return out;
    }
}
