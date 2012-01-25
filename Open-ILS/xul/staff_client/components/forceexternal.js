const nsISupports           = Components.interfaces.nsISupports;
const nsICategoryManager    = Components.interfaces.nsICategoryManager;
const nsIComponentRegistrar = Components.interfaces.nsIComponentRegistrar;
const nsIContentPolicy      = Components.interfaces.nsIContentPolicy;
const nsIFactory            = Components.interfaces.nsIFactory;
const nsIModule             = Components.interfaces.nsIModule;
const nsIWindowWatcher      = Components.interfaces.nsIWindowWatcher;

const WINDOW_MAIN = "eg_main"

const fe_contractID = "@mozilla.org/content-policy;1?type=egfe";
const fe_CID = Components.ID("{D969ED61-DF4C-FA12-A2A6-70AA94C222FB}");
// category names are sorted alphabetically. Typical command-line handlers use a
// category that begins with the letter "m".
const fe_category = "m-egfe";

const myAppHandler = {

   shouldLoad: function(contentType, contentLocation, requestOrigin, node, mimeTypeGuess, extra)
   {
      if (contentType == nsIContentPolicy.TYPE_DOCUMENT) {
          var wm = Components.classes["@mozilla.org/appshell/window-mediator;1"].
            getService(Components.interfaces.nsIWindowMediator);
          var targetWindow = wm.getMostRecentWindow("eg_main");
          if (targetWindow != null) {
            var host = targetWindow.G.data.server_unadorned;
            if(host && (contentLocation.scheme == 'http' || contentLocation.scheme == 'https') && contentLocation.host != host) {
                // first construct an nsIURI object using the ioservice
                var ioservice = Components.classes["@mozilla.org/network/io-service;1"]
                                .getService(Components.interfaces.nsIIOService);

                var uriToOpen = ioservice.newURI(contentLocation.spec, null, null);

                var extps = Components.classes["@mozilla.org/uriloader/external-protocol-service;1"]
                                .getService(Components.interfaces.nsIExternalProtocolService);

                // now, open it!
                extps.loadURI(uriToOpen, null);

                return nsIContentPolicy.REJECT_REQUEST;
            }
          }
      }
      return nsIContentPolicy.ACCEPT;
   },

   shouldProcess: function(contentType, contentLocation, requestOrigin, insecNode, mimeType, extra)
   {
      return nsIContentPolicy.ACCEPT;
   },

  /* nsISupports */
  QueryInterface : function fe_QI(iid)
  {
    if (iid.equals(nsIContentPolicy) ||
        iid.equals(nsIFactory) ||
        iid.equals(nsISupports))
      return this;

    throw Components.results.NS_ERROR_NO_INTERFACE;
  },

  /* nsIFactory */

  createInstance : function fe_CI(outer, iid)
  {
    if (outer != null)
      throw Components.results.NS_ERROR_NO_AGGREGATION;

    return this.QueryInterface(iid);
  },

  lockFactory : function fe_lock(lock)
  {
    /* no-op */
  }
};

/**
 * The XPCOM glue that implements nsIModule
 */
const myAppHandlerModule = {
  /* nsISupports */
  QueryInterface : function mod_QI(iid)
  {
    if (iid.equals(nsIModule) ||
        iid.equals(nsISupports))
      return this;

    throw Components.results.NS_ERROR_NO_INTERFACE;
  },

  /* nsIModule */
  getClassObject : function mod_gch(compMgr, cid, iid)
  {
    if (cid.equals(fe_CID))
      return myAppHandler.QueryInterface(iid);

    throw Components.results.NS_ERROR_NOT_REGISTERED;
  },

  registerSelf : function mod_regself(compMgr, fileSpec, location, type)
  {
    compMgr.QueryInterface(nsIComponentRegistrar);

    compMgr.registerFactoryLocation(fe_CID,
                                    "myAppHandler",
                                    fe_contractID,
                                    fileSpec,
                                    location,
                                    type);

    var catMan = Components.classes["@mozilla.org/categorymanager;1"].
      getService(nsICategoryManager);
    catMan.addCategoryEntry("content-policy",
                            fe_category,
                            fe_contractID, true, true);
  },

  unregisterSelf : function mod_unreg(compMgr, location, type)
  {
    compMgr.QueryInterface(nsIComponentRegistrar);
    compMgr.unregisterFactoryLocation(fe_CID, location);

    var catMan = Components.classes["@mozilla.org/categorymanager;1"].
      getService(nsICategoryManager);
    catMan.deleteCategoryEntry("content-policy", fe_category);
  },

  canUnload : function (compMgr)
  {
    return true;
  }
};

/* The NSGetModule function is the magic entry point that XPCOM uses to find what XPCOM objects
 * this component provides
 */
function NSGetModule(comMgr, fileSpec)
{
  return myAppHandlerModule;
}

