Components.utils.import("resource://gre/modules/XPCOMUtils.jsm");

// This component is intended to handle remote XUL requests

function oilsProtocol() {}

oilsProtocol.prototype = {
    _system_principal: null,
    scheme: "oils",
    protocolflags: Components.interfaces.nsIProtocolHandler.URI_DANGEROUS_TO_LOAD |
                   Components.interfaces.nsIProtocolHandler.URI_INHERITS_SECURITY_CONTEXT,
    newURI: function(aSpec, aOriginCharset, aBaseURI) {
        var new_url = Components.classes["@mozilla.org/network/standard-url;1"].createInstance(Components.interfaces.nsIStandardURL);
        new_url.init(1, -1, aSpec, aOriginCharset, aBaseURI);
        return new_url.QueryInterface(Components.interfaces.nsIURI);
    },
    newChannel: function(aURI) {
        var ios = Components.classes["@mozilla.org/network/io-service;1"].getService(Components.interfaces.nsIIOService);
        var host;
        switch(aURI.spec.replace(/^oils:\/\/([^\/]*)\/.*$/,'$1')) {
            case 'remote':
                var data_cache = Components.classes["@open-ils.org/openils_data_cache;1"].getService().wrappedJSObject.data;
                host = data_cache.server_unadorned;
                break;
            case 'selfcheck':
                // To allow elevated permissions on a specific host for selfcheck purposes change this from null.
                // This is intended for installing an extension on Firefox specifically for selfcheck purposes
                // NOTE: I honestly don't know how dangerous this might be, but I can't imagine it is worse than the previous "grant the domain permissions to do anything" model.
                host = null;
                break;
            default:
                return null; // Bad input. Not really sure what to do.
                break;
        }
        if(!host) return null; // Not really sure what to do when we don't have the data we need. Unless manual entry is happening, though, shouldn't be an issue.
        var chunk = aURI.spec.replace(/^oils:\/\/[^\/]*\//,'');
        var channel = ios.newChannel("https://" + host + "/" + chunk, null, null).QueryInterface(Components.interfaces.nsIHttpChannel);
        channel.setRequestHeader("OILS-Wrapper", "true", false);
        if(this._system_principal == null) {
            // We don't have the owner?
            var chrome_service = Components.classesByID['{61ba33c0-3031-11d3-8cd0-0060b0fc14a3}'].getService().QueryInterface(Components.interfaces.nsIProtocolHandler);
            var chrome_uri = chrome_service.newURI("chrome://open_ils_staff_client/content/main/main.xul", null, null);
            var chrome_channel = chrome_service.newChannel(chrome_uri);
            this._system_principal = chrome_channel.owner;
            var chrome_request = chrome_channel.QueryInterface(Components.interfaces.nsIRequest);
            chrome_request.cancel(0x804b0002);
        }
        if (this._system_principal) channel.owner = this._system_principal;
        return channel;
    },
    allowPort: function(aPort, aScheme) {
        return false;
    },
    classDescription: "OILS Protocol Handler",
    contractID: "@mozilla.org/network/protocol;1?name=oils",
    classID: Components.ID('{51d35450-5e59-11e1-b86c-0800200c9a66}'),
    QueryInterface: XPCOMUtils.generateQI([Components.interfaces.nsIProtocolHandler]),
}

if (XPCOMUtils.generateNSGetFactory)
    var NSGetFactory = XPCOMUtils.generateNSGetFactory([oilsProtocol]);
else
    var NSGetModule = XPCOMUtils.generateNSGetModule([oilsProtocol]);

