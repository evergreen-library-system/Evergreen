dump('entering main/menu.js\n');

if (typeof main == 'undefined') main = {};
main.menu = function () {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.window'); this.window = new util.window();

	this.w = window;
}

main.menu.prototype = {

	'id_incr' : 0,

	'url_prefix' : function(url) {
		if (url.match(/^\//)) url = urls.remote + url;
		if (! url.match(/^(http|chrome):\/\//) && ! url.match(/^data:/) ) url = 'http://' + url;
		dump('url_prefix = ' + url + '\n');
		return url;
	},

	'init' : function( params ) {

		urls.remote = params['server'];

		var obj = this;

		JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});

		var cmd_map = {
			'cmd_broken' : [
				['oncommand'],
				function() { alert('Not Yet Implemented'); }
			],

			/* File Menu */
			'cmd_close_window' : [ 
				['oncommand'], 
				function() { window.close(); } 
			],
			'cmd_new_window' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.window.open(
						obj.url_prefix(urls.XUL_MENU_FRAME)
						+ '?server='+window.escape(urls.remote),
						'main' + obj.window.window_name_increment(),
						'chrome,resizable'); 
				}
			],
			'cmd_new_tab' : [
				['oncommand'],
				function() { obj.new_tab(null,{'focus':true},null); }
			],
			'cmd_close_tab' : [
				['oncommand'],
				function() { obj.close_tab(); }
			],
			'cmd_close_all_tabs' : [
				['oncommand'],
				function() { obj.close_all_tabs(); }
			],

			/* Edit Menu */
			'cmd_edit_copy_buckets' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_COPY_BUCKETS),{'tab_name':'Copy Buckets'},{});
				}
			],
			'cmd_edit_record_buckets' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_RECORD_BUCKETS),{'tab_name':'Record Buckets'},{});
				}
			],

			'cmd_replace_barcode' : [
				['oncommand'],
				function() {
					try {
						JSAN.use('util.network');
						var network = new util.network();

						var old_bc = window.prompt('Enter original barcode for the copy:','','Replace Barcode');
						if (!old_bc) return;
	
						var copy = network.simple_request('FM_ACP_RETRIEVE_VIA_BARCODE',[ old_bc ]);
						if (typeof copy.ilsevent != 'undefined') throw(copy); 
						if (!copy) throw(copy);
	
						// Why did I want to do this twice?  Because this copy is more fleshed?
						copy = network.simple_request('FM_ACP_RETRIEVE',[ copy.id() ]);
						if (typeof copy.ilsevent != 'undefined') throw(copy);
						if (!copy) throw(copy);
	
						var new_bc = window.prompt('Enter the replacement barcode for the copy:','','Replace Barcode');
	
						var test = network.simple_request('FM_ACP_RETRIEVE_VIA_BARCODE',[ ses(), new_bc ]);
						if (typeof test.ilsevent == 'undefined') {
							alert('Rename aborted.  Another copy has that barcode');
							return;
						}
						copy.barcode(new_bc); copy.ischanged('1');
						var r = network.simple_request('FM_ACP_FLESHED_BATCH_UPDATE', [ ses(), [ copy ] ]);
						if (typeof r.ilsevent != 'undefined') { if (r.ilsevent != 0) throw(r); }
					} catch(E) {
						obj.error.standard_unexpected_error_alert('Rename did not likely occur.',copy);
					}
				}
			],

			/* Search Menu */
			'cmd_patron_search' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_PATRON_DISPLAY),{},{});
				}
			],
			'cmd_search_opac' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					var content_params = { 'session' : ses(), 'authtime' : ses('authtime') };
					obj.set_tab(obj.url_prefix(urls.XUL_OPAC_WRAPPER), {'tab_name':'Catalog'}, content_params);
				}
			],
			'cmd_search_tcn' : [
				['oncommand'],
				function() {
					var tcn = prompt('What is the TCN or accession ID for the record?','','TCN Lookup');

					if (tcn) {
						JSAN.use('util.network');
						var network = new util.network();
						var robj = network.simple_request('FM_BRE_ID_SEARCH_VIA_TCN',[tcn]);
						if (robj.count != robj.ids.length) throw('FIXME -- FM_BRE_ID_SEARCH_VIA_TCN = ' + js2JSON(robj));
						if (robj.count == 0) {
							alert('TCN not found');
						} else {
							for (var i = 0; i < robj.count; i++) {
								var id = robj.ids[i];
								var opac_url = obj.url_prefix( urls.opac_rdetail ) + '?r=' + id;
								obj.data.stash_retrieve();
								var content_params = { 
									'session' : ses(), 
									'authtime' : ses('authtime'),
									'opac_url' : opac_url,
								};
								if (i == 0) {
									obj.set_tab(
										obj.url_prefix(urls.XUL_OPAC_WRAPPER), 
										{'tab_name':tcn}, 
										content_params
									);
								} else {
									obj.new_tab(
										obj.url_prefix(urls.XUL_OPAC_WRAPPER), 
										{'tab_name':tcn}, 
										content_params
									);
								}
							}
						}
					}
				}
			],
			'cmd_copy_status' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_COPY_STATUS),{},{});
				}
			],

			/* Circulation Menu */
			'cmd_patron_register' : [
				['oncommand'],
				function() {
								function spawn_editor(p) {
									var url = urls.XUL_PATRON_EDIT;
									var param_count = 0;
									for (var i in p) {
										if (param_count++ == 0) url += '?'; else url += '&';
										url += i + '=' + window.escape(p[i]);
									}
									var loc = obj.url_prefix( urls.XUL_REMOTE_BROWSER ) + '?url=' + window.escape( url );
									obj.new_tab(
										loc, 
										{}, 
										{ 
											'show_print_button' : true , 
											'tab_name' : 'Editing Related Patron' ,
											'passthru_content_params' : {
												'spawn_search' : function(s) { obj.spawn_search(s); },
												'spawn_editor' : spawn_editor,
											}
										}
									);
								}

					obj.data.stash_retrieve();
					var loc = obj.url_prefix( urls.XUL_REMOTE_BROWSER ) 
						+ '?url=' + window.escape( urls.XUL_PATRON_EDIT + '?ses=' + window.escape( ses() ) );
					obj.set_tab(
						loc, 
						{}, 
						{ 
							'show_print_button' : true , 
							'tab_name' : 'Register Patron' ,
							'passthru_content_params' : {
								'spawn_search' : function(s) { obj.spawn_search(s); },
								'spawn_editor' : spawn_editor,
							}
						}
					);
				}
			],
			'cmd_circ_checkin' : [
				['oncommand'],
				function() { 
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_CHECKIN),{},{});
				}
			],
			'cmd_circ_checkout' : [
				['oncommand'],
				function() { 
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_PATRON_BARCODE_ENTRY),{},{});
				}
			],
			'cmd_circ_hold_capture' : [
				['oncommand'],
				function() { 
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_CHECKIN)+'?hold_capture=1',{},{});
				}
			],
			'cmd_browse_holds' : [
				['oncommand'],
				function() { 
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_HOLDS_BROWSER),{ 'tab_name' : 'Hold Browser' },{});
				}
			],
			'cmd_browse_holds_shelf' : [
				['oncommand'],
				function() { 
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_HOLDS_BROWSER)+'?shelf=1',{ 'tab_name' : 'Holds Shelf' },{});
				}
			],
			'cmd_circ_hold_pull_list' : [
				['oncommand'],
				function() { 
					obj.data.stash_retrieve();
					var loc = urls.XUL_REMOTE_BROWSER + '?url=' + window.escape(
						obj.url_prefix(urls.XUL_HOLD_PULL_LIST) + '?ses='+window.escape(ses())
					);
					obj.set_tab( loc, {'tab_name':'On Shelf Pull List'}, { 'show_print_button' : true, } );
				}
			],

			'cmd_in_house_use' : [
				['oncommand'],
				function() { 
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_IN_HOUSE_USE),{},{});
				}
			],

			'cmd_standalone' : [
				['oncommand'],
				function() { 
					obj.set_tab(obj.url_prefix(urls.XUL_STANDALONE),{},{});
				}
			],

			'cmd_local_admin' : [
				['oncommand'],
				function() { 
					//obj.set_tab(obj.url_prefix(urls.XUL_LOCAL_ADMIN)+'?ses='+window.escape(ses())+'&session='+window.escape(ses()),{},{});
					var loc = urls.XUL_REMOTE_BROWSER + '?url=' + window.escape(
						urls.XUL_LOCAL_ADMIN+'?ses='+window.escape(ses())+'&session='+window.escape(ses())
					);
					obj.set_tab( 
						loc, 
						{'tab_name':'Local Administration', 'browser' : true }, 
						{ 'no_xulG' : false, 'show_nav_buttons' : true, 'show_print_button' : true } 
					);

				}
			],

			'cmd_reprint' : [
				['oncommand'],
				function() {
					try {
						JSAN.use('util.print'); var print = new util.print();
						print.reprint_last();
					} catch(E) {
						alert(E);
					}
				}
			],

			'cmd_retrieve_last_patron' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					if (!obj.data.last_patron) {
						alert('No patron visited yet this session.');
						return;
					}
					var url = obj.url_prefix( urls.XUL_PATRON_DISPLAY + '?id=' + window.escape( obj.data.last_patron ) );
					obj.set_tab( url );
				}
			],
			
			'cmd_retrieve_last_record' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					if (!obj.data.last_record) {
						alert('No record visited yet this session.');
						return;
					}
					var opac_url = obj.url_prefix( urls.opac_rdetail ) + '?r=' + obj.data.last_record;
					var content_params = {
						'session' : ses(),
						'authtime' : ses('authtime'),
						'opac_url' : opac_url,
					};
					obj.set_tab(
						obj.url_prefix(urls.XUL_OPAC_WRAPPER),
						{'tab_name':'Retrieving title...'},
						content_params
					);
				}
			],


			/* Cataloging Menu */
			'cmd_z39_50_import' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_Z3950_IMPORT),{},{});
				}
			],

			/* Admin menu */
			'cmd_manage_offline_xacts' : [
				['oncommand'],
				function() {
					obj.set_tab(obj.url_prefix(urls.XUL_OFFLINE_MANAGE_XACTS), {'tab_name':'Offline Transactions'}, {});
				}
			],
			'cmd_download_patrons' : [
				['oncommand'],
				function() {
					try {
						netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
						var x = new XMLHttpRequest();
						var url = 'http://' + XML_HTTP_SERVER + '/standalone/list.txt';
						x.open("GET",url,false);
						x.send(null);
						if (x.status == 200) {
							JSAN.use('util.file'); var file = new util.file('offline_patron_list');
							file.write_content('truncate',x.responseText);
							file.close();
							file = new util.file('offline_patron_list.date');
							file.write_content('truncate',new Date());
							file.close();
							alert('Download completed');
						} else {
							alert('There was a problem with the download.  The server returned a status ' + x.status + ' : ' + x.statusText);
						}
					} catch(E) {
						obj.error.standard_unexpected_error_alert('cmd_download_patrons',E);
					}
				}
			],
			'cmd_adv_user_edit' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_ADV_USER_BARCODE_ENTRY), {}, {});
				}
			],
			'cmd_print_list_template_edit' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_PRINT_LIST_TEMPLATE_EDITOR), {}, {});
				}
			],
			'cmd_stat_cat_edit' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_STAT_CAT_EDIT) + '?ses='+window.escape(ses()),{'tab_name':'Stat Cat Editor'},{});
				}
			],
			'cmd_non_cat_type_edit' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_NON_CAT_LABEL_EDIT) + '?ses='+window.escape(ses()),{'tab_name':'Non-Cataloged Type Editor'},{});
				}
			],
			'cmd_copy_location_edit' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_COPY_LOCATION_EDIT) + '?ses='+window.escape(ses()),{'tab_name':'Copy Location Editor'},{});
				}
			],
			'cmd_test' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					var content_params = { 'session' : ses(), 'authtime' : ses('authtime') };
					obj.set_tab(obj.url_prefix(urls.XUL_OPAC_WRAPPER), {}, content_params);
				}
			],
			'cmd_test_html' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.TEST_HTML) + '?ses='+window.escape(ses()),{ 'browser' : true },{});
				}
			],
			'cmd_test_xul' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.TEST_XUL) + '?ses='+window.escape(ses()),{ 'browser' : true },{});
				}
			],
			'cmd_console' : [
				['oncommand'],
				function() {
					obj.set_tab(obj.url_prefix(urls.XUL_DEBUG_CONSOLE),{'tab_name':'Console'},{});
				}
			],
			'cmd_shell' : [
				['oncommand'],
				function() {
					obj.set_tab(obj.url_prefix(urls.XUL_DEBUG_SHELL),{'tab_name':'JS Shell'},{});
				}
			],
			'cmd_xuleditor' : [
				['oncommand'],
				function() {
					obj.set_tab(obj.url_prefix(urls.XUL_DEBUG_XULEDITOR),{'tab_name':'XUL Editor'},{});
				}
			],
			'cmd_fieldmapper' : [
				['oncommand'],
				function() {
					obj.set_tab(obj.url_prefix(urls.XUL_DEBUG_FIELDMAPPER),{'tab_name':'Fieldmapper'},{});
				}
			],
			'cmd_survey_wizard' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.window.open(obj.url_prefix(urls.XUL_SURVEY_WIZARD),'survey_wizard','chrome'); 
				}
			],
			'cmd_public_opac' : [
				['oncommand'],
				function() {
					var loc = urls.XUL_REMOTE_BROWSER + '?url=' + window.escape(
						urls.remote
					);
					obj.set_tab( 
						loc, 
						{'tab_name':'OPAC', 'browser' : true}, 
						{ 'no_xulG' : true, 'show_nav_buttons' : true, 'show_print_button' : true } 
					);
				}
			],
			'cmd_clear_cache' : [
				['oncommand'],
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
			],
			'cmd_restore_all_tabs' : [
				['oncommand'],
				function() {
					var tabs = obj.controller.view.tabs;
					for (var i = 0; i < tabs.childNodes.length; i++) {
						tabs.childNodes[i].hidden = false;
					}
				}
			],
			'cmd_shutdown' : [
				['oncommand'],
				function() {
					var windowManager = Components.classes["@mozilla.org/appshell/window-mediator;1"].getService();
					var windowManagerInterface = windowManager.QueryInterface(Components.interfaces.nsIWindowMediator);
					var enumerator = windowManagerInterface.getEnumerator(null);

					var w; // close all other windows
					while ( w = enumerator.getNext() ) {
						if (w != window) w.close();
					
					}
					window.close();
				}
			],
		};

		JSAN.use('util.controller');
		var cmd;
		obj.controller = new util.controller();
		obj.controller.init( { 'window_knows_me_by' : 'g.menu.controller', 'control_map' : cmd_map } );

		obj.controller.view.tabbox = window.document.getElementById('main_tabbox');
		obj.controller.view.tabs = obj.controller.view.tabbox.firstChild;
		obj.controller.view.panels = obj.controller.view.tabbox.lastChild;

		obj.new_tab(null,{'focus':true},null);

		obj.init_tab_focus_handlers();
	},

	'spawn_search' : function(s) {
		var obj = this;
		obj.error.sdump('D_TRACE', 'Editor would like to search for: ' + js2JSON(s) ); 
		obj.data.stash_retrieve();
		var loc = obj.url_prefix(urls.XUL_PATRON_DISPLAY);
		loc += '?doit=1&query=' + window.escape(js2JSON(s));
		obj.new_tab( loc, {}, {} );
	},

	'init_tab_focus_handlers' : function() {
		var obj = this;
		for (var i = 0; i < obj.controller.view.tabs.childNodes.length; i++) {
			var tab = obj.controller.view.tabs.childNodes[i];
			var panel = obj.controller.view.panels.childNodes[i];
			tab.addEventListener(
				'command',
				function(p) {
					return function() {
						try {
								if (p
									&& p.firstChild 
									&& ( p.firstChild.nodeName == 'iframe' || p.firstChild.nodeName == 'browser' )
									&& p.firstChild.contentWindow 
								) {
									if (typeof p.firstChild.contentWindow.default_focus == 'function') {
										p.firstChild.contentWindow.default_focus();
									} else {
										//p.firstChild.contentWindow.firstChild.focus();
									}
								}
						} catch(E) {
							obj.error.sdump('D_ERROR','init_tab_focus_handler: ' + js2JSON(E));
						}
					}
				}(panel),
				false
			);
		}
	},

	'close_all_tabs' : function() {
		var obj = this;
		try {
			var count = obj.controller.view.tabs.childNodes.length;
			for (var i = 0; i < count; i++) obj.close_tab();
			setTimeout( function(){ obj.controller.view.tabs.firstChild.focus(); }, 0);
		} catch(E) {
			obj.error.standard_unexpected_error_alert('Error closing all tabs',E);
		}
	},

	'close_tab' : function () {
		var idx = this.controller.view.tabs.selectedIndex;
		var tab = this.controller.view.tabs.childNodes[idx];
		tab.setAttribute('label','Tab ' + (idx+1));
		if (idx == 0) {
			try {
				this.controller.view.tabs.advanceSelectedTab(+1);
			} catch(E) {
				this.error.sdump('D_TAB','failed tabs.advanceSelectedTab(+1):'+js2JSON(E) + '\n');
				try {
					this.controller.view.tabs.advanceSelectedTab(-1);
				} catch(E) {
					this.error.sdump('D_TAB','failed again tabs.advanceSelectedTab(-1):'+
						js2JSON(E) + '\n');
				}
			}
		} else {
			try {
				this.controller.view.tabs.advanceSelectedTab(-1);
			} catch(E) {
				this.error.sdump('D_TAB','failed tabs.advanceSelectedTab(-1):'+js2JSON(E) + '\n');
				try {
					this.controller.view.tabs.advanceSelectedTab(+1);
				} catch(E) {
					this.error.sdump('D_TAB','failed again tabs.advanceSelectedTab(+1):'+
						js2JSON(E) + '\n');
				}
			}

		}
		
		this.error.sdump('D_TAB','\tnew tabbox.selectedIndex = ' + this.controller.view.tabbox.selectedIndex + '\n');

		this.controller.view.tabs.childNodes[ idx ].hidden = true;
		this.error.sdump('D_TAB','tabs.childNodes[ ' + idx + ' ].hidden = true;\n');

		// Make sure we keep at least one tab open.
		var tab_flag = true;
		for (var i = 0; i < this.controller.view.tabs.childNodes.length; i++) {
			var tab = this.controller.view.tabs.childNodes[i];
			if (!tab.hidden)
				tab_flag = false;
		}
		if (tab_flag) {
			this.controller.view.tabs.selectedIndex = 0;
			this.new_tab(); 
		}
	},

	'find_free_tab' : function() {
		var last_not_hidden = -1;
		for (var i = 0; i<this.controller.view.tabs.childNodes.length; i++) {
			var tab = this.controller.view.tabs.childNodes[i];
			if (!tab.hidden)
				last_not_hidden = i;
		}
		if (last_not_hidden == this.controller.view.tabs.childNodes.length - 1)
			last_not_hidden = -1;
		// If the one next to last_not_hidden is hidden, we want it.
		// Basically, we fill in tabs after existing tabs for as 
		// long as possible.
		var idx = last_not_hidden + 1;
		var candidate = this.controller.view.tabs.childNodes[ idx ];
		if (candidate.hidden)
			return idx;
		// Alright, find the first hidden then
		for (var i = 0; i<this.controller.view.tabs.childNodes.length; i++) {
			var tab = this.controller.view.tabs.childNodes[i];
			if (tab.hidden)
				return i;
		}
		return -1;
	},

	'new_tab' : function(url,params,content_params) {
		var tc = this.find_free_tab();
		if (tc == -1) { return null; } // 9 tabs max
		var tab = this.controller.view.tabs.childNodes[ tc ];
		tab.hidden = false;
		if (!content_params) content_params = {};
		if (!params) params = { 'tab_name' : 'Tab ' + (tc+1) };
		if (!params.nofocus) params.focus = true; /* make focus the default */
		try {
			if (params.focus) this.controller.view.tabs.selectedIndex = tc;
			params.index = tc;
			this.set_tab(url,params,content_params);
		} catch(E) {
			this.error.sdump('D_ERROR',E);
		}
	},

	'set_tab' : function(url,params,content_params) {
		var obj = this;
		if (!url) url = '/xul/server/';
		if (!url.match(/:\/\//) && !url.match(/^data:/)) url = urls.remote + url;
		if (!params) params = {};
		if (!content_params) content_params = {};
		var idx = this.controller.view.tabs.selectedIndex;
		if (params && typeof params.index != 'undefined') idx = params.index;
		var tab = this.controller.view.tabs.childNodes[ idx ];
		var panel = this.controller.view.panels.childNodes[ idx ];
		while ( panel.lastChild ) panel.removeChild( panel.lastChild );

		content_params.new_tab = function(a,b,c) { return obj.new_tab(a,b,c); };
		content_params.set_tab = function(a,b,c) { return obj.set_tab(a,b,c); };
		content_params.set_tab_name = function(name) { tab.setAttribute('label',(idx + 1) + ' ' + name); };
		content_params.open_chrome_window = function(a,b,c) { return obj.window.open(a,b,c); };
		content_params.url_prefix = function(url) { return obj.url_prefix(url); };
		if (params && params.tab_name) content_params.set_tab_name( params.tab_name );
		
		var frame;
		try {
			if (params && typeof params.browser != 'undefined') {
				obj.id_incr++;
				frame = this.w.document.createElement('browser');
				frame.setAttribute('flex','1');
				frame.setAttribute('type','content');
				frame.setAttribute('id','frame_'+obj.id_incr);
				panel.appendChild(frame);
				try {
					dump('creating browser with src = ' + url + '\n');
					JSAN.use('util.browser');
					var b = new util.browser();
					b.init(
						{
							'url' : url,
							'push_xulG' : true,
							'alt_print' : false,
							'browser_id' : 'frame_'+obj.id_incr,
							'passthru_content_params' : content_params,
						}
					);
				} catch(E) {
					alert(E);
				}
			} else {
				frame = this.w.document.createElement('iframe');
				frame.setAttribute('flex','1');
				panel.appendChild(frame);
				dump('creating iframe with src = ' + url + '\n');
				frame.setAttribute('src',url);
				try {
					netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
					var cw = frame.contentWindow;
					if (typeof cw.wrappedJSObject != 'undefined') cw = cw.wrappedJSObject;
					cw.IAMXUL = true;
					cw.xulG = content_params;
				} catch(E) {
					this.error.sdump('D_ERROR', 'main.menu: ' + E);
				}
			}
		} catch(E) {
			this.error.sdump('D_ERROR', 'main.menu:2: ' + E);
			alert('pause for error');
		}

		return frame;
	}

}

dump('exiting main/menu.js\n');
