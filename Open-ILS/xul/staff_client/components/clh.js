const nsISupports           = Components.interfaces.nsISupports;
const nsICategoryManager    = Components.interfaces.nsICategoryManager;
const nsIComponentRegistrar = Components.interfaces.nsIComponentRegistrar;
const nsICommandLine        = Components.interfaces.nsICommandLine;
const nsICommandLineHandler = Components.interfaces.nsICommandLineHandler;
const nsIFactory            = Components.interfaces.nsIFactory;
const nsIModule             = Components.interfaces.nsIModule;
const nsIWindowWatcher      = Components.interfaces.nsIWindowWatcher;


const XUL_STANDALONE = "chrome://open_ils_staff_client/content/circ/offline.xul";
const XUL_MAIN = "chrome://open_ils_staff_client/content/main/main.xul";
const WINDOW_STANDALONE = "eg_offline"
const WINDOW_MAIN = "eg_main"

const clh_contractID = "@mozilla.org/commandlinehandler/general-startup;1?type=egcli";
const clh_CID = Components.ID("{7e608198-7355-483a-a85a-20322e4ef91a}");
// category names are sorted alphabetically. Typical command-line handlers use a
// category that begins with the letter "m".
const clh_category = "m-egcli";

/**
 * Utility functions
 */

/**
 * Opens a chrome window.
 * @param aChromeURISpec a string specifying the URI of the window to open.
 * @param aArgument an argument to pass to the window (may be null)
 */
function findOrOpenWindow(aWindowType, aChromeURISpec, aName, aArgument, aLoginInfo)
{
  var wm = Components.classes["@mozilla.org/appshell/window-mediator;1"].
    getService(Components.interfaces.nsIWindowMediator);
  var targetWindow = wm.getMostRecentWindow(aWindowType);
  if (targetWindow != null) {
      var noFocus = false;
      if(typeof targetWindow.new_tabs == 'function' && aArgument != null) {
          targetWindow.new_tabs(aArgument);
          noFocus = true;
      }
      if(typeof targetWindow.auto_login == 'function' && aLoginInfo != null) {
          targetWindow.auto_login(aLoginInfo);
          noFocus = true;
      }
      if(!noFocus) {
          targetwindow.focus;
      }
  }
  else {
    var params = null;
    if (aArgument != null && aArgument.length != 0 || aLoginInfo != null)
    {
        params = { "openTabs" : aArgument, "loginInfo" : aLoginInfo };
        params.wrappedJSObject = params;
    }
    var ww = Components.classes["@mozilla.org/embedcomp/window-watcher;1"].
        getService(Components.interfaces.nsIWindowWatcher);
    ww.openWindow(null, aChromeURISpec, aName,
        "chrome,resizable,dialog=no", params);
  }
}
 
/**
 * The XPCOM component that implements nsICommandLineHandler.
 * It also implements nsIFactory to serve as its own singleton factory.
 */
const myAppHandler = {
  /* nsISupports */
  QueryInterface : function clh_QI(iid)
  {
    if (iid.equals(nsICommandLineHandler) ||
        iid.equals(nsIFactory) ||
        iid.equals(nsISupports))
      return this;

    throw Components.results.NS_ERROR_NO_INTERFACE;
  },

  /* nsICommandLineHandler */

  handle : function clh_handle(cmdLine)
  {
    // Each of these options is used for opening a new tab, either on login or remote send.
    // XULRunner does some sanitize to turn /ilsblah into -ilsblah, for example.
    // In addition to the ones here, -ilslogin, -ilsoffline, and -ilsstandalone
    // are defined below.

    // With the exception of 'new', 'tab', and 'init', the value is checked for in urls in main.js.

    // NOTE: The option itself should be all lowercase (we .toLowerCase below)
    var options = {
    '-ilscheckin' : 'XUL_CHECKIN',
    '-ilscheckout' : 'XUL_PATRON_BARCODE_ENTRY',
    '-ilsnew' : 'new', // 'new' is a special keyword for opening a new window
    '-ilstab' : 'tab', // 'tab' is a special keyword for opening a new tab with the default content
    '-ilsnew_default' : 'init', // 'init' is a special keyword for opening a new window with an initial default tab
    };

    var inParams = new Array();
    var loginInfo = {};
    var loginInfoProvided = false;
	var position = 0;
	while (position < cmdLine.length) {
		var arg = cmdLine.getArgument(position).toLowerCase();
		if (options[arg] != undefined) {
			inParams.push(options[arg]);
			cmdLine.removeArguments(position,position);
			continue;
		}
        if (arg == '-ilsurl' && cmdLine.length > position) {
		  inParams.push(cmdLine.getArgument(position + 1));
		  cmdLine.removeArguments(position, position + 1);
		  continue;
		}
        if (arg == '-ilshost' && cmdLine.length > position) {
          loginInfo.host = cmdLine.getArgument(position + 1);
          cmdLine.removeArguments(position, position + 1);
          loginInfoProvided = true;
          continue;
        }
        if (arg == '-ilsuser' && cmdLine.length > position) {
          loginInfo.user = cmdLine.getArgument(position + 1);
          cmdLine.removeArguments(position, position + 1);
          loginInfoProvided = true;
          continue;
        }
        if (arg == '-ilspassword' && cmdLine.length > position) {
          loginInfo.passwd = cmdLine.getArgument(position + 1);
          cmdLine.removeArguments(position, position + 1);
          loginInfoProvided = true;
          continue;
        }
		position=position + 1;
	}

	if (cmdLine.handleFlag("ILSlogin", false) || inParams.length > 0 || loginInfoProvided) {
	  findOrOpenWindow(WINDOW_MAIN, XUL_MAIN, '_blank', inParams, loginInfoProvided ? loginInfo : null);
	  cmdLine.preventDefault = true;
	}

    if (cmdLine.handleFlag("ILSoffline", false) || cmdLine.handleFlag("ILSstandalone", false)) {
   	  findOrOpenWindow(WINDOW_STANDALONE, XUL_STANDALONE, 'Offline', null, null);
      cmdLine.preventDefault = true;
   	}
  },

  // CHANGEME: change the help info as appropriate, but
  // follow the guidelines in nsICommandLineHandler.idl
  // specifically, flag descriptions should start at
  // character 24, and lines should be wrapped at
  // 72 characters with embedded newlines,
  // and finally, the string should end with a newline
  helpInfo : "  -ILScheckin          Open an Evergreen checkin tab\n" +
             "  -ILScheckout         Open an Evergreen checkout tab\n" +
             "  -ILSnew              Open a new Evergreen 'menu' window\n" +
             "  -ILSnew_default      Open a new Evergreen 'menu' window,\n" +
             "                       with a 'default' tab\n" +
             "  -ILStab              Open a 'default' tab alone\n" +
             "  -ILSurl <url>        Open the specified url in an Evergreen tab\n" +
             "  -ILShost             Default hostname for login\n" +
             "  -ILSuser             Default username for login\n" +
             "  -ILSpassword         Default password for login\n" +
             "  The above three, if all specified, trigger an automatic login attempt\n" +
             "  The above nine imply -ILSlogin\n" +
             "  -ILSlogin            Open the Evergreen Login window\n" +
             "  -ILSstandalone       Open the Evergreen Standalone interface\n" +
             "  -ILSoffline          Alias for -ILSstandalone\n",

  /* nsIFactory */

  createInstance : function clh_CI(outer, iid)
  {
    if (outer != null)
      throw Components.results.NS_ERROR_NO_AGGREGATION;

    return this.QueryInterface(iid);
  },

  lockFactory : function clh_lock(lock)
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
    if (cid.equals(clh_CID))
      return myAppHandler.QueryInterface(iid);

    throw Components.results.NS_ERROR_NOT_REGISTERED;
  },

  registerSelf : function mod_regself(compMgr, fileSpec, location, type)
  {
    compMgr.QueryInterface(nsIComponentRegistrar);

    compMgr.registerFactoryLocation(clh_CID,
                                    "myAppHandler",
                                    clh_contractID,
                                    fileSpec,
                                    location,
                                    type);

    var catMan = Components.classes["@mozilla.org/categorymanager;1"].
      getService(nsICategoryManager);
    catMan.addCategoryEntry("command-line-handler",
                            clh_category,
                            clh_contractID, true, true);
  },

  unregisterSelf : function mod_unreg(compMgr, location, type)
  {
    compMgr.QueryInterface(nsIComponentRegistrar);
    compMgr.unregisterFactoryLocation(clh_CID, location);

    var catMan = Components.classes["@mozilla.org/categorymanager;1"].
      getService(nsICategoryManager);
    catMan.deleteCategoryEntry("command-line-handler", clh_category);
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

