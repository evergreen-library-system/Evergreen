Components.utils.import("resource://gre/modules/XPCOMUtils.jsm");

// This content policy component tries to prevent outside sites from getting xulG hooks
// It does so by forcing them to open outside of Evergreen

function oilsForceExternal() {}
oilsForceExternal.prototype = {
    classDescription: "OpenILS Force External",
    classID:          Components.ID("{D969ED61-DF4C-FA12-A2A6-70AA94C222FB}"),
    contractID:       "@mozilla.org/content-policy;1?type=egfe",
    _xpcom_categories: [{
        category: "content-policy",
        entry: "m-egfe"
    }],
    QueryInterface:   XPCOMUtils.generateQI([Components.interfaces.nsIContentPolicy]),
    shouldLoad: function(contentType, contentLocation, requestOrigin, node, mimeTypeGuess, extra)
    {
        if ((contentType == Components.interfaces.nsIContentPolicy.TYPE_DOCUMENT || contentType == Components.interfaces.nsIContentPolicy.TYPE_SUBDOCUMENT)
          && (contentLocation.scheme == 'http' || contentLocation.scheme == 'https')
          && node && node.getAttribute('oils_force_external') == 'true') {
            var data_cache = Components.classes["@open-ils.org/openils_data_cache;1"].getService().wrappedJSObject.data;
            var host = data_cache.server_unadorned;
            if(host && contentLocation.host != host) {
                // first construct an nsIURI object using the ioservice
                var ioservice = Components.classes["@mozilla.org/network/io-service;1"]
                                .getService(Components.interfaces.nsIIOService);

                var uriToOpen = ioservice.newURI(contentLocation.spec, null, null);

                var extps = Components.classes["@mozilla.org/uriloader/external-protocol-service;1"]
                            .getService(Components.interfaces.nsIExternalProtocolService);

                // now, open it!
                extps.loadURI(uriToOpen, null);

                return Components.interfaces.nsIContentPolicy.REJECT_REQUEST;
            }
        }
        return Components.interfaces.nsIContentPolicy.ACCEPT;
    },

    shouldProcess: function(contentType, contentLocation, requestOrigin, insecNode, mimeType, extra)
    {
        return Components.interfaces.nsIContentPolicy.ACCEPT;
    },
};

if (XPCOMUtils.generateNSGetFactory)
    var NSGetFactory = XPCOMUtils.generateNSGetFactory([oilsForceExternal]);
else
    var NSGetModule = XPCOMUtils.generateNSGetModule([oilsForceExternal]);

