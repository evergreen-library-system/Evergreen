dump('entering main/main.js\n');

function grant_perms(url) {
	var perms = "UniversalXPConnect UniversalPreferencesWrite UniversalBrowserWrite UniversalPreferencesRead UniversalBrowserRead UniversalFileRead";
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

function clear_the_cache() {
	try {
		var cacheClass 		= Components.classes["@mozilla.org/network/cache-service;1"];
		var cacheService	= cacheClass.getService(Components.interfaces.nsICacheService);
		cacheService.evictEntries(Components.interfaces.nsICache.STORE_ON_DISK);
		cacheService.evictEntries(Components.interfaces.nsICache.STORE_IN_MEMORY);
	} catch(E) {
		dump(E+'\n');alert(E);
	}
}

function pick_file(mode) {
	var nsIFilePicker = Components.interfaces.nsIFilePicker;
	var fp = Components.classes["@mozilla.org/filepicker;1"].createInstance( nsIFilePicker );
	fp.init( 
		window, 
		mode == 'open' ? "Import Transaction File" : "Save Transaction File As", 
		mode == 'open' ? nsIFilePicker.modeOpen : nsIFilePicker.modeSave
	);
	fp.appendFilters( nsIFilePicker.filterAll );
	if ( fp.show( ) == nsIFilePicker.returnOK && fp.file ) {
		return fp.file;
	} else {
		return null;
	}
}

function main_init() {
	dump('entering main_init()\n');
	try {
		clear_the_cache();

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
			G.ws_info = G.file.get_object(); G.file.close();
		} catch(E) {
			G.ws_info = {};
		}
		G.data.ws_info = G.ws_info; G.data.stash('ws_info');

		G.auth.on_login = function() {

			var url = G.auth.controller.view.server_prompt.value || urls.remote;

			G.data.server_unadorned = url; G.data.stash('server_unadorned'); G.data.stash_retrieve();

			if (! url.match( '^http://' ) ) url = 'http://' + url;

			G.data.server = url; G.data.stash('server'); 
			G.data.session = G.auth.session.key; G.data.stash('session');
			G.data.stash_retrieve();

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

		G.auth.on_standalone = function() {
			try {
				G.window.open(urls.XUL_STANDALONE,'Offline','chrome,resizable');
			} catch(E) {
				alert(E);
			}
		}

		G.auth.on_standalone_export = function() {
			try {
				JSAN.use('util.file'); var file = new util.file('pending_xacts');
				if (file._file.exists()) {
					var f = pick_file('save');
					if (f) {
						if (f.exists()) {
							var r = G.error.yns_alert(
								'Would you like to overwrite the existing file ' + f.leafName + '?',
								'Transaction Export Warning',
								'Yes',
								'No',
								null,
								'Check here to confirm this message'
							);
							if (r != 0) { file.close(); return; }
						}
						var e_file = new util.file(''); e_file._file = f;
						e_file.write_content( 'truncate', file.get_content() );
						e_file.close();
						var r = G.error.yns_alert(
							'Your transactions have been successfully exported to file ' + f.leafName + '.\n\nWe strongly recommend that you now purge the transactions from this staff client.  Would you like for us to do this?',
							'Transaction Export Successful',
							'Yes',
							'No',
							null,
							'Check here to confirm this message'
						);
						if (r == 0) {
							var count = 0;
							var filename = 'pending_xacts_exported_' + new Date().getTime();
							var t_file = new util.file(filename);
							while (t_file._file.exists()) {
								filename = 'pending_xacts_' + new Date().getTime() + '.exported';
								t_file = new util.file(filename);
								if (count++>100) throw('Error purging transactions:  Taking too long to find a unique filename for archival.');
							}
							file._file.moveTo(null,filename);
						} else {
							alert('Please note that you now have two sets of identical transactions.  Unless the set you just exported is soley for archival purposes, we run the risk of duplicate transactions being processed on the server.');
						}
					} else {
						alert('No filename chosen.  Or a bug where you tried to overwrite an existing file.');
					}
				} else {
					alert('There are no outstanding transactions to export.');
				}
				file.close();
			} catch(E) {
				alert(E);
			}
		}

		G.auth.on_standalone_import = function() {
			try {
				JSAN.use('util.file'); var file = new util.file('pending_xacts');
				if (file._file.exists()) {
					alert('There are already outstanding transactions on this staff client.  Upload these first.');
				} else {
					var f = pick_file('open');
					if (f && f.exists()) {
						var i_file = new util.file(''); i_file._file = f;
						file.write_content( 'truncate', i_file.get_content() );
						i_file.close();
						var r = G.error.yns_alert(
							'Your transactions have been successfully migrated to this staff client.\n\nWe recommend that you delete the external copy.  Would you like for us to delete ' + f.leafName + '?',
							'Transaction Import Successful',
							'Yes',
							'No',
							null,
							'Check here to confirm this message'
						);
						if (r == 0) {
							f.remove(false);
						}
					}
				}
				file.close();
			} catch(E) {
				alert(E);
			}
		}

		G.auth.on_debug = function(action) {
			switch(action) {
				case 'js_console' :
					G.window.open(urls.XUL_DEBUG_CONSOLE,'testconsole','chrome,resizable');
				break;
				case 'clear_cache' :
					clear_the_cache();
					alert('cache cleared');
				break;
				default:
					alert('debug the debug :D');
				break;
			}
		}

		G.auth.init();
		// XML_HTTP_SERVER will get reset to G.auth.controller.view.server_prompt.value

		/////////////////////////////////////////////////////////////////////////////

		var x = document.getElementById('version_label');
		var version = '/xul/server/'.split(/\//)[2];
		if (version == 'server') {
			version = 'versionless debug build';
			document.getElementById('debug_gb').hidden = false;
		}
		x.setAttribute('value','Build ID: ' + version);

	} catch(E) {
		var error = "!! This software has encountered an error.  Please tell your friendly " +
			"system administrator or software developer the following:\n" + E + '\n';
		try { G.error.sdump('D_ERROR',error); } catch(E) { dump(error); }
		alert(error);
	}
	dump('exiting main_init()\n');
}

dump('exiting main/main.js\n');
