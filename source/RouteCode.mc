import Toybox.Lang;

// Route codes produced by the Open NavG planner web page:
//   "NAVG1L:<polyline5>"  line   – follow this exact line, no server needed
//   "NAVG1V:<polyline5>"  via    – route through these points on real roads (OSRM)
module RouteCode {
    const KIND_NONE = 0;
    const KIND_LINE = 1;
    const KIND_VIA = 2;

    function kind(text as String) as Number {
        var s = trimmed(text);
        if (s.length() < 8 || !s.substring(0, 5).equals("NAVG1") || !s.substring(6, 7).equals(":")) {
            return KIND_NONE;
        }
        var k = s.substring(5, 6);
        if (k.equals("L")) {
            return KIND_LINE;
        }
        if (k.equals("V")) {
            return KIND_VIA;
        }
        return KIND_NONE;
    }

    // Decoded points (flat lat/lon radians), or null for a broken code.
    function points(text as String) as Array<Float>? {
        var s = trimmed(text);
        try {
            var pts = Polyline.decode(s.substring(7, s.length()) as String, 5);
            return (Polyline.count(pts) >= 2) ? pts : null;
        } catch (e) {
            return null;
        }
    }

    // Drop spaces / line breaks that copy-paste can add.
    function trimmed(text as String) as String {
        var chars = text.toCharArray();
        var out = "";
        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i];
            if (c != ' ' && c != '\n' && c != '\r' && c != '\t') {
                out += c.toString();
            }
        }
        return out;
    }
}
