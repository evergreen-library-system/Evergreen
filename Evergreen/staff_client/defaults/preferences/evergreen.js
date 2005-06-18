// Preferences that get set when the application is loaded

// Modified by Jason for Evergreen

// This one is required for XUL Runner
pref("toolkit.defaultChromeURI", "chrome://evergreen/content/auth/auth.xul");

// This one just makes things speedier.  We use a lot of XMLHttpRequest
pref("network.http.max-persistent-connections-per-server",8);
