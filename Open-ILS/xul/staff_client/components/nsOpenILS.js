Components.utils.import("resource://gre/modules/XPCOMUtils.jsm");

// This entire component is a singleton that exists solely to store data.

function nsOpenILS() {
    this.wrappedJSObject = this;
}

nsOpenILS.prototype = {
    classDescription: "OpenILS Data Cache",
    classID:          Components.ID("{dc3e4b5f-c0f4-4b34-bc57-7b4099c3a5d6}"),
    contractID:       "@open-ils.org/openils_data_cache;1",
    QueryInterface:   XPCOMUtils.generateQI(),
    _xpcom_factory:   {
        singleton: null,
        createInstance: function (aOuter, aIID) {
            if (aOuter != null)
                throw Components.results.NS_ERROR_NO_AGGREGATION;
            if (this.singleton == null)
                this.singleton = new nsOpenILS();
            return this.singleton.QueryInterface(aIID);
        },
        getService: function (aIID) {
            if (aOuter != null)
                throw Components.results.NS_ERROR_NO_AGGREGATION;
            if (this.singleton == null)
                this.singleton = new nsOpenILS();
            return this.singleton.QueryInterface(aIID);
        }
    },
    data: {},
    openMainEGWindow: function() {
        var wm = Components.classes["@mozilla.org/appshell/window-mediator;1"]
                 .getService(Components.interfaces.nsIWindowMediator);
        var targetWindow = wm.getMostRecentWindow("eg_main");
        if (targetWindow != null) {
            targetWindow.focus();
        } else {
            var ww = Components.classes["@mozilla.org/embedcomp/window-watcher;1"]
                     .getService(Components.interfaces.nsIWindowWatcher);
            ww.openWindow(null, "chrome://open_ils_staff_client/content/main/main.xul", "_blank", "chrome,resizable,dialog=no", null);
        }
    },
};

if (XPCOMUtils.generateNSGetFactory)
    var NSGetFactory = XPCOMUtils.generateNSGetFactory([nsOpenILS]);
else
    var NSGetModule = XPCOMUtils.generateNSGetModule([nsOpenILS]);
