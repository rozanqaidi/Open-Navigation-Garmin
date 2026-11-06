import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Every visual is drawn from code: no bitmaps on the watch.
// Icons are defined in a 24 x 28 box and scaled by k.
module Draw {
    const BLUE = 0x3AA0FF;
    const GREY = 0x444444;
    const YELLOW = 0xF5C542;
    const RED = 0xFF6B5E;
    const GREEN = 0x2ECC71;
    const BAR_BG = 0x333333;
    const FONTS_DOWN = [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL,
                        Graphics.FONT_TINY, Graphics.FONT_XTINY];
    const FONTS_UP = [Graphics.FONT_XTINY, Graphics.FONT_TINY, Graphics.FONT_SMALL,
                      Graphics.FONT_MEDIUM, Graphics.FONT_LARGE];

    // ---------- text ----------

    // Text with a thin black outline that follows the glyphs (≈8% of the font size).
    function haloText(dc as Dc, x as Numeric, y as Numeric, font as Graphics.FontType,
                      text as String, color as Number, justify as Number) as Void {
        var o = (Graphics.getFontHeight(font) * 0.04).toNumber();
        if (o < 1) {
            o = 1;
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        for (var dx = -o; dx <= o; dx += o) {
            for (var dy = -o; dy <= o; dy += o) {
                if (dx != 0 || dy != 0) {
                    dc.drawText(x + dx, y + dy, font, text, justify);
                }
            }
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, justify);
    }

    // Largest font, at most `want`, whose text fits inside the 90% safe circle at row y.
    function fitFont(dc as Dc, text as String, y as Numeric, want as Graphics.FontType) as Graphics.FontType {
        var fonts = FONTS_DOWN;
        var r = dc.getWidth() / 2.0 * 0.90;
        var dy = y - dc.getHeight() / 2.0;
        var chord = (dy.abs() >= r) ? 0 : 2 * Math.sqrt(r * r - dy * dy);
        var started = false;
        for (var i = 0; i < fonts.size(); i++) {
            if (fonts[i] == want) {
                started = true;
            }
            if (started && dc.getTextWidthInPixels(text, fonts[i]) <= chord) {
                return fonts[i];
            }
        }
        return Graphics.FONT_XTINY;
    }

    // Font whose height is closest to (but not much above) px.
    function fontForHeight(px as Numeric) as Graphics.FontType {
        var fonts = FONTS_UP;
        var best = fonts[0];
        for (var i = 0; i < fonts.size(); i++) {
            if (Graphics.getFontHeight(fonts[i]) <= px * 1.15) {
                best = fonts[i];
            }
        }
        return best;
    }

    // Centred text that always fits the round screen.
    function line(dc as Dc, y as Numeric, text as String, want as Graphics.FontType, color as Number) as Void {
        var f = fitFont(dc, text, y, want);
        haloText(dc, dc.getWidth() / 2, y, f, text, color,
                 Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ---------- shapes ----------

    function scaled(pts as Array, x as Numeric, y as Numeric, k as Numeric, mirror as Boolean) as Array<[Numeric, Numeric]> {
        var out = new Array<[Numeric, Numeric]>[pts.size()];
        for (var i = 0; i < pts.size(); i++) {
            var px = pts[i][0];
            out[i] = [x + (mirror ? 24 - px : px) * k, y + pts[i][1] * k];
        }
        return out;
    }

    function polyline(dc as Dc, pts as Array<[Numeric, Numeric]>, width as Numeric) as Void {
        dc.setPenWidth(width);
        for (var i = 1; i < pts.size(); i++) {
            dc.drawLine(pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1]);
        }
        // round joints / caps
        for (var i = 0; i < pts.size(); i++) {
            dc.fillCircle(pts[i][0], pts[i][1], width / 2);
        }
    }

    function grow(poly as Array<[Numeric, Numeric]>, f as Float) as Array<[Numeric, Numeric]> {
        var cx = 0.0;
        var cy = 0.0;
        for (var i = 0; i < poly.size(); i++) {
            cx += poly[i][0];
            cy += poly[i][1];
        }
        cx /= poly.size();
        cy /= poly.size();
        var out = new Array<[Numeric, Numeric]>[poly.size()];
        for (var i = 0; i < poly.size(); i++) {
            out[i] = [cx + (poly[i][0] - cx) * f, cy + (poly[i][1] - cy) * f];
        }
        return out;
    }

    // Stem + head icon with a black outline.
    function strokeIcon(dc as Dc, stem as Array, head as Array, x as Numeric, y as Numeric,
                        k as Numeric, mirror as Boolean, color as Number) as Void {
        var s = scaled(stem, x, y, k, mirror);
        var h = scaled(head, x, y, k, mirror);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        polyline(dc, s, 7.5 * k);
        dc.fillPolygon(grow(h, 1.3));
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        polyline(dc, s, 5 * k);
        dc.fillPolygon(h);
    }

    const STEM_TURN = [[5, 27], [5, 14], [6, 10.5], [8.5, 8], [12, 7], [15, 7]];
    const HEAD_TURN = [[14, 0], [24, 7], [14, 14]];
    const STEM_STRAIGHT = [[12, 27], [12, 10]];
    const HEAD_STRAIGHT = [[12, 0], [20, 11], [4, 11]];
    const STEM_UTURN = [[19, 27], [19, 12], [18, 8], [15, 5.5], [12, 5], [9, 5.5], [6, 8], [5, 12], [5, 16]];
    const HEAD_UTURN = [[0, 15], [10, 15], [5, 24]];

    // Header icon for a Route turn type, top-left at (x, y), box 24k × 28k.
    function turnIcon(dc as Dc, type as Number, x as Numeric, y as Numeric, k as Numeric) as Void {
        if (type == 1) {          // LEFT
            strokeIcon(dc, STEM_TURN, HEAD_TURN, x, y, k, true, Graphics.COLOR_WHITE);
        } else if (type == 2) {   // RIGHT
            strokeIcon(dc, STEM_TURN, HEAD_TURN, x, y, k, false, Graphics.COLOR_WHITE);
        } else if (type == 3) {   // UTURN
            strokeIcon(dc, STEM_UTURN, HEAD_UTURN, x, y, k, false, Graphics.COLOR_WHITE);
        } else if (type == 4) {   // FINISH
            pin(dc, x + 12 * k, y + 10 * k, k);
        } else {                  // STRAIGHT
            strokeIcon(dc, STEM_STRAIGHT, HEAD_STRAIGHT, x, y, k, false, Graphics.COLOR_WHITE);
        }
    }

    // Red "go back" hook for off-route (same family as the turn icons).
    function returnIcon(dc as Dc, x as Numeric, y as Numeric, k as Numeric) as Void {
        strokeIcon(dc, [[19, 27], [19, 14], [18, 10.5], [15.5, 8], [12, 7], [9, 7]],
                   [[10, 0], [0, 7], [10, 14]], x, y, k, false, RED);
    }

    // Green location pin centred at (cx, cy) of its round head.
    function pin(dc as Dc, cx as Numeric, cy as Numeric, k as Numeric) as Void {
        var tri = [[cx - 9 * k, cy + 5 * k], [cx + 9 * k, cy + 5 * k], [cx, cy + 18 * k]];
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, 10 * k + 2);
        dc.fillPolygon(grow(tri, 1.2));
        dc.setColor(GREEN, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, 10 * k);
        dc.fillPolygon(tri);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, 3.5 * k);
    }

    function check(dc as Dc, x as Numeric, y as Numeric, k as Numeric, color as Number) as Void {
        var p = scaled([[0, 9], [5, 14], [14, 2]], x, y, k, false);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        polyline(dc, p, 4 * k);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        polyline(dc, p, 2.5 * k);
    }

    // Small compass = explore mode is on.
    function compass(dc as Dc, cx as Numeric, cy as Numeric, k as Numeric) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, 10 * k);
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1.5 * k);
        dc.drawCircle(cx, cy, 9 * k);
        dc.setColor(0xCCCCCC, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, cy - 6 * k], [cx + 3.5 * k, cy + 3 * k], [cx, cy + 1 * k], [cx - 3.5 * k, cy + 3 * k]]);
    }

    // "You are here" chevron pointing up, tip at (cx, tipY).
    function youAreHere(dc as Dc, cx as Numeric, tipY as Numeric, k as Numeric) as Void {
        var p = [[cx, tipY], [cx - 12 * k, tipY + 19 * k], [cx, tipY + 12 * k], [cx + 12 * k, tipY + 19 * k]];
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(grow(p, 1.12));
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(p);
    }

    // Navigation arrow centred on (cx, cy), pointing at `angle` (0 = up, clockwise).
    function arrow(dc as Dc, cx as Numeric, cy as Numeric, size as Numeric, angle as Numeric) as Void {
        var shape = [[0.0, -1.0], [0.62, 0.62], [0.0, 0.28], [-0.62, 0.62]];
        var s = Math.sin(angle);
        var c = Math.cos(angle);
        var out = new Array<[Numeric, Numeric]>[shape.size()];
        for (var i = 0; i < shape.size(); i++) {
            var x = shape[i][0] * size;
            var y = shape[i][1] * size;
            out[i] = [cx + x * c - y * s, cy + x * s + y * c];
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(grow(out, 1.08));
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(out);
    }

    // Dashed line from (x1,y1) to (x2,y2).
    function dashed(dc as Dc, x1 as Numeric, y1 as Numeric, x2 as Numeric, y2 as Numeric,
                    dash as Numeric, gap as Numeric) as Void {
        var dx = x2 - x1;
        var dy = y2 - y1;
        var len = Math.sqrt(dx * dx + dy * dy);
        if (len < 1) {
            return;
        }
        var ux = dx / len;
        var uy = dy / len;
        var t = 0.0;
        while (t < len) {
            var e = (t + dash > len) ? len : t + dash;
            dc.drawLine(x1 + ux * t, y1 + uy * t, x1 + ux * e, y1 + uy * e);
            t += dash + gap;
        }
    }

    // Yellow countdown bar (fills left → right; full = turn now).
    function bar(dc as Dc, x as Numeric, y as Numeric, w as Numeric, h as Numeric, f as Float) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - 2, y - 2, w + 4, h + 4, (h + 4) / 2);
        dc.setColor(BAR_BG, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, h / 2);
        if (f > 0) {
            var fw = w * f;
            if (fw < h) {
                fw = h;
            }
            dc.setColor(YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, y, fw, h, h / 2);
        }
    }
}
