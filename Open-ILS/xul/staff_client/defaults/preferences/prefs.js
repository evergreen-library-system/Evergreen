// Preferences that get set when the application is loaded

// Modified by Jason for Evergreen

// This one is required for XUL Runner
pref("toolkit.defaultChromeURI", "chrome://open_ils_staff_client/content/main/main.xul");

// Let's try to enable tracemonkey
pref("javascript.options.jit.chrome", true);
pref("javascript.options.jit.content", true);

// We'll use this one to help brand some build information into the client, and rely on subversion keywords
pref("open-ils.repository.headURL","$HeadURL$");
pref("open-ils.repository.author","$Author$");
pref("open-ils.repository.revision","$Revision$");
pref("open-ils.repository.date","$Date$");
pref("open-ils.repository.id","$Id$");

// We'll set a default locale
pref("general.useragent.locale", "en-US");

// We need something like this to get window.open to work in some places (where it complains about
// navigator.xul not being registered.  But is about:blank the best value to use here?
pref("browser.chromeURL","about:blank");

// This one is specific for Open-ILS
pref("open-ils.write_in_user_chrome_directory", true);

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

// Developer options
pref("browser.dom.window.dump.enabled",true);
pref("javascript.options.strict",true);
pref("javascript.options.showInConsole",true);
pref("nglayout.debug.disable_xul_cache",false);
pref("nglayout.debug.disable_xul_fastload",false);
pref("browser.xul.error_pages.enabled",true);
// This one is specific for Open-ILS; debug options on login window
pref("open-ils.debug_options", true);


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

