function OpenILS(){}

OpenILS.prototype = {

    help: function () { 
    	dump("Ah ha!  This xpcom isn't really 'xp'.  We make use of the .wrappedJSObject method to get a truly global place to stick data.\n"); 
    },

    data: {},

    wrappedJSObject: this,

    QueryInterface: function (iid) {
        if (!iid.equals(Components.interfaces.nsIOpenILS)
            && !iid.equals(Components.interfaces.nsISupports))
        {
            throw Components.results.NS_ERROR_NO_INTERFACE;
        }
        return this;
    }
}

var Module = {
    firstTime: true,

    registerSelf: function (compMgr, fileSpec, location, type) {
        if (this.firstTime) {
            dump("*** Deferring registration of OpenILS data cache\n");
            this.firstTime = false;
            throw Components.results.NS_ERROR_FACTORY_REGISTER_AGAIN;
        }
        debug("*** Registering OpenILS data cache\n");
        compMgr = compMgr.QueryInterface(Components.interfaces.nsIComponentRegistrar);
        compMgr.registerFactoryLocation(this.myCID,
                                        "OpenILS data cache",
                                        this.myProgID,
                                        fileSpec,
                                        location,
                                        type);
    },

    getClassObject : function (compMgr, cid, iid) {
        if (!cid.equals(this.myCID))
        throw Components.results.NS_ERROR_NO_INTERFACE
        if (!iid.equals(Components.interfaces.nsIFactory))
        throw Components.results.NS_ERROR_NOT_IMPLEMENTED;
        return this.myFactory;
    },

    myCID: Components.ID("{dc3e4b5f-c0f4-4b34-bc57-7b4099c3a5d6}"),
    myProgID: "@mozilla.org/openils_data_cache;1",

    myFactory: {
        createInstance: function (outer, iid) {
            dump("CI: " + iid + "\n");
            if (outer != null)
            throw Components.results.NS_ERROR_NO_AGGREGATION;
            return (new OpenILS()).QueryInterface(iid);
        }
    },

    canUnload: function(compMgr) {
        dump("****** Unloading: OpenILS data cache! ****** \n");
        return true;
    }
}; // END Module

function NSGetModule(compMgr, fileSpec) { return Module; }

