// This one is required for XUL Runner
pref("toolkit.defaultChromeURI", "chrome://open_ils_staff_client/content/main/main.xul");

// Let's try to enable tracemonkey
pref("javascript.options.jit.chrome", true);
pref("javascript.options.jit.content", true);

// We'll set a default locale
pref("general.useragent.locale", "en-US");

// We need something like this to get window.open to work in some places (where it complains about
// navigator.xul not being registered). The untrusted_window file provided the minimum required elements.
pref("browser.chromeURL","chrome://open_ils_staff_client/content/util/untrusted_window.xul");

// This one just makes things speedier.  We use a lot of XMLHttpRequest
pref("network.http.max-persistent-connections-per-server",8);

// more speed-up attempts
pref("content.maxtextrun",16385);
pref("browser.display.show_image_placeholders", false);

// This stops the unresponsive script warning, but the code is still too slow for some reason.
// However, it's better than POEM, which I wasted a day on :)
pref("dom.max_script_run_time",60);

// This lets remote xul access link to local chrome, except it doesn't work
pref("security.checkloaduri", false);
pref("signed.applets.codebase_principal_support", true);

// This stops the pop-up blocker.  Well it should, but it doesn't work here
pref("dom.disable_open_during_load", false);
pref("browser.popups.showPopupBlocker", false);
pref("privacy.popups.disable_from_plugins",0);
pref("privacy.popups.policy",0);

pref("browser.download.useDownloadDir", true);
pref("browser.download.folderList", 0);
pref("browser.download.manager.showAlertOnComplete", true);
pref("browser.download.manager.showAlertInterval", 2000);
pref("browser.download.manager.retention", 2);
pref("browser.download.manager.showWhenStarting", true);
pref("browser.download.manager.useWindow", true);
pref("browser.download.manager.closeWhenDone", false);
pref("browser.download.manager.openDelay", 0);
pref("browser.download.manager.focusWhenStarting", false);
pref("browser.download.manager.flashCount", 2); 

// Developer options we want for all builds
pref("browser.dom.window.dump.enabled",true);

// For extension manager, etc.
pref("xpinstall.dialog.confirm", "chrome://mozapps/content/xpinstall/xpinstallConfirm.xul");
pref("xpinstall.dialog.progress.skin", "chrome://mozapps/content/extensions/extensions.xul?type=themes");
pref("xpinstall.dialog.progress.chrome", "chrome://mozapps/content/extensions/extensions.xul?type=extensions");
pref("xpinstall.dialog.progress.type.skin", "Extension:Manager-themes");
pref("xpinstall.dialog.progress.type.chrome", "Extension:Manager-extensions");
pref("extensions.update.enabled", true);
pref("extensions.update.interval", 86400);
pref("extensions.dss.enabled", false);
pref("extensions.dss.switchPending", false);
pref("extensions.ignoreMTimeChanges", false);
pref("extensions.logging.enabled", false);
pref("general.skins.selectedSkin", "classic/1.0");
// NB these point at AMO
pref("extensions.update.url", "chrome://mozapps/locale/extensions/extensions.properties");
pref("extensions.getMoreExtensionsURL", "chrome://mozapps/locale/extensions/extensions.properties");
pref("extensions.getMoreThemesURL", "chrome://mozapps/locale/extensions/extensions.properties");

// Allow opening of web stuff in external apps
// suppress external-load warning for standard browser schemes
pref("network.protocol-handler.warn-external.http", false);
pref("network.protocol-handler.warn-external.https", false);
pref("network.protocol-handler.warn-external.ftp", false);
