// Preferences that get set when the application is loaded

// Modified by Jason for Evergreen

// This one is required for XUL Runner
pref("toolkit.defaultChromeURI", "chrome://evergreen/content/auth/auth.xul");

// This one just makes things speedier.  We use a lot of XMLHttpRequest
pref("network.http.max-persistent-connections-per-server",8);

// This stops the unresponsive script warning, but the code is still too slow for some reason.
// However, it's better than POEM, which I wasted a day on :)
pref("dom.max_script_run_time",60);

pref("javascript.options.strict",false);
