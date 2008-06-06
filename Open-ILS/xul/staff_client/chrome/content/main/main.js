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
			G.data.session = { 'key' : G.auth.session.key, 'auth' : G.auth.session.authtime }; G.data.stash('session');
			G.data.stash_retrieve();

			grant_perms(url);

			var xulG = {
				'auth' : G.auth,
				'url' : url,
				'window' : G.window,
			}

			if (G.data.ws_info && G.data.ws_info[G.auth.controller.view.server_prompt.value]) {
				JSAN.use('util.widgets');
				var deck = document.getElementById('progress_space');
				util.widgets.remove_children( deck );
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
                    var file2 = new util.file('');
					var f = file2.pick_file( { 'mode' : 'save', 'title' : 'Save Transaction File As' } );
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
                            file.close();
                            rename_file();
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
                    var file2 = new util.file('');
					var f = file2.pick_file( { 'mode' : 'open', 'title' : 'Import Transaction File'} );
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

		var version = '/xul/server/'.split(/\//)[2];
		if (version == 'server') {
			version = 'versionless debug build';
			document.getElementById('debug_gb').hidden = false;
		}
		//var x = document.getElementById('version_label');
		//x.setAttribute('value','Build ID: ' + version);
		var x = document.getElementById('about_btn');
		x.setAttribute('label','About this client...');
		x.addEventListener(
			'command',
			function() {
				try { 
					G.window.open('about.html','about','chrome,resizable,width=800,height=600');
				} catch(E) { alert(E); }
			}, 
			false
		);

		var y = document.getElementById('new_window_btn');
		y.setAttribute('label','Open New Window');
		y.addEventListener(
			'command',
			function() {
				if (G.data.session) {
					try {
						G.window.open('chrome://open_ils_staff_client/content/main/menu_frame.xul?server=' +
							G.data.server,'main','chrome,resizable' );

					} catch(E) { alert(E); }
				} else {
					alert ('Please login first!')
				}
			},
			false
		);

		if ( found_ws_info_in_Achrome() ) {
			//var hbox = x.parentNode; var b = document.createElement('button'); 
			//b.setAttribute('label','Migrate legacy settings'); hbox.appendChild(b);
			//b.addEventListener(
			//	'command',
			//	function() {
			//		try {
			//			handle_migration();
			//		} catch(E) { alert(E); }
			//	},
			//	false
			//);
			if (window.confirm('This version of the staff client stores local settings in a different location than your previous installation.  Should we attempt to migrate these settings?')) {
				setTimeout( function() { handle_migration(); }, 0 );
			}
		}

	} catch(E) {
		var error = "!! This software has encountered an error.  Please tell your friendly " +
			"system administrator or software developer the following:\n" + E + '\n';
		try { G.error.sdump('D_ERROR',error); } catch(E) { dump(error); }
		alert(error);
	}
	dump('exiting main_init()\n');
}

function found_ws_info_in_Achrome() {
	JSAN.use('util.file');
	var f = new util.file();
	var f_in_chrome = f.get('ws_info','chrome');
	var path = f_in_chrome.exists() ? f_in_chrome.path : false;
	f.close();
	return path;
}

function found_ws_info_in_Uchrome() {
	JSAN.use('util.file');
	var f = new util.file();
	var f_in_uchrome = f.get('ws_info','uchrome');
	var path = f_in_uchrome.exists() ? f_in_uchrome.path : false;
	f.close();
	return path;
}

function handle_migration() {
	if ( found_ws_info_in_Uchrome() ) {
		alert('WARNING: Unable to migrate legacy settings.  The settings and configuration files appear to exist in multiple locations.\n'
			+ 'To resolve manually, please consider:\n\t' + found_ws_info_in_Uchrome() + '\n'
			+ 'which is in the directory where we want to store settings for the current OS user, and:\n\t'
			+ found_ws_info_in_Achrome() + '\nwhich is where we used to store such information.\n'
		);
	} else {
		var dirService = Components.classes["@mozilla.org/file/directory_service;1"].getService( Components.interfaces.nsIProperties );
		var f_new = dirService.get( "UChrm", Components.interfaces.nsIFile );
		var f_old = dirService.get( "AChrom", Components.interfaces.nsIFile );
		f_old.append(myPackageDir); f_old.append("content"); f_old.append("conf"); 
		if (window.confirm("Move the settings and configuration files from\n" + f_old.path + "\nto\n" + f_new.path + "?")) {
			var files = f_old.directoryEntries;
			while (files.hasMoreElements()) {
				var file = files.getNext();
				var file2 = file.QueryInterface( Components.interfaces.nsILocalFile );
				try {
					file2.moveTo( f_new, '' );
				} catch(E) {
					alert('Error trying to move ' + file2.path + ' to directory ' + f_new.path + '\n');
				}
			}
			location.href = location.href;
		}
	}
}

function rename_file() {
    netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");

    try {

        JSAN.use('util.file'); 
        var pending = new util.file('pending_xacts');
        if ( !pending._file.exists() ) { throw("Can't rename a non-existent file"); }
        var transition_filename = 'pending_xacts_' + new Date().getTime();
        var count = 0;
        var file = new util.file(transition_filename);
        while (file._file.exists()) {
            transition_filename = 'pending_xacts_' + new Date().getTime();
            file = new util.file(transition_filename);
            if (count++>100) throw("Taking too long to find a unique filename.");
        }
        pending._file.moveTo(null,transition_filename);

    } catch(E) {
        alert('Error renaming xact file\n'+E);
    }
}


dump('exiting main/main.js\n');
