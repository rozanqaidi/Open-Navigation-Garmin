import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;

// Asks a free routing server for a route, through the phone's connection.
//  - Destination (A → B [→ A]): Valhalla, which can avoid toll roads for motorbikes.
//  - Via-point codes (many points): OSRM, because the public Valhalla allows only 10 points.
// The result is handed back as a flat lat/lon radian array, or null with an error code.
class RouteFetcher {
    const ERR_NONE = 0;
    const ERR_NO_CONNECTION = 1;
    const ERR_SERVER = 2;

    const OSRM_URL = "https://routing.openstreetmap.de/";

    hidden var _onDone as Method(pts as Array<Float>?, err as Number) as Void;

    function initialize(onDone as Method(pts as Array<Float>?, err as Number) as Void) {
        _onDone = onDone;
    }

    // points: Array of [latDeg, lonDeg]
    function fetchValhalla(server as String, points as Array, mode as Number) as Void {
        var costing = (mode == Settings.MODE_MOTO) ? "motorcycle"
                    : (mode == Settings.MODE_BIKE) ? "bicycle" : "pedestrian";
        var locations = [];
        for (var i = 0; i < points.size(); i++) {
            locations.add({ "lat" => points[i][0], "lon" => points[i][1] });
        }
        var body = {
            "locations" => locations,
            "costing" => costing,
            "directions_type" => "none"
        };
        if (mode == Settings.MODE_MOTO) {
            body["costing_options"] = { "motorcycle" => { "use_highways" => 0, "use_tolls" => 0 } };
        }
        Communications.makeWebRequest(server, body, {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:onValhalla));
    }

    // pts: flat lat/lon radians (decoded from a NAVG1V code)
    function fetchOsrm(pts as Array<Float>, mode as Number) as Void {
        var profile = (mode == Settings.MODE_MOTO) ? "routed-car"
                    : (mode == Settings.MODE_BIKE) ? "routed-bike" : "routed-foot";
        var coords = "";
        for (var i = 0; i < pts.size(); i += 2) {
            if (i > 0) {
                coords += ";";
            }
            coords += Math.toDegrees(pts[i + 1]).format("%.5f") + "," + Math.toDegrees(pts[i]).format("%.5f");
        }
        var url = OSRM_URL + profile + "/route/v1/driving/" + coords;
        Communications.makeWebRequest(url, { "overview" => "full", "geometries" => "polyline", "steps" => "false" }, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:onOsrm));
    }

    function onValhalla(code as Number, data as Dictionary or String or Null) as Void {
        if (code != 200 || !(data instanceof Dictionary)) {
            _onDone.invoke(null, errorFor(code));
            return;
        }
        try {
            var legs = (data["trip"] as Dictionary)["legs"] as Array;
            var all = [] as Array<Float>;
            for (var i = 0; i < legs.size(); i++) {
                var p = Polyline.decode((legs[i] as Dictionary)["shape"] as String, 6);
                // Each leg starts where the previous one ended: skip the duplicate.
                var from = (all.size() > 0) ? 2 : 0;
                for (var k = from; k < p.size(); k++) {
                    all.add(p[k]);
                }
            }
            _onDone.invoke(all, ERR_NONE);
        } catch (e) {
            _onDone.invoke(null, ERR_SERVER);
        }
    }

    function onOsrm(code as Number, data as Dictionary or String or Null) as Void {
        if (code != 200 || !(data instanceof Dictionary)) {
            _onDone.invoke(null, errorFor(code));
            return;
        }
        try {
            var routes = data["routes"] as Array;
            var geometry = (routes[0] as Dictionary)["geometry"] as String;
            _onDone.invoke(Polyline.decode(geometry, 5), ERR_NONE);
        } catch (e) {
            _onDone.invoke(null, ERR_SERVER);
        }
    }

    // Negative codes are Connect IQ / Bluetooth errors (phone not reachable etc.).
    function errorFor(code as Number) as Number {
        return (code < 0) ? ERR_NO_CONNECTION : ERR_SERVER;
    }
}
