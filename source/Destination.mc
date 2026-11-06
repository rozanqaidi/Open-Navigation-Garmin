import Toybox.Lang;

// Parses the "Tujuan" setting typed or pasted on the phone.
// Accepts:  "-6.2185, 106.8019"   "-6.2185,106.8019"
//           Google Maps links containing "@-6.2185,106.8019,17z" or "q=-6.2185,106.8019"
// Returns [latDeg, lonDeg] or null.
module Destination {
    function parse(text as String?) as [Float, Float]? {
        if (text == null) {
            return null;
        }
        var s = text;
        // Prefer the part after '@' or 'q=' in map links.
        var at = s.find("@");
        if (at != null) {
            s = s.substring(at + 1, s.length()) as String;
        } else {
            var q = s.find("q=");
            if (q != null) {
                s = s.substring(q + 2, s.length()) as String;
            }
        }
        var nums = numbers(s);
        if (nums.size() < 2) {
            return null;
        }
        var lat = nums[0];
        var lon = nums[1];
        if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
            return null;
        }
        return [lat, lon];
    }

    // Pulls decimal numbers (with optional '-') out of a string, in order.
    function numbers(s as String) as Array<Float> {
        var out = [] as Array<Float>;
        var chars = s.toCharArray();
        var token = "";
        for (var i = 0; i <= chars.size(); i++) {
            var c = (i < chars.size()) ? chars[i] : ' ';
            var isNumChar = (c >= '0' && c <= '9') || c == '.' || (c == '-' && token.length() == 0);
            if (isNumChar) {
                token += c.toString();
            } else {
                if (token.length() > 0 && !token.equals("-") && !token.equals(".")) {
                    var v = token.toFloat();
                    if (v != null) {
                        out.add(v);
                    }
                }
                token = "";
                if (out.size() >= 2) {
                    break;
                }
            }
        }
        return out;
    }
}
