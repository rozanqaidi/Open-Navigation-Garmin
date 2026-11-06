import Toybox.Lang;

// Pure navigation state, free of Toybox.Activity so it can be unit tested.
// All lat/lon/heading values are radians.
class NavState {
    // Moving faster than this (m/s) -> heading from GPS track, else compass.
    const TRACK_HEADING_MIN_SPEED = 1.0;
    // Only take a new track-heading sample after moving this far (m).
    const TRACK_HEADING_MIN_STEP = 4.0;
    // Closer than this to the start counts as "arrived" (m).
    const ARRIVED_RADIUS = 15.0;

    var hasFix as Boolean = false;
    var lat as Float = 0.0;
    var lon as Float = 0.0;
    var startLat as Float? = null;
    var startLon as Float? = null;
    var heading as Float = 0.0;
    var speed as Float = 0.0;

    hidden var _prevLat as Float? = null;
    hidden var _prevLon as Float? = null;

    function initialize() {
    }

    function lostFix() as Void {
        hasFix = false;
    }

    // One GPS sample. activityStartLat/Lon are null until the timer starts.
    // compassHeading is null when the device gives none.
    function update(newLat as Numeric, newLon as Numeric, newSpeed as Numeric?,
                    compassHeading as Numeric?,
                    activityStartLat as Numeric?, activityStartLon as Numeric?) as Void {
        lat = newLat.toFloat();
        lon = newLon.toFloat();
        hasFix = true;
        speed = (newSpeed != null) ? newSpeed.toFloat() : 0.0;

        if (activityStartLat != null && activityStartLon != null) {
            startLat = activityStartLat.toFloat();
            startLon = activityStartLon.toFloat();
        } else if (startLat == null) {
            // Before the timer starts: use the first good fix.
            startLat = lat;
            startLon = lon;
        }

        var pLat = _prevLat;
        var pLon = _prevLon;
        if (pLat == null || pLon == null) {
            _prevLat = lat;
            _prevLon = lon;
        } else if (Geo.distance(pLat, pLon, lat, lon) >= TRACK_HEADING_MIN_STEP) {
            if (speed >= TRACK_HEADING_MIN_SPEED) {
                heading = Geo.bearing(pLat, pLon, lat, lon);
            }
            _prevLat = lat;
            _prevLon = lon;
        }
        if (speed < TRACK_HEADING_MIN_SPEED && compassHeading != null) {
            heading = compassHeading.toFloat();
        }
    }

    function hasStart() as Boolean {
        return startLat != null && startLon != null;
    }

    function distanceToStart() as Float {
        if (!hasStart()) {
            return 0.0;
        }
        return Geo.distance(lat, lon, startLat as Float, startLon as Float);
    }

    // Arrow angle relative to where the user faces (0 = straight ahead).
    function relativeBearingToStart() as Float {
        if (!hasStart()) {
            return 0.0;
        }
        return Geo.wrap(Geo.bearing(lat, lon, startLat as Float, startLon as Float) - heading);
    }

    function arrived() as Boolean {
        return hasStart() && distanceToStart() < ARRIVED_RADIUS;
    }
}
