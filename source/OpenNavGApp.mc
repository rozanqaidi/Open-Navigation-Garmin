import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class OpenNavGApp extends Application.AppBase {
    hidden var _view as OpenNavGView?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new OpenNavGView();
        _view = view;
        return [view, new OpenNavGDelegate(view)];
    }

    // Called when the phone saves new settings.
    function onSettingsChanged() as Void {
        var v = _view;
        if (v != null) {
            v.settingsChanged();
        }
        WatchUi.requestUpdate();
    }
}

// Taps on the data field (Venu 2 touchscreen): open the route picker, choose, retry.
class OpenNavGDelegate extends WatchUi.InputDelegate {
    hidden var _view as OpenNavGView;

    function initialize(view as OpenNavGView) {
        InputDelegate.initialize();
        _view = view;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var c = evt.getCoordinates();
        return _view.handleTap(c[0], c[1]);
    }
}
