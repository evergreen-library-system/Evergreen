Components.utils.import("resource://gre/modules/XPCOMUtils.jsm");

// This component exists to handle custom command line options
// First up, some useful constants

// Standalone interface information
const XUL_STANDALONE = "chrome://open_ils_staff_client/content/circ/offline.xul";
const WINDOW_STANDALONE = "eg_offline"
// Main (login) window information
const XUL_MAIN = "chrome://open_ils_staff_client/content/main/main.xul";
const WINDOW_MAIN = "eg_main"

// Useful utility functions

/**
 * Opens a chrome window.
 * @param aChromeURISpec a string specifying the URI of the window to open.
 * @param aArgument an argument to pass to the window (may be null)
 */
function findOrOpenWindow(aWindowType, aChromeURISpec, aName, aArgument, aLoginInfo)
{
    var wm = Components.classes["@mozilla.org/appshell/window-mediator;1"]
             .getService(Components.interfaces.nsIWindowMediator);
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
            targetWindow.focus();
        }
    }
    else {
        var params = null;
        if (aArgument != null && aArgument.length != 0 || aLoginInfo != null)
        {
            params = { "openTabs" : aArgument, "loginInfo" : aLoginInfo };
            params.wrappedJSObject = params;
        }
        var ww = Components.classes["@mozilla.org/embedcomp/window-watcher;1"]
                 .getService(Components.interfaces.nsIWindowWatcher);
        ww.openWindow(null, aChromeURISpec, aName, "chrome,resizable,dialog=no", params);
    }
}

function oilsCommandLineHandler() {}
oilsCommandLineHandler.prototype = {
    classDescription: "OpenILS Command Line Handler",
    classID:          Components.ID("{7e608198-7355-483a-a85a-20322e4ef91a}"),
    contractID:       "@mozilla.org/commandlinehandler/general-startup;1?type=egcli",
    _xpcom_categories: [{
        category: "command-line-handler",
        entry: "m-egcli"
    }],
    QueryInterface:   XPCOMUtils.generateQI([Components.interfaces.nsICommandLineHandler]),
    handle : function clh_handle(cmdLine) {
        // Each of these options is used for opening a new tab, either on login or remote send.
        // XULRunner does some sanitize to turn /ilsblah into -ilsblah, for example.
        // In addition to the ones here:
        // -ilslogin, -ilsoffline, -ilsstandalone, -ilshost, -ilsuser, and -ilspassword
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

    // Help Info:
    // Flag descriptions start on char 24
    // 72 char wrap on lines, embedded newlines
    // End with a newline
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
};

if (XPCOMUtils.generateNSGetFactory)
    var NSGetFactory = XPCOMUtils.generateNSGetFactory([oilsCommandLineHandler]);
else
    var NSGetModule = XPCOMUtils.generateNSGetModule([oilsCommandLineHandler]);

