// Preferences that get set when the application is loaded

// This one is required for XUL Runner
pref("toolkit.defaultChromeURI", "chrome://evergreen/content/evergreen.xul");

// This one just makes things speedier.  We use a lot of XMLHttpRequest
pref("network.http.max-persistent-connections-per-server",8);
