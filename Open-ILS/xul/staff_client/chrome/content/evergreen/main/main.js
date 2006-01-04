dump('entering main/main.js\n');

function grant_perms(url) {
	var pref = Components.classes["@mozilla.org/preferences-service;1"]
		.getService(Components.interfaces.nsIPrefBranch);
	if (pref) {
		pref.setCharPref("capability.principal.codebase.p0.granted", "UniversalXPConnect UniversalPreferencesWrite UniversalBrowserWrite UniversalPreferencesRead UniversalBrowserRead");
		pref.setCharPref("capability.principal.codebase.p0.id", url);
	}

}

function main_init() {
	dump('entering main_init()\n');
	try {
		if (typeof JSAN == 'undefined') {
			throw(
				"The JSAN library object is missing."
			);
		}
		/////////////////////////////////////////////////////////////////////////////

		JSAN.errorLevel = "die"; // none, warn, or die
		JSAN.addRepository('..');

		//JSAN.use('test.test'); test.test.hello_world();

		var mw = self;
		var G =  {};
		G.OpenILS = {};
		G.OpenSRF = {};

		JSAN.use('util.error');
		G.error = new util.error();
		G.error.sdump('D_ERROR','Testing');

		JSAN.use('util.window');
		G.window = new util.window();

		//G.window.open(urls.XUL_DEBUG_CONSOLE,'testconsole','chrome,resizable');

		JSAN.use('auth.controller');
		G.auth = new auth.controller( { 'window' : mw } );

		JSAN.use('OpenILS.data');
		G.OpenILS.data = new OpenILS.data()
		G.OpenILS.data.on_error = G.auth.logoff;
		G.OpenILS.data.entities = entities;
		G.OpenILS.data.stash('entities');

		G.auth.on_login = function() {

			G.OpenILS.data.session = G.auth.session.key;
			G.OpenILS.data.on_complete = function () {

				var url = G.auth.controller.view.server_prompt.value || urls.remote;
				if (! url.match( '^http://' ) ) url = 'http://' + url;
				grant_perms(url);
				
				G.OpenILS.data.stash('list','hash','temp');
				G.OpenILS.data._debug_stash();

				G.window.open(urls.XUL_MENU_FRAME 
					+ '?session='+mw.escape(G.auth.session.key)
					+ '&authtime='+mw.escape(G.auth.session.authtime)
					+ '&server='+mw.escape(url),
					'test','chrome,resizable');
			}
			G.OpenILS.data.init();
		}

		G.auth.init();
		// XML_HTTP_SERVER will get reset to G.auth.controller.view.server_prompt.value

		/////////////////////////////////////////////////////////////////////////////

	} catch(E) {
		var error = "!! This software has encountered an error.  Please tell your friendly " +
			"system administrator or software developer the following:\n" + E + '\n';
		try { G.error.sdump('D_ERROR',error); } catch(E) { dump(error); }
		alert(error);
	}
	dump('exiting main_init()\n');
}

dump('exiting main/main.js\n');
