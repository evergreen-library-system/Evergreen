Components.utils.import("resource://gre/modules/XPCOMUtils.jsm");

// These components are intended to handle remote XUL requests

// FIRST, if we don't have bind, add a workaroundish thing.
// If we stop caring about firefox/xulrunner < 4 we can ditch this.
if (!Function.prototype.bind) {
  Function.prototype.bind = function (oThis) {
    if (typeof this !== "function") {
      // closest thing possible to the ECMAScript 5 internal IsCallable function
      throw new TypeError("Function.prototype.bind - what is trying to be bound is not callable");
    }
 
    var aArgs = Array.prototype.slice.call(arguments, 1),
        fToBind = this,
        fNOP = function () {},
        fBound = function () {
          return fToBind.apply(this instanceof fNOP && oThis
                                 ? this
                                 : oThis,
                               aArgs.concat(Array.prototype.slice.call(arguments)));
        };
 
    fNOP.prototype = this.prototype;
    fBound.prototype = new fNOP();
 
    return fBound;
  };
}

// First we define a channel wrapper.
// We need this to handle redirects properly.
// Things we care about:
// Intercepting the URI
// Intercepting things that get a channel in callbacks
//
// We define what we need for those.
// wrap_channel(_mode) handles all of the other fun we then have to worry about.

function oilsChannel() {
}

oilsChannel.prototype = {
    QueryInterface: XPCOMUtils.generateQI([
        Components.interfaces.nsIChannel,
        Components.interfaces.nsIHttpChannel,
        Components.interfaces.nsIHttpChannelInternal,
        Components.interfaces.nsIRequest,
        Components.interfaces.nsIInterfaceRequestor,
        Components.interfaces.nsIChannelEventSink,
        Components.interfaces.nsIProgressEventSink,
        Components.interfaces.nsIHttpEventSink,
        Components.interfaces.nsIStreamListener,
        Components.interfaces.nsIAuthPrompt2,
        Components.interfaces.nsIRequestObserver,
        Components.interfaces.nsIUploadChannel
    ]),
    _internal_channel: null,
    _internal_uri: null,
    _redirect_notificationCallbacks: null,
    _redirect_streamListener: null,
    wrap_channel: function(channel, uri) {
        this._internal_channel = channel;
        this._internal_uri = uri;
        this.wrap_channel_mode(channel.QueryInterface(Components.interfaces.nsIRequest)); // Basic request stuff
        this.wrap_channel_mode(channel.QueryInterface(Components.interfaces.nsIChannel)); // Basic channel stuff
        this.wrap_channel_mode(channel.QueryInterface(Components.interfaces.nsIHttpChannel)); // Basic HTTP stuff
        this.wrap_channel_mode(channel.QueryInterface(Components.interfaces.nsIHttpChannelInternal)); // To pretend we are internal-ish
        this.wrap_channel_mode(channel.QueryInterface(Components.interfaces.nsIUploadChannel)); // To make POST work
    },
    wrap_channel_mode: function(channel) {
        for( var item in channel ) {
            try {
                if(this[item] || typeof this[item] != 'undefined')
                    continue;
            } catch (E) { continue; }
            try {
                var isfunc = false;
                try {
                    isfunc = (/[Ff]unction/.test(typeof channel[item])) || typeof channel[item].bind != 'undefined';
                } catch (E) {}
                if(isfunc) {
                    try {
                        this[item] = (function(thisItem){ return channel[thisItem].bind(channel); })(item);
                    } catch (E) {}
                } else {
                    try {
                        this.__defineGetter__(item, (function(thisItem) { return function() { return channel[thisItem]; } })(item));
                    } catch (E) {}
                    try {
                        this.__defineSetter__(item, (function(thisItem) { return function(val) { return channel[thisItem] = val; } })(item));
                    } catch (E) {}
                }
            } catch (E) {}
        }
    },
    get notificationCallbacks() {
        // for a number of reasons we don't admit to re-writing these things here
        return this._redirect_notificationCallbacks;
    },
    set notificationCallbacks(val) {
        if (val) {
            this._internal_channel.notificationCallbacks = this.QueryInterface(Components.interfaces.nsIInterfaceRequestor);
            this._redirect_notificationCallbacks = val;
        } else {
            this._internal_channel.notificationCallbacks = null;
            this._redirect_notificationCallbacks = null;
        }
        this._internal_channel.notificationCallbacks = val;
    },
    get URI() {
        return this._internal_uri;
    },
    asyncOpen: function(aListener, aContext) {
        this._redirect_streamListener = aListener;
        this._internal_channel.asyncOpen(this.QueryInterface(Components.interfaces.nsIStreamListener), aContext);
    },
    open: function() {
        return this._internal_channel.open();
    },
    getInterface: function(aIID) {
        try {
            if (this.QueryInterface(aIID) && this._redirect_notificationCallbacks.getInterface(aIID)) {
                return this.QueryInterface(aIID);
            }
        } catch(e) {}
        // Pass onto the forwarding target as a last resort.
        return this._redirect_notificationCallbacks.getInterface(aIID);
    },
    onChannelRedirect: function(oldChannel, newChannel, flags) {
        var redirect = this._redirect_notificationCallbacks.getInterface(Components.interfaces.nsIChannelEventSink);
        return redirect.onChannelRedirect(this.QueryInterface(Components.interfaces.nsIChannel), newChannel, flags);
    },
    asyncOnChannelRedirect: function(oldChannel, newChannel, flags, callback) {
        var redirect = this._redirect_notificationCallbacks.getInterface(Components.interfaces.nsIChannelEventSink);
        return redirect.asyncOnChannelRedirect(this.QueryInterface(Components.interfaces.nsIChannel), newChannel, flags, callback);
    },
    onProgress: function(aRequest, aContext, aProgress, aProgressMax) {
        var redirect = this._redirect_notificationCallbacks.getInterface(Components.interfaces.nsIProgressEventSink);
        return redirect.onProgress(this.QueryInterface(Components.interfaces.nsIRequest), aContext, aProgress, aProgressMax);
    },
    onStatus: function(aRequest, aContext, aStatus, aStatusArg) {
        var redirect = this._redirect_notificationCallbacks.getInterface(Components.interfaces.nsIProgressEventSink);
        return redirect.onStatus(this.QueryInterface(Components.interfaces.nsIRequest), aContext, aStatus, aStatusArg);
    },
    onRedirect: function(httpChannel, newChannel) {
        var redirect = this._redirect_notificationCallbacks.getInterface(Components.interfaces.nsIHttpEventSink);
        return redirect.onRedirect(this.QueryInterface(Components.interfaces.nsIHttpChannel), newChannel);
    },
    asyncPromptAuth: function(aChannel, aCallback, aContext, level, authInfo) {
        var redirect = this._redirect_notificationCallbacks.getInterface(Components.interfaces.nsIAuthPrompt2);
        return redirect.asyncPromptAuth(this.QueryInterface(Components.interfaces.nsIChannel), aCallback, aContext, level, authInfo);
    },
    promptAuth: function(aChannel, level, authInfo) {
        var redirect = this._redirect_notificationCallbacks.getInterface(Components.interfaces.nsIAuthPrompt2);
        return redirect.promptAuth(this.QueryInterface(Components.interfaces.nsIChannel), level, authInfo);
    },
    onStartRequest: function(aRequest, aContext) {
        if ( aRequest == this._internal_channel )
            this._redirect_streamListener.onStartRequest(this.QueryInterface(Components.interfaces.nsIRequest), aContext);
        else
            this._redirect_streamListener.onStartRequest(aRequest, aContext);
    },
    onStopRequest: function(aRequest, aContext, aStatusCode) {
        if ( aRequest == this._internal_channel )
            this._redirect_streamListener.onStopRequest(this.QueryInterface(Components.interfaces.nsIRequest), aContext, aStatusCode);
        else
            this._redirect_streamListener.onStopRequest(aRequest, aContext, aStatusCode);
    },
    onDataAvailable: function(aRequest, aContext, aInputStream, aOffset, aCount) {
        if ( aRequest == this._internal_channel )
            this._redirect_streamListener.onDataAvailable(this.QueryInterface(Components.interfaces.nsIRequest), aContext, aInputStream, aOffset, aCount);
        else
            this._redirect_streamListener.onDataAvailable(aRequest, aContext, aInputStream, aOffset, aCount);
    },
}

// This handles the actual security-related elements of the protocol wrapper

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
        var data_cache = Components.classes["@open-ils.org/openils_data_cache;1"].getService().wrappedJSObject.data;
        switch(aURI.host) {
            case 'remote':
                host = data_cache.server_unadorned;
                break;
            case 'selfcheck':
                // To allow elevated permissions on a specific host for selfcheck purposes change this from null.
                // This is intended for installing an extension on Firefox specifically for selfcheck purposes
                // NOTE: I honestly don't know how dangerous this might be, but I can't imagine it is worse than the previous "grant the domain permissions to do anything" model.
                host = null;
                break;
        }
        if(!host)
            return ios.newChannel("about:blank", null, null); // Bad input. Not really sure what to do. Returning a dummy channel does prevent a crash, though!
        var chunk = aURI.spec.replace(/^oils:\/\/[^\/]*\//,'');
        var channel = ios.newChannel("https://" + host + "/" + chunk, null, null).QueryInterface(Components.interfaces.nsIHttpChannel);
        channel.setRequestHeader("OILS-Wrapper", "true", false);
        // If we have a search/pref lib, set them too!
        if (data_cache.search_lib && data_cache.search_lib != null)
            channel.setRequestHeader("OILS-Search-Lib", data_cache.search_lib, false);
        if (data_cache.pref_lib && data_cache.pref_lib != null)
            channel.setRequestHeader("OILS-Pref-Lib", data_cache.pref_lib, false);
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
        // This is a workaround.
        // We can't wrap all the time because XMLHttpRequests are busted by us doing so.
        // If we don't wrap, redirects in the Template Toolkit OPAC break out of the protocol.
        // So wrap only if we are in the catalog!
        if (aURI.path.match(/^\/eg\/[ok]pac/)) {
            var outChannel = new oilsChannel();
            outChannel.wrap_channel(channel, aURI);
            return outChannel;
        }
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
