// Preferences that get set when the application is loaded

// Modified by Jason for Evergreen

// These are specific to Evergreen
pref("open-ils.write_in_user_chrome_directory", true);
pref("open-ils.disable_accesskeys_on_tabs", false);
pref("toolkit.singletonWindowType", "eg_main");

// Toggles for experimental features that may later become org unit settings
pref("open-ils.enable_join_tabs", true);

// We'll use this one to help brand some build information into the client, and rely on subversion keywords
pref("open-ils.repository.headURL","$HeadURL$");
pref("open-ils.repository.author","$Author$");
pref("open-ils.repository.revision","$Revision$");
pref("open-ils.repository.date","$Date$");
pref("open-ils.repository.id","$Id$");

// Base (empty) prefs for local menu and toolbar customizations
// NOTE: IF YOU SET DEFAULTS ON THESE THE ORG UNIT SETTING VARIANT WON'T WORK
pref("open-ils.menu.hotkeyset", "");
pref("open-ils.menu.toolbar", "");
// For now these are only workstation level and are safe to set defaults on if desired
pref("open-ils.menu.toolbar.iconsize", "");
pref("open-ils.menu.toolbar.mode", "");
pref("open-ils.menu.toolbar.labelbelow", false);
pref("open-ils.toolbar.defaultnewtab", false);

// Template Toolkit Opac Enabled in Staff Client
pref("oils.use_tpac", false);

// Copy location name first in copy editor
pref("oils.copy_editor.copy_location_name_first", false);

// Number of tabs that can be opened in Staff Client
// NOTE: If the value is set to 0 or less, there is no limit to number of tabs.
pref("open-ils.window_max_tabs", 0);
