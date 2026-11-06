import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Test;

// Scenario tests for NavState and the view. Compiled only with --test.
(:test)
module NavStateTest {
    // Base point near Monas, Jakarta (radians).
    const LAT0 = -0.10778;
    const LON0 = 1.86450;
    const M = 1.0 / 6371000.0; // one metre of latitude, in radians

    function north(m as Numeric) as Float {
        return (LAT0 + m * M).toFloat();
    }

    // Longitude offset in metres at LAT0.
    function east(m as Numeric) as Float {
        return (LON0 + m * M / Math.cos(LAT0)).toFloat();
    }

    function near(a as Numeric, b as Numeric, tol as Numeric) as Boolean {
        return (a - b).abs() <= tol;
    }

    (:test)
    function firstFixBecomesStart(logger as Logger) as Boolean {
        var s = new NavState();
        s.update(LAT0, LON0, 0, null, null, null);
        return s.hasFix && s.hasStart() && s.distanceToStart() < 0.5 && s.arrived();
    }

    (:test)
    function activityStartOverridesFirstFix(logger as Logger) as Boolean {
        var s = new NavState();
        s.update(north(50), LON0, 0, null, null, null);
        s.update(north(50), LON0, 0, null, LAT0, LON0);
        logger.debug("d=" + s.distanceToStart());
        return near(s.distanceToStart(), 50, 1) && !s.arrived();
    }

    (:test)
    function runningNorthStartIsBehind(logger as Logger) as Boolean {
        var s = new NavState();
        for (var m = 0; m <= 100; m += 5) {
            s.update(north(m), LON0, 3.0, null, null, null);
        }
        var rel = s.relativeBearingToStart();
        logger.debug("heading=" + s.heading + " rel=" + rel);
        return near(s.heading, 0, 0.02) && near(rel.abs(), Math.PI, 0.02)
            && near(s.distanceToStart(), 100, 1);
    }

    (:test)
    function turnEastStartIsBackLeft(logger as Logger) as Boolean {
        var s = new NavState();
        for (var m = 0; m <= 100; m += 5) {
            s.update(north(m), LON0, 3.0, null, null, null);
        }
        for (var m = 5; m <= 100; m += 5) {
            s.update(north(100), east(m), 3.0, null, null, null);
        }
        var rel = s.relativeBearingToStart();
        logger.debug("heading=" + s.heading + " rel=" + rel);
        // Facing east, start is south-west => 135 deg to the right-behind (clockwise +).
        return near(s.heading, Math.PI / 2, 0.02) && near(rel, 3 * Math.PI / 4, 0.03);
    }

    (:test)
    function slowUsesCompass(logger as Logger) as Boolean {
        var s = new NavState();
        s.update(LAT0, LON0, 0.3, 1.0, null, null);
        return near(s.heading, 1.0, 0.0001);
    }

    (:test)
    function compassWobbleIsIgnored(logger as Logger) as Boolean {
        // Standing still, hand shaking ±3°: map must not move.
        var s = new NavState();
        s.update(LAT0, LON0, 0.0, 1.0, null, null);
        var ok = true;
        var w = [0.05, -0.05, 0.03, -0.04];
        for (var i = 0; i < w.size(); i++) {
            s.update(LAT0, LON0, 0.0, 1.0 + w[i], null, null);
            ok = ok && near(s.heading, 1.0, 0.0001);
        }
        return ok;
    }

    (:test)
    function compassTurnIsSpreadOut(logger as Logger) as Boolean {
        // Turning on the spot by 90°: small steps, then exactly on target.
        var s = new NavState();
        s.update(LAT0, LON0, 0.0, 0.0, null, null);
        var target = Math.PI / 2;
        var steps = [] as Array<Float>;
        for (var i = 0; i < 6; i++) {
            s.update(LAT0, LON0, 0.0, target, null, null);
            steps.add(s.heading);
        }
        logger.debug("steps=" + steps);
        var firstStepHalf = near(steps[0], target / 2, 0.01);
        var landed = near(steps[3], target, 0.0001) && near(steps[5], target, 0.0001);
        return firstStepHalf && landed;
    }

    (:test)
    function compassCrossesNorth(logger as Logger) as Boolean {
        // 350° -> 20°: must turn the short way (+30°), not back round 330°.
        var s = new NavState();
        var d = Math.PI / 180;
        s.update(LAT0, LON0, 0.0, 350 * d, null, null);
        s.update(LAT0, LON0, 0.0, 20 * d, null, null);
        var h = Geo.wrap(s.heading) / d;
        logger.debug("h=" + h);
        return near(h, 5, 0.5);
    }

    (:test)
    function fastIgnoresCompassWobble(logger as Logger) as Boolean {
        // Arm swinging: compass says 2.5 rad, but we run north.
        var s = new NavState();
        for (var m = 0; m <= 40; m += 5) {
            s.update(north(m), LON0, 3.0, 2.5, null, null);
        }
        return near(s.heading, 0, 0.02);
    }

    (:test)
    function gpsJitterKeepsHeading(logger as Logger) as Boolean {
        var s = new NavState();
        for (var m = 0; m <= 40; m += 5) {
            s.update(north(m), LON0, 3.0, null, null, null);
        }
        // 2 m sideways noise must not swing the arrow.
        s.update(north(40), east(2), 3.0, null, null, null);
        return near(s.heading, 0, 0.02);
    }

    (:test)
    function lostFixThenRecover(logger as Logger) as Boolean {
        var s = new NavState();
        s.update(LAT0, LON0, 0, null, null, null);
        s.lostFix();
        var lost = !s.hasFix;
        s.update(north(30), LON0, 2.0, null, null, null);
        return lost && s.hasFix && near(s.distanceToStart(), 30, 1);
    }

    (:test)
    function twoHourRunNoMemoryGrowth(logger as Logger) as Boolean {
        var s = new NavState();
        s.update(LAT0, LON0, 0, null, null, null);
        var before = System.getSystemStats().usedMemory;
        for (var t = 0; t < 7200; t++) {
            var a = t * 0.002;
            s.update(north(500 * Math.sin(a)), east(500 * Math.cos(a)), 3.0, null, null, null);
        }
        var after = System.getSystemStats().usedMemory;
        logger.debug("used before=" + before + " after=" + after
            + " total=" + System.getSystemStats().totalMemory);
        return (after - before) < 2048;
    }

    // Draw every screen into an off-screen 416x416 bitmap: must not crash.
    (:test)
    function renderAllScreens(logger as Logger) as Boolean {
        var ref = Graphics.createBufferedBitmap({:width => 416, :height => 416});
        var dc = ref.get().getDc();
        var v = new OpenNavGView();

        v.onUpdate(dc); // no fix yet

        v.state.update(LAT0, LON0, 0, null, null, null);
        v.onUpdate(dc); // arrived (dot)

        for (var m = 0; m <= 1500; m += 5) {
            v.state.update(north(m), LON0, 3.0, null, null, null);
        }
        v.onUpdate(dc); // arrow + km

        v.state.lostFix();
        v.onUpdate(dc); // searching again

        logger.debug("render ok, used=" + System.getSystemStats().usedMemory);
        return true;
    }
}
