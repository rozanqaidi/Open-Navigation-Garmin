import Toybox.Application;
import Toybox.Lang;

// Saved routes on the watch: slots 1..MAX_SLOTS in Application.Storage.
// Each slot: { "name" => String, "pts" => Array<Float> (flat lat/lon radians),
//              "len" => Float metres, "mode" => Number }.
// Slot names are mirrored into the phone settings (slotNName) so they can be
// seen and deleted from the phone.
module RouteStore {
    const MAX_SLOTS = 5;

    function key(slot as Number) as String {
        return "route" + slot;
    }

    function load(slot as Number) as Dictionary? {
        if (slot < 1 || slot > MAX_SLOTS) {
            return null;
        }
        return Application.Storage.getValue(key(slot)) as Dictionary?;
    }

    function save(slot as Number, name as String, pts as Array<Float>, mode as Number) as Void {
        Application.Storage.setValue(key(slot), {
            "name" => name,
            "pts" => pts,
            "len" => Polyline.lengthM(pts),
            "mode" => mode
        });
        Settings.set("slot" + slot + "Name", name);
    }

    function remove(slot as Number) as Void {
        Application.Storage.deleteValue(key(slot));
        Settings.set("slot" + slot + "Name", "");
        Settings.set("slot" + slot + "Delete", false);
        if (Settings.get("activeSlot", 0) == slot) {
            Settings.set("activeSlot", 0);
        }
    }

    // First empty slot, or -1 when all slots are used (user must delete one).
    function freeSlot() as Number {
        for (var s = 1; s <= MAX_SLOTS; s++) {
            if (load(s) == null) {
                return s;
            }
        }
        return -1;
    }

    function usedSlots() as Array<Number> {
        var out = [] as Array<Number>;
        for (var s = 1; s <= MAX_SLOTS; s++) {
            if (load(s) != null) {
                out.add(s);
            }
        }
        return out;
    }

    // Apply "Delete slot N" ticks made on the phone.
    function applyPhoneDeletes() as Void {
        for (var s = 1; s <= MAX_SLOTS; s++) {
            if (Settings.flag("slot" + s + "Delete")) {
                remove(s);
            }
        }
    }
}
