# Changelog

Versions of the Open NavG data field (private Connect IQ beta). Dates are when the version was built.

## 0.3.2-beta — 2026-11-07
- Route ready screen: the map download status is now two short lines (in 0.3.1 it ran off the round edge).
- Text that still does not fit (for example a very long route name) is cut with "..." inside the safe circle.
- The check mark after "Map ready" was removed: the Venu 2 system font has no such glyph.
- The finish flag shows after the last real turn (bends less than 40 m before the finish are not announced).
- The green off-route trail starts on the route where you left it, so it joins the route without a gap.
- Distances below 100 km always show one decimal, rounded down (10.56 km → "10.5 km").
- The route line turns grey exactly up to your position, blue ahead.
- Text outline (halo) is 2 px and follows the letter shapes, readable over map lines.
- Bigger rows in the route picker when there are few routes.
- North indicator also on the arrow-to-start screen.
- Arrived shows the distance actually covered (the activity's distance).
- New test that draws every screen and checks every text fits the round screen, in English and Indonesian.
- Store screenshots now use the real Venu 2 font (built from the local Connect IQ SDK by `docs/store/make_fonts.py`; the font data is not in the repo).

## 0.3.1-beta — 2026-11-06
- North indicator on the navigation screens (red half points north, letter N / U), turning with the heading-up map.
- Calmer compass while standing still: changes under 5° are ignored, up to 12° jump directly, bigger turns move half the way each second.
- Explore mode removed: off-route always gives one short vibration, and one when back on the route. The red dashed line back to the route is unchanged.

## 0.3.0-beta — 2026-11-06
- Light street map: the roads (thicker) and alleys (thin) around the route, downloaded once from the Valhalla server together with the route, then fully offline. Motorbike mode keeps roads only.
- Stored per route slot (80 KB for all maps), resumes after interruptions, erased with the route.
- Drawn heading-up under the route line; falls back to roads only if drawing is slow.
- Route ready screen shows the map download progress; phone settings explain the download time.
- OpenStreetMap (ODbL) attribution.

## 0.2.0-beta — 2026-11-06
- First version: next-turn arrow with a countdown bar, one vibration about 20 m before turns.
- Off-route guidance (40 m for 10 s; 50 m for motorbike) with a red dashed line to the rejoin point ahead on the route, green trail, back-on-route message.
- Arrival screen, 5 saved route slots, tap-to-choose route picker, English and Indonesian.
- Routes from Valhalla (destination; motorbike without toll roads), OSRM (via points) or offline route codes from the Planner.
- Planner web page (`docs/planner`): import GPX or draw points, preview, copy a route code.
