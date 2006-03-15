dump('entering main/main.js\n');

function grant_perms(url) {
	var perms = "UniversalXPConnect UniversalPreferencesWrite UniversalBrowserWrite UniversalPreferencesRead UniversalBrowserRead";
	dump('Granting ' + perms + ' to ' + url + '\n');
	var pref = Components.classes["@mozilla.org/preferences-service;1"]
		.getService(Components.interfaces.nsIPrefBranch);
	if (pref) {
		pref.setCharPref("capability.principal.codebase.p0.granted", perms);
		pref.setCharPref("capability.principal.codebase.p0.id", url);
		pref.setBoolPref("dom.disable_open_during_load",false);
		pref.setBoolPref("browser.popups.showPopupBlocker",false);
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
		G =  {};

		JSAN.use('util.error');
		G.error = new util.error();
		G.error.sdump('D_ERROR','Testing');

		JSAN.use('util.window');
		G.window = new util.window();

		//G.window.open(urls.XUL_DEBUG_CONSOLE,'testconsole','chrome,resizable');

		JSAN.use('auth.controller');
		G.auth = new auth.controller( { 'window' : mw } );

		JSAN.use('OpenILS.data');
		G.data = new OpenILS.data()
		G.data.on_error = G.auth.logoff;
		G.data.entities = entities;
		G.data.stash('entities');

		JSAN.use('util.file');
		G.file = new util.file();
		try {
			G.file.get('ws_info');
			G.ws_info = G.file.get_object();
		} catch(E) {
			G.ws_info = {};
		}
		G.data.ws_info = G.ws_info; G.data.stash('ws_info');

		G.auth.on_login = function() {

			var url = G.auth.controller.view.server_prompt.value || urls.remote;
			if (! url.match( '^http://' ) ) url = 'http://' + url;

			G.data.server = url; G.data.stash('server'); G.data.stash_retrieve();

			grant_perms(url);

			var xulG = {
				'auth' : G.auth,
				'url' : url,
				'window' : G.window,
			}

			if (G.data.ws_info && G.data.ws_info[G.auth.controller.view.server_prompt.value]) {
				var deck = document.getElementById('main_deck');
				var iframe = document.createElement('iframe'); deck.appendChild(iframe);
				iframe.setAttribute( 'src', url + '/xul/server/main/data.xul' );
				iframe.contentWindow.xulG = xulG;
			} else {
				xulG.file = G.file;
				var deck = G.auth.controller.view.ws_deck;
				JSAN.use('util.widgets'); util.widgets.remove_children('ws_deck');
				var iframe = document.createElement('iframe'); deck.appendChild(iframe);
				iframe.setAttribute( 'src', url + '/xul/server/main/ws_info.xul' );
				iframe.contentWindow.xulG = xulG;
				deck.selectedIndex = deck.childNodes.length - 1;
			}
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
