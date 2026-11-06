import Toybox.Application;
import Toybox.Lang;

// Phone-editable settings (Connect IQ / Garmin Connect app → Open NavG → Settings).
module Settings {
    const MODE_RUN = 0;
    const MODE_BIKE = 1;
    const MODE_MOTO = 2;

    function get(id as String, fallback) {
        try {
            var v = Application.Properties.getValue(id);
            return (v == null) ? fallback : v;
        } catch (e) {
            return fallback;
        }
    }

    function set(id as String, value) as Void {
        try {
            Application.Properties.setValue(id, value);
        } catch (e) {
            // Property not present (old settings file): ignore.
        }
    }

    function mode() as Number {
        var m = get("mode", MODE_RUN);
        return (m instanceof Number && m >= 0 && m <= 2) ? m : MODE_RUN;
    }

    function str(id as String) as String {
        var v = get(id, "");
        return (v instanceof String) ? v : "";
    }

    function flag(id as String) as Boolean {
        return get(id, false) == true;
    }
}
