// Enable Updater
pref("app.update.enabled", true);
// Change to "false" to not automatically update
pref("app.update.auto", true);
// 0 downloads without prompt always
pref("app.update.mode", 0);

// These settings are in seconds
// Interval for checking
pref("app.update.interval", 86400);
// Time before prompting to download - If auto is off, mainly
pref("app.update.nagTimer.download", 86400);
// Time before prompting to restart to apply update that has downloaded
pref("app.update.nagTimer.restart", 1800);

// How often to check timers (above) - in MILLIseconds
pref("app.update.timer", 600000);


// URL for downloading. For Thomas Berezansky's script the update.xml part isn't needed.
// NOTE: Certs that default to invalid, even those overridden with cert_override.txt, won't work with this!
pref("app.update.url", "https://::HOSTNAME::/updates/check/%CHANNEL%/%VERSION%/update.xml");

// URL for manual update information
pref("app.update.url.manual", "http://::HOSTNAME::/updates/manualupdate.html");

// Default details URL for updates
pref("app.update.url.details", "http://::HOSTNAME::/updates/updatedetails.html");

