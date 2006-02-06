dump('entering util/window.js\n');

if (typeof util == 'undefined') util = {};
util.window = function () {
	JSAN.use('util.error'); this.error = new util.error(); this.win = window;
	return this;
};

util.window.prototype = {
	
	// list of open window references, used for debugging in shell
	'win_list' : [],	

	// list of Top Level menu interface window references
	'appshell_list' : [],	

	// list of documents for debugging.  BROKEN
	'doc_list' : [],	

	// Windows need unique names.  This number helps.
	'window_name_increment' : 0, 

	// This number gets put into the title bar for Top Level menu interface windows
	'appshell_name_increment' : function() {
		var windowManager = Components.classes["@mozilla.org/appshell/window-mediator;1"].getService();
		var windowManagerInterface = windowManager.QueryInterface(Components.interfaces.nsIWindowMediator);
		var enumerator = windowManagerInterface.getEnumerator(null);

		var i = 0; while ( w = enumerator.getNext() ) { i++; }

		return i - 1;
	},

	// From: Bryan White on netscape.public.mozilla.xpfe, Oct 13, 2004
	// Message-ID: <ckjh7a$18q1@ripley.netscape.com>
	// Modified by Jason for Evergreen
	'SafeWindowOpen' : function (url,title,features) {
		var w;

		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		netscape.security.PrivilegeManager.enablePrivilege("UniversalPreferencesRead");
		netscape.security.PrivilegeManager.enablePrivilege("UniversalPreferencesWrite");
		netscape.security.PrivilegeManager.enablePrivilege("UniversalBrowserRead");
		netscape.security.PrivilegeManager.enablePrivilege("UniversalBrowserWrite");

		const CI = Components.interfaces;
		const PB = Components.classes["@mozilla.org/preferences-service;1"].getService(CI.nsIPrefBranch);

		var blocked = false;
		try {
			// pref 'dom.disable_open_during_load' is the main popup blocker preference
			blocked = PB.getBoolPref("dom.disable_open_during_load");
			if(blocked) PB.setBoolPref("dom.disable_open_during_load",false);
			w = this.win.open(url,title,features);
		} catch(E) {
			this.error.sdump('D_ERROR','window.SafeWindowOpen: ' + E + '\n');
			throw(E);
		}
		if(blocked) PB.setBoolPref("dom.disable_open_during_load",true);

		return w;
	},

	'open' : function(url,title,features) {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		if (!title) title = 'anon' + window_name_increment++;
		if (!features) features = 'chrome';
		this.error.sdump('D_WIN',
			'opening ' + url + ', ' + title + ', ' + features + ' from ' + this.win + '\n');
		var w = this.SafeWindowOpen(url,title,features);
		/*
		setTimeout( 
			function() { 
				try { w.title = title; } catch(E) { dump('**'+E+'\n'); }
				try { w.document.title = title; } catch(E) { dump('**'+E+'\n'); }
			}, 0 
		);
		*/
		return w;
	}
}

dump('exiting util/window.js\n');
