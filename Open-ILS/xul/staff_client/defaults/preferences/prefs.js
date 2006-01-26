// Preferences that get set when the application is loaded

// Modified by Jason for Evergreen

// This one is required for XUL Runner
pref("toolkit.defaultChromeURI", "chrome://open_ils_staff_client/content/main/main.xul");

// This one just makes things speedier.  We use a lot of XMLHttpRequest
pref("network.http.max-persistent-connections-per-server",8);

// This stops the unresponsive script warning, but the code is still too slow for some reason.
// However, it's better than POEM, which I wasted a day on :)
pref("dom.max_script_run_time",60);

// This lets remote xul access link to local chrome, except it doesn't work
pref("security.checkloaduri", false);
pref("signed.applets.codebase_principal_support", true);

// Developer options
pref("browser.dom.window.dump.enabled",true);
pref("javascript.options.strict",false);
pref("javascript.options.showInConsole",true);
pref("nglayout.debug.disable_xul_cache",true);
pref("nglayout.debug.disable_xul_fastload",true);
pref("browser.xul.error_pages.enabled",true);

