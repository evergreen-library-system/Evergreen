dump('entering main/main.js\n');
// vim:noet:sw=4:ts=4:

var xulG;
var offlineStrings;
var authStrings;
var openTabs = new Array();
var tempWindow = null;
var tempFocusWindow = null;

function clear_the_cache() {
    try {
        var cacheClass         = Components.classes["@mozilla.org/network/cache-service;1"];
        var cacheService    = cacheClass.getService(Components.interfaces.nsICacheService);
        cacheService.evictEntries(Components.interfaces.nsICache.STORE_ON_DISK);
        cacheService.evictEntries(Components.interfaces.nsICache.STORE_IN_MEMORY);
    } catch(E) {
        dump(E+'\n');alert(E);
    }
}

function toOpenWindowByType(inType, uri) { /* for Venkman */
    try {
        var winopts = "chrome,extrachrome,menubar,resizable,scrollbars,status,toolbar";
        window.open(uri, "_blank", winopts);
    } catch(E) {
        alert(E); throw(E);
    }
}

function start_debugger() {
    setTimeout(
        function() {
            try { start_venkman(); } catch(E) { alert(E); }
        }, 0
    );
};

function start_inspector() {
    setTimeout(
        function() {
            try { inspectDOMDocument(); } catch(E) { alert(E); }
        }, 0
    );
};

function start_chrome_list() {
    setTimeout(
        function() {
            try { startChromeList(); } catch(E) { alert(E); }
        }, 0
    );
};

function start_js_shell() {
    setTimeout(
        function() {
            try { window.open('chrome://open_ils_staff_client/content/util/shell.html','shell','chrome,resizable,scrollbars'); } catch(E) { alert(E); }
        }, 0
    );
};

function new_tabs(aTabList, aContinue) {
    if(aTabList != null) {
        openTabs = openTabs.concat(aTabList);
    }
    if(G.data.session) { // Just add to the list of stuff to open unless we are logged in
        var targetwindow = null;
        var focuswindow = null;
        var focustab = {'focus' : true};
        if(aContinue == true && tempWindow.closed == false) {
            if(tempWindow.g == undefined || tempWindow.g.menu == undefined) {
                setTimeout(
                    function() {
                        new_tabs(null, true);
                    }, 300);
                return null;
            }
            targetwindow = tempWindow;
            tempWindow = null;
            focuswindow = tempFocusWindow;
            tempFocusWindow = null;
            focustab = {'nofocus' : true};
        }
        else if(tempWindow != null) { // In theory, we are waiting on a setTimeout
            if(tempWindow.closed == true) // But someone closed our window?
            {
                tempWindow = null;
                tempFocusWindow = null;
            }
            else
            {
                return null;
            }
        }
        var newTab;
        var firstURL;
        var wm = Components.classes["@mozilla.org/appshell/window-mediator;1"].
            getService(Components.interfaces.nsIWindowMediator);
            // This may look out of place, but this is so we can continue this loop from down below
opentabs:
            while(openTabs.length > 0) {
            newTab = openTabs.shift();
            if(newTab == 'new' || newTab == 'init') {
                if(newTab != 'init' && openTabs.length > 0 && openTabs[0] != 'new') {
                    firstURL = openTabs.shift();
                    if(firstURL != 'tab') { // 'new' followed by 'tab' should be equal to 'init' in functionality, this should do that
                        if(urls[firstURL]) {
                            firstURL = urls[firstURL];
                        }
                        firstURL = '&firstURL=' + window.escape(firstURL);
                    }
                    else {
                        firstURL = '';
                    }
                }
                else {
                    firstURL = '';
                }
                targetwindow = xulG.window.open(urls.XUL_MENU_FRAME
                    + '?server='+window.escape(G.data.server) + firstURL,
                    '_blank','chrome,resizable'
                );
                targetwindow.xulG = xulG;
                if (focuswindow == null) {
                    focuswindow = targetwindow;
                }
                tempWindow = targetwindow;
                tempFocusWindow = focuswindow;
                setTimeout(
                    function() {
                        new_tabs(null, true);
                    }, 300);
                return null;
            }
            else {
                if(newTab == 'tab') {
                    newTab = null;
                }
                else if(urls[newTab]) {
                    newTab = urls[newTab];
                }
                if(targetwindow != null) { // Already have a previous target window? Use it first.
                    if(targetwindow.g.menu.new_tab(newTab,focustab,null)) {
                        focustab = {'nofocus' : true};
                        continue;
                    }
                }
                var enumerator = wm.getEnumerator('eg_menu');
                while(enumerator.hasMoreElements()) {
                    targetwindow = enumerator.getNext();
                    if(targetwindow.g.menu.new_tab(newTab,focustab,null)) {
                        focustab = {'nofocus' : true};
                        if (focuswindow == null) {
                            focuswindow = targetwindow;
                        }
                        continue opentabs;
                    }
                }
                // No windows found to add the tab to? Make a new one.
                if(newTab == null) { // Were we making a "default" tab?
                    openTabs.unshift('init'); // 'init' does that for us!
                }
                else {
                    openTabs.unshift('new',newTab);
                }
            }
        }
        if(focuswindow != null) {
            focuswindow.focus();
        }
    }
}

// Returns false if we can't get an actual perm list
// Returns an array of perms with boolean has/hasn't flag
function get_menu_perms(indocument) {
    // If we don't have our static perm list, and we have a remote window, go looking.
    // We never need to look twice unless a dev is manually editing their files.
    // Shame on them, they can restart the entire client ;)
    if(typeof(get_menu_perms.perm_list) == 'undefined' && indocument != null)
    {
        get_menu_perms.perm_list = [ ];
        var commands = indocument.getElementById('universal_cmds').getElementsByTagName('command');
        for (var i = 0; i < commands.length; i++) { 
            if (commands[i].hasAttribute('perm')) {
                get_menu_perms.perm_list = get_menu_perms.perm_list.concat(commands[i].getAttribute('perm').split(' '));
            }           
        }
    }
    // 
    if(typeof(get_menu_perms.perm_list) == 'object') {
        G.data.stash_retrieve();
        if(!G.data.menu_perms) {
            JSAN.use('util.network');
            var network = new util.network();
            var r = network.simple_request('BATCH_PERM_RETRIEVE_WORK_OU', [ G.data.session.key, get_menu_perms.perm_list ]);
            for(p in r)
                r[p] = (typeof(r[p][0]) == 'number');
            // Developer-enabled clients override permissions and always allow debugging
            if(G.data.debug_build) {
                r['DEBUG_CLIENT'] = true;
            }
            // If we have DEBUG_CLIENT (by force or otherwise) we can use debugging interfaces
            // Doing this here because this function gets called at least once per login
            // Including operator change
            G.data.enable_debug = (r['DEBUG_CLIENT'] == true);
            G.data.stash('enable_debug');
            G.data.menu_perms = r;
            G.data.stash('menu_perms');
        }
        return G.data.menu_perms;
    }
    return false;
}

// Returns a list (cached or from filesystem) of hotkey sets
function load_hotkey_sets() {
    if(typeof(load_hotkey_sets.set_list) == 'undefined') {
        load_hotkey_sets.set_list = [];
        // We can't safely use util.file here because extensions aren't unpacked in Firefox 4+
        // So instead we will use and parse information from a chrome:// URL
        var hotkeysBase = 'chrome://open_ils_staff_client/skin/hotkeys/';
        var ioService=Components.classes["@mozilla.org/network/io-service;1"]
            .getService(Components.interfaces.nsIIOService);
        var scriptableStream=Components
            .classes["@mozilla.org/scriptableinputstream;1"]
            .getService(Components.interfaces.nsIScriptableInputStream);

        var channel=ioService.newChannel(hotkeysBase,null,null);
        var input=channel.open();
        var str = '';
        scriptableStream.init(input);
        try {
            while(input.available()) {
                str+=scriptableStream.read(input.available());
            }
        } catch (E) {}
        scriptableStream.close();
        input.close();
        // str now, in theory, has a list of files (and metadata) for our base chrome URL.
        str = str.replace(/^(?!201: ).*$/gm,''); // Remove non-filename result lines
        str = str.replace(/^(?!.*\.keyset).*$/gm,''); // Remove non-keyset file result lines
        str = str.replace(/^201: (.*)\.keyset.*$/gm, "$1"); // Reduce keyset matches to just base names
        // Split into an array
        var files = str.trim().split(/[\r\n]+/g);
        for (var i = 0; i < files.length; i++) {
            if(files[i].length = 0) continue;
            load_hotkey_sets.set_list.push(files[i]);
        }
    }
    return load_hotkey_sets.set_list;
}

// Returns an array (cached or from filesystem) for a given hotkey set
function get_hotkey_array(keyset_name) {
    if(typeof(get_hotkey_array.keyset_cache) == 'undefined') {
        get_hotkey_array.keyset_cache = {};
    }
    if(get_hotkey_array.keyset_cache[keyset_name])
        return get_hotkey_array.keyset_cache[keyset_name];
    // We can't safely use util.file here because extensions aren't unpacked in Firefox 4+
    // So instead we will use and parse information from a chrome:// URL
    var hotkeysBase = 'chrome://open_ils_staff_client/skin/hotkeys/' + keyset_name + '.keyset';
    var ioService=Components.classes["@mozilla.org/network/io-service;1"]
        .getService(Components.interfaces.nsIIOService);
    var scriptableStream=Components
        .classes["@mozilla.org/scriptableinputstream;1"]
        .getService(Components.interfaces.nsIScriptableInputStream);

    var channel=ioService.newChannel(hotkeysBase,null,null);
    var input=channel.open();
    var keyset_raw = '';
    scriptableStream.init(input);
    try {
        while(input.available()) {
            keyset_raw+=scriptableStream.read(input.available());
        }
    } catch (E) {}
    scriptableStream.close();
    input.close();

    var tempArray = [];

    var keyset_lines = keyset_raw.trim().split("\n");
    for(var line = 0; line < keyset_lines.length; line++) {
        // Grab line, strip comments, strip leading/trailing whitespace
        var curline = keyset_lines[line].replace(/\s*#.*$/,'').trim();
        if(curline == "") continue; // Skip empty lines
        // Split into pieces
        var split_line = curline.split(',');
        // We need at least 3 elements. Command, modifiers, keycode.
        if(split_line.length < 3) continue;
        // Trim each segment
        split_line[0] = split_line[0].trim();
        split_line[1] = split_line[1].trim();
        split_line[2] = split_line[2].trim();
        if(split_line.length > 3)
            split_line[3] = split_line[3].trim();
        // Skip empty commands
        if(split_line[0] == "") continue;
        // Push to array
        tempArray.push(split_line);
    }
    get_hotkey_array.keyset_cache[keyset_name] = tempArray;
    return tempArray;
}

function main_init() {
    dump('entering main_init()\n');
    try {
        clear_the_cache();
        if("arguments" in window && window.arguments.length > 0 && window.arguments[0].wrappedJSObject != undefined && window.arguments[0].wrappedJSObject.openTabs != undefined) {
            openTabs = openTabs.concat(window.arguments[0].wrappedJSObject.openTabs);
        }

        // Disable commands that we can't do anything with right now
        if(typeof start_venkman != 'function') {
            document.getElementById('cmd_debugger').setAttribute('disabled','true');
        }
        if(typeof inspectDOMDocument != 'function') {
            document.getElementById('cmd_inspector').setAttribute('disabled','true');
        }
        if(typeof startChromeList != 'function') {
            document.getElementById('cmd_chrome_list').setAttribute('disabled','true');
        }

        // Now we can safely load the strings without the cache getting wiped
        offlineStrings = document.getElementById('offlineStrings');
        authStrings = document.getElementById('authStrings');

        if (typeof JSAN == 'undefined') {
            throw(
                offlineStrings.getString('common.jsan.missing')
            );
        }
        /////////////////////////////////////////////////////////////////////////////

        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('..');

        //JSAN.use('test.test'); test.test.hello_world();

        var mw = self;
        G =  {};
        
        G.pref = Components.classes["@mozilla.org/preferences-service;1"].getService(Components.interfaces.nsIPrefBranch);
        G.pref.QueryInterface(Components.interfaces.nsIPrefBranch2);

        JSAN.use('util.error');
        G.error = new util.error();
        G.error.sdump('D_ERROR', offlineStrings.getString('main.testing'));

        JSAN.use('util.window');
        G.window = new util.window();

        JSAN.use('auth.controller');
        G.auth = new auth.controller( { 'window' : mw } );

        JSAN.use('OpenILS.data');
        G.data = new OpenILS.data();
        G.data.on_error = G.auth.logoff;

        JSAN.use('util.file');
        G.file = new util.file();
        try {
            G.file.get('ws_info');
            G.ws_info = G.file.get_object(); G.file.close();
        } catch(E) {
            G.ws_info = {};
        }
        G.data.ws_info = G.ws_info; G.data.stash('ws_info');

        G.auth.on_login = function() {

            var url = G.auth.controller.view.server_prompt.value.match(/^[^\/]*/).toString() || urls.remote;

            G.data.server_unadorned = url; G.data.stash('server_unadorned'); G.data.stash_retrieve();

            if (! url.match( '^(http|https)://' ) ) { url = 'http://' + url; }

            G.data.server = url; G.data.stash('server'); 
            G.data.session = { 'key' : G.auth.session.key, 'auth' : G.auth.session.authtime }; G.data.stash('session');
            G.data.stash_retrieve();
            try {
                var ios = Components.classes["@mozilla.org/network/io-service;1"].getService(Components.interfaces.nsIIOService);
                var cookieUriSSL = ios.newURI("https://" + G.data.server_unadorned, null, null);
                var cookieSvc = Components.classes["@mozilla.org/cookieService;1"].getService(Components.interfaces.nsICookieService);

                cookieSvc.setCookieString(cookieUriSSL, null, "ses="+G.data.session.key + "; secure;", null);

            } catch(E) {
                alert(offlineStrings.getFormattedString(main.session_cookie.error, [E]));
            }

            xulG = {
                'auth' : G.auth,
                'url' : url,
                'window' : G.window,
                'data' : G.data,
                'pref' : G.pref
            };

            if (G.data.ws_info && G.data.ws_info[G.auth.controller.view.server_prompt.value]) {
                JSAN.use('util.widgets');
                var deck = document.getElementById('progress_space');
                util.widgets.remove_children( deck );
                var iframe = document.createElement('iframe'); deck.appendChild(iframe);
                iframe.setAttribute( 'src', urls.XUL_LOGIN_DATA );
                iframe.contentWindow.xulG = xulG;
                G.data_xul = iframe.contentWindow;
            } else {
                xulG.file = G.file;
                var deck = G.auth.controller.view.ws_deck;
                JSAN.use('util.widgets'); util.widgets.remove_children('ws_deck');
                var iframe = document.createElement('iframe'); deck.appendChild(iframe);
                iframe.setAttribute( 'src', urls.XUL_WORKSTATION_INFO );
                iframe.contentWindow.xulG = xulG;
                deck.selectedIndex = deck.childNodes.length - 1;
            }
        };

        G.auth.on_standalone = function() {
            try {
                G.window.open(urls.XUL_STANDALONE,'Offline','chrome,resizable');
            } catch(E) {
                alert(E);
            }
        };

        G.auth.on_standalone_export = function() {
            try {
                JSAN.use('util.file'); var file = new util.file('pending_xacts');
                if (file._file.exists()) {
                    var file2 = new util.file('');
                    var f = file2.pick_file( { 'mode' : 'save', 'title' : offlineStrings.getString('main.transaction_export.title') } );
                    if (f) {
                        if (f.exists()) {
                            var r = G.error.yns_alert(
                                offlineStrings.getFormattedString('main.transaction_export.prompt', [f.leafName]),
                                offlineStrings.getString('main.transaction_export.prompt.title'),
                                offlineStrings.getString('common.yes'),
                                offlineStrings.getString('common.no'),
                                null,
                                offlineStrings.getString('common.confirm')
                            );
                            if (r != 0) { file.close(); return; }
                        }
                        var e_file = new util.file(''); e_file._file = f;
                        e_file.write_content( 'truncate', file.get_content() );
                        e_file.close();
                        var r = G.error.yns_alert(
                            offlineStrings.getFormattedString('main.transaction_export.success.prompt', [f.leafName]),
                            offlineStrings.getString('main.transaction_export.success.title'),
                            offlineStrings.getString('common.yes'),
                            offlineStrings.getString('common.no'),
                            null,
                            offlineStrings.getString('common.confirm')
                        );
                        if (r == 0) {
                            var count = 0;
                            var filename = 'pending_xacts_exported_' + new Date().getTime();
                            var t_file = new util.file(filename);
                            while (t_file._file.exists()) {
                                filename = 'pending_xacts_' + new Date().getTime() + '.exported';
                                t_file = new util.file(filename);
                                if (count++ > 100) {
                                    throw(offlineStrings.getString('main.transaction_export.filename.error'));
                                }
                            }
                            file.close(); file = new util.file('pending_xacts'); // prevents a bug with .moveTo below
                            file._file.moveTo(null,filename);
                        } else {
                            alert(offlineStrings.getString('main.transaction_export.duplicate.warning'));
                        }
                    } else {
                        alert(offlineStrings.getString('main.transaction_export.no_filename.error'));
                    }
                } else {
                    alert(offlineStrings.getString('main.transaction_export.no_transactions.error'));
                }
                file.close();
            } catch(E) {
                alert(E);
            }
        };

        G.auth.on_standalone_import = function() {
            try {
                JSAN.use('util.file'); var file = new util.file('pending_xacts');
                if (file._file.exists()) {
                    alert(offlineStrings.getString('main.transaction_import.outstanding.error'));
                } else {
                    var file2 = new util.file('');
                    var f = file2.pick_file( { 'mode' : 'open', 'title' : offlineStrings.getString('main.transaction_import.title')} );
                    if (f && f.exists()) {
                        var i_file = new util.file(''); i_file._file = f;
                        file.write_content( 'truncate', i_file.get_content() );
                        i_file.close();
                        var r = G.error.yns_alert(
                            offlineStrings.getFormattedString('main.transaction_import.delete.prompt', [f.leafName]),
                            offlineStrings.getString('main.transaction_import.success'),
                            offlineStrings.getString('common.yes'),
                            offlineStrings.getString('common.no'),
                            null,
                            offlineStrings.getString('common.confirm')
                        );
                        if (r == 0) {
                            f.remove(false);
                        }
                    }
                }
                file.close();
            } catch(E) {
                alert(E);
            }
        };

        G.auth.on_debug = function(action) {
            switch(action) {
                case 'js_console' :
                    G.window.open(urls.XUL_DEBUG_CONSOLE,'testconsole','chrome,resizable');
                break;
                case 'clear_cache' :
                    clear_the_cache();
                    alert(offlineStrings.getString('main.on_debug.clear_cache'));
                break;
                default:
                    alert(offlineStrings.getString('main.on_debug.debug'));
                break;
            }
        };

        G.auth.init();
        // XML_HTTP_SERVER will get reset to G.auth.controller.view.server_prompt.value

        /////////////////////////////////////////////////////////////////////////////

        var version = CLIENT_VERSION;
        if (CLIENT_STAMP.length == 0) {
            version = 'versionless debug build';
            document.getElementById('debug_gb').hidden = false;
        }

        try {
            if (G.pref && G.pref.getBoolPref('open-ils.debug_options')) {
                document.getElementById('debug_gb').hidden = false;
            }
        } catch(E) {
        }

        // If we are showing the debugging frame then we consider this a debug build
        // This could be a versionless build, a developer-pref enabled build, or otherwise
        // If set this will enable all debugging commands, even if you normally don't have permission to use them
        G.data.debug_build = !document.getElementById('debug_gb').hidden;
        G.data.stash('debug_build');

        var appInfo = Components.classes["@mozilla.org/xre/app-info;1"] 
            .getService(Components.interfaces.nsIXULAppInfo); 

        if (appInfo.ID == "staff-client@open-ils.org")
        {
            try {
                if (G.pref && G.pref.getBoolPref('app.update.enabled')) {
                    document.getElementById('check_upgrade_sep').hidden = false;
                    var upgrademenu = document.getElementById('check_upgrade');
                    upgrademenu.hidden = false;
                    G.upgradeCheck = function () {
                        var um = Components.classes["@mozilla.org/updates/update-manager;1"]
                            .getService(Components.interfaces.nsIUpdateManager);
                        var prompter = Components.classes["@mozilla.org/updates/update-prompt;1"]
                            .createInstance(Components.interfaces.nsIUpdatePrompt);

                        if (um.activeUpdate && um.activeUpdate.state == "pending")
                            prompter.showUpdateDownloaded(um.activeUpdate);
                        else
                            prompter.checkForUpdates();
                    }
                    upgrademenu.addEventListener(
                        'command',
                        G.upgradeCheck,
                        false
                    );
                }
            } catch(E) {
            }
        }

        window.document.title = authStrings.getFormattedString('staff.auth.titlebar.label', CLIENT_VERSION);
        var x = document.getElementById('about_btn');
        x.addEventListener(
            'command',
            function() {
                try { 
                    G.window.open('about.html','about','chrome,resizable,width=800,height=600');
                } catch(E) { alert(E); }
            }, 
            false
        );

        var y = document.getElementById('new_window_btn');
        y.addEventListener(
            'command',
            function() {
                if (G.data.session) {
                    new_tabs(Array('new'), null, null);
                } else {
                    alert ( offlineStrings.getString('main.new_window_btn.login_first_warning') );
                }
            },
            false
        );

        JSAN.use('util.mozilla');
        var z = document.getElementById('locale_menupopup');
        if (z) {
            while (z.lastChild) z.removeChild(z.lastChild);
            var locales = util.mozilla.chromeRegistry().getLocalesForPackage( String( location.href ).split(/\//)[2] );
            var current_locale = util.mozilla.prefs().getCharPref('general.useragent.locale');
            while (locales.hasMore()) {
                var locale = locales.getNext();
                var parts = locale.split(/-/);
                var label;
                try {
                    label = locale + ' : ' + util.mozilla.languages().GetStringFromName(parts[0]);
                    if (parts.length > 1) {
                        try {
                            label += ' (' + util.mozilla.regions().GetStringFromName(parts[1].toLowerCase()) + ')';
                        } catch(E) {
                            label += ' (' + parts[1] + ')';
                        }
                    }
                } catch(E) {
                    label = locale;
                }
                var mi = document.createElement('menuitem');
                mi.setAttribute('label',label);
                mi.setAttribute('value',locale);
                if (locale == current_locale) {
                    if (z.parentNode.tagName == 'menulist') {
                        mi.setAttribute('selected','true');
                        z.parentNode.setAttribute('label',label);
                        z.parentNode.setAttribute('value',locale);
                    }
                }
                z.appendChild( mi );
            }
        }
        var xx = document.getElementById('apply_locale_btn');
        xx.addEventListener(
            'command',
            function() {
                util.mozilla.change_locale(z.parentNode.value);
            },
            false
        );

        if ( found_ws_info_in_Achrome() && G.pref && G.pref.getBoolPref("open-ils.write_in_user_chrome_directory") ) {
            //var hbox = x.parentNode; var b = document.createElement('button'); 
            //b.setAttribute('label','Migrate legacy settings'); hbox.appendChild(b);
            //b.addEventListener(
            //    'command',
            //    function() {
            //        try {
            //            handle_migration();
            //        } catch(E) { alert(E); }
            //    },
            //    false
            //);
            if (window.confirm(offlineStrings.getString('main.settings.migrate'))) {
                setTimeout( function() { handle_migration(); }, 0 );
            }
        }

        window.addEventListener(
            'close',
            function(ev) {

                G.data.stash_retrieve();
                if (typeof G.data.unsaved_data != 'undefined') {
                    if (G.data.unsaved_data > 0) {
                        var confirmation = window.confirm(offlineStrings.getString('menu.shutdown.unsaved_data_warning'));
                        if (!confirmation) {
                            ev.preventDefault();
                            return false;
                        }
                    }
                }
                G.data.unsaved_data = 0;
                G.data.stash('unsaved_data');

                return true;

            },
            false
        );

        /**
            @brief Stats for Offline Files / Transactions
            @launchpad #797408
        */
        var px = new util.file('pending_xacts');
        document.getElementById('offline_message').setAttribute('style','display:none;');
        if (px._file.exists()) {
            document.getElementById('offline_message').setAttribute('style','background-color:red;display:block;font-weight:bold;padding:2px;');
            document.getElementById('offline_import_btn').disabled = true;
        }

        // Attempt auto-login, if provided
        if("arguments" in window && window.arguments.length > 0 && window.arguments[0].wrappedJSObject != undefined && window.arguments[0].wrappedJSObject.loginInfo != undefined) {
            auto_login(window.arguments[0].wrappedJSObject.loginInfo);
            // Regardless of success, clear that variable now, so we don't possibly have passwords hanging around.
            window.arguments[0].wrappedJSObject.loginInfo = null;
        }

    } catch(E) {
        var error = offlineStrings.getFormattedString('common.exception', [E, '']);
        try { G.error.sdump('D_ERROR',error); } catch(E) { dump(error); }
        alert(error);
    }
    dump('exiting main_init()\n');
}

function found_ws_info_in_Achrome() {
    JSAN.use('util.file');
    var f = new util.file();
    var f_in_chrome = f.get('ws_info','chrome');
    var path = f_in_chrome.exists() ? f_in_chrome.path : false;
    f.close();
    return path;
}

function found_ws_info_in_Uchrome() {
    JSAN.use('util.file');
    var f = new util.file();
    var f_in_uchrome = f.get('ws_info','uchrome');
    var path = f_in_uchrome.exists() ? f_in_uchrome.path : false;
    f.close();
    return path;
}

function handle_migration() {
    if ( found_ws_info_in_Uchrome() ) {
        alert(offlineStrings.getFormattedString('main.settings.migrate.failed', [found_ws_info_in_Uchrome(), found_ws_info_in_Achrome()])
        );
    } else {
        var dirService = Components.classes["@mozilla.org/file/directory_service;1"].getService( Components.interfaces.nsIProperties );
        var f_new = dirService.get( "UChrm", Components.interfaces.nsIFile );
        var f_old = dirService.get( "AChrom", Components.interfaces.nsIFile );
        f_old.append(myPackageDir); f_old.append("content"); f_old.append("conf"); 
        if (window.confirm(offlineStrings.getFormattedString("main.settings.migrate.confirm", [f_old.path, f_new.path]))) {
            var files = f_old.directoryEntries;
            while (files.hasMoreElements()) {
                var file = files.getNext();
                var file2 = file.QueryInterface( Components.interfaces.nsILocalFile );
                try {
                    file2.moveTo( f_new, '' );
                } catch(E) {
                    alert(offlineStrings.getFormattedString('main.settings.migrate.error', [file2.path, f_new.path]) + '\n');
                }
            }
            location.href = location.href; // huh?
        }
    }
}

function auto_login(loginInfo) {
    G.data.stash_retrieve();
    if(G.data.session) return; // We are logged in. No auto-logoff supported.
    if(loginInfo.host) G.auth.controller.view.server_prompt.value = loginInfo.host;
    if(loginInfo.user) G.auth.controller.view.name_prompt.value = loginInfo.user;
    if(loginInfo.passwd) G.auth.controller.view.password_prompt.value = loginInfo.passwd;
    if(loginInfo.host && loginInfo.user && loginInfo.passwd && G.data.ws_info && G.data.ws_info[loginInfo.host]) {
        G.auth.login();
    }
}

dump('exiting main/main.js\n');
