import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;

// Phone settings → route code → staged processing → saved slot → navigation ready.
(:test)
module PipelineTest {
    const CODE = "NAVG1L:_p~iF~ps|U_ulLnnqC_mqNvxq`@";

    function reset() as Void {
        for (var s = 1; s <= RouteStore.MAX_SLOTS; s++) {
            Application.Storage.deleteValue(RouteStore.key(s));
            Settings.set("slot" + s + "Name", "");
            Settings.set("slot" + s + "Delete", false);
        }
        Settings.set("activeSlot", 0);
        Settings.set("destination", "");
        Settings.set("routeName", "");
    }

    (:test)
    function lineCodeBecomesSavedRoute(logger as Logger) as Boolean {
        reset();
        Settings.set("destination", CODE);
        Settings.set("routeName", "CFD Komunitas");
        var v = new OpenNavGView();
        var phase = v.testPipeline(50);
        var name = v.testRouteName();
        logger.debug("phase=" + phase + " name=" + name + " active=" + Settings.get("activeSlot", -1)
            + " slot1=" + Settings.str("slot1Name") + " dest='" + Settings.str("destination") + "'");
        var ok = phase == v.PH_ROUTE && "CFD Komunitas".equals(name)
            && Settings.get("activeSlot", 0) == 1 && "CFD Komunitas".equals(Settings.str("slot1Name"))
            && Settings.str("destination").length() == 0;
        // A new watch session now loads slot 1 without any code.
        var v2 = new OpenNavGView();
        ok = ok && v2.testPipeline(50) == v2.PH_ROUTE && "CFD Komunitas".equals(v2.testRouteName());
        reset();
        return ok;
    }

    (:test)
    function missingNameIsAnError(logger as Logger) as Boolean {
        reset();
        Settings.set("destination", CODE);
        var v = new OpenNavGView();
        var ok = v.testPipeline(50) == v.PH_ERROR;
        reset();
        return ok;
    }

    (:test)
    function fullSlotsAskToDelete(logger as Logger) as Boolean {
        reset();
        var pts = RouteCode.points(CODE) as Array<Float>;
        for (var s = 1; s <= RouteStore.MAX_SLOTS; s++) {
            RouteStore.save(s, "R" + s, pts, 0);
        }
        Settings.set("destination", CODE);
        Settings.set("routeName", "Baru");
        var v = new OpenNavGView();
        var full = v.testPipeline(50) == v.PH_ERROR;
        // Tick "delete slot 3" on the phone → next session saves into slot 3.
        Settings.set("slot3Delete", true);
        var v2 = new OpenNavGView();
        var saved = v2.testPipeline(50) == v2.PH_ROUTE && Settings.get("activeSlot", 0) == 3;
        logger.debug("full=" + full + " savedInSlot3=" + saved);
        reset();
        return full && saved;
    }

    (:test)
    function badDestinationIsAnError(logger as Logger) as Boolean {
        reset();
        Settings.set("destination", "hotel dekat pantai");
        Settings.set("routeName", "x");
        var v = new OpenNavGView();
        var ok = v.testPipeline(50) == v.PH_ERROR;
        reset();
        return ok;
    }
}
