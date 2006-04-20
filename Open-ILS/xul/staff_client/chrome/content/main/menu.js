dump('entering main/menu.js\n');

if (typeof main == 'undefined') main = {};
main.menu = function () {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.window'); this.window = new util.window();

	this.w = window;
}

main.menu.prototype = {

	'url_prefix' : function(url) {
		if (url.match(/^\//)) url = urls.remote + url;
		if (! url.match(/^(http|chrome):\/\//) && ! url.match(/^data:/) ) url = 'http://' + url;
		dump('url_prefix = ' + url + '\n');
		return url;
	},

	'init' : function( params ) {

		/* var session = params['session']; */
		var authtime = params['authtime'];
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
						+ '?session='+window.escape(obj.data.session) 
						+ '&authtime='+window.escape(authtime) 
						+ '&server='+window.escape(urls.remote),
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

			/* Edit Menu */
			'cmd_edit_copy_buckets' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_COPY_BUCKETS)
						+ '?session='+window.escape(obj.data.session),{'tab_name':'Copy Buckets'},{});
				}
			],

			/* Search Menu */
			'cmd_patron_search' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_PATRON_DISPLAY)
						+ '?session='+window.escape(obj.data.session),{},{});
				}
			],
			'cmd_search_opac' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					var content_params = { 'session' : obj.data.session, 'authtime' : authtime };
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
									'session' : obj.data.session, 
									'authtime' : authtime,
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
					obj.set_tab(obj.url_prefix(urls.XUL_COPY_STATUS)
						+ '?session='+window.escape(obj.data.session),{},{});
				}
			],

			/* Circulation Menu */
			'cmd_patron_register' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					var loc = obj.url_prefix( urls.XUL_REMOTE_BROWSER ) 
						+ '?url=' + window.escape( urls.XUL_PATRON_EDIT + '?ses=' + window.escape( obj.data.session ) );
					obj.set_tab(
						loc, 
						{}, 
						{ 
							'show_print_button' : true , 
							'tab_name' : 'Register Patron' ,
							'passthru_content_params' : {
								'spawn_search' : function(s) { obj.spawn_search(s); }
							}
						}
					);
				}
			],
			'cmd_circ_checkin' : [
				['oncommand'],
				function() { 
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_CHECKIN) + '?session='+window.escape(obj.data.session),{},{});
				}
			],
			'cmd_circ_checkout' : [
				['oncommand'],
				function() { 
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_PATRON_BARCODE_ENTRY) + '?session='+window.escape(obj.data.session),{},{});
				}
			],
			/*
			'cmd_circ_hold_capture' : [
				['oncommand'],
				function() { 
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_HOLD_CAPTURE) + '?session='+window.escape(obj.data.session),{},{});
				}
			],
			*/
			'cmd_browse_holds' : [
				['oncommand'],
				function() { 
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_HOLDS_BROWSER) + '?session='+window.escape(obj.data.session),{ 'tab_name' : 'Hold Browser' },{});
				}
			],
			'cmd_circ_hold_pull_list' : [
				['oncommand'],
				function() { 
					obj.data.stash_retrieve();
					var loc = urls.XUL_REMOTE_BROWSER + '?url=' + window.escape(
						obj.url_prefix(urls.XUL_HOLD_PULL_LIST) + '?ses='+window.escape(obj.data.session)
					);
					obj.set_tab( loc, {'tab_name':'On Shelf Pull List'}, { 'show_print_button' : true, } );
				}
			],

			'cmd_in_house_use' : [
				['oncommand'],
				function() { 
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_IN_HOUSE_USE) + '?session='+window.escape(obj.data.session),{},{});
				}
			],

			'cmd_standalone' : [
				['oncommand'],
				function() { 
					obj.set_tab(obj.url_prefix(urls.XUL_STANDALONE),{},{});
				}
			],

			/* Cataloging Menu */
			'cmd_z39_50_import' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_Z3950_IMPORT) + '?session='+window.escape(obj.data.session),{},{});
				}
			],

			/* Admin menu */
			'cmd_manage_offline_xacts' : [
				['oncommand'],
				function() {
					obj.set_tab(obj.url_prefix(urls.XUL_OFFLINE_MANAGE_XACTS), {}, {});
				}
			],

			'cmd_adv_user_edit' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_ADV_USER_BARCODE_ENTRY) + '?session=' + window.escape(obj.data.session), {}, {});
				}
			],
			'cmd_print_list_template_edit' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_PRINT_LIST_TEMPLATE_EDITOR) + '?session=' + window.escape(obj.data.session), {}, {});
				}
			],
			'cmd_stat_cat_edit' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_STAT_CAT_EDIT) + '?ses='+window.escape(obj.data.session),{'tab_name':'Stat Cat Editor'},{});
				}
			],
			'cmd_non_cat_type_edit' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_NON_CAT_LABEL_EDIT) + '?ses='+window.escape(obj.data.session),{'tab_name':'Non-Cataloged Type Editor'},{});
				}
			],
			'cmd_copy_location_edit' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.XUL_COPY_LOCATION_EDIT) + '?ses='+window.escape(obj.data.session),{'tab_name':'Copy Location Editor'},{});
				}
			],
			'cmd_test' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					var content_params = { 'session' : obj.data.session, 'authtime' : authtime };
					obj.set_tab(obj.url_prefix(urls.XUL_OPAC_WRAPPER), {}, content_params);
				}
			],
			'cmd_test_html' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.TEST_HTML) + '?session='+window.escape(obj.data.session),{},{});
				}
			],
			'cmd_test_xul' : [
				['oncommand'],
				function() {
					obj.data.stash_retrieve();
					obj.set_tab(obj.url_prefix(urls.TEST_XUL) + '?session='+window.escape(obj.data.session),{},{});
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
					obj.window.open(obj.url_prefix(urls.XUL_SURVEY_WIZARD)+ '?session='+window.escape(obj.data.session),'survey_wizard','chrome'); 
				}
			],
			'cmd_public_opac' : [
				['oncommand'],
				function() {
					var loc = urls.XUL_BROWSER + '?url=' + window.escape(
						urls.remote
					);
					obj.set_tab( 
						loc, 
						{'tab_name':'OPAC'}, 
						{ 'no_xulG' : true, 'show_nav_buttons' : true, 'show_print_button' : true, } 
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
		var loc = obj.url_prefix(urls.XUL_PATRON_DISPLAY) + '?session='+window.escape(obj.data.session);
		loc += '&doit=1&query=' + window.escape(js2JSON(s));
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
									&& p.firstChild.nodeName == 'iframe' 
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
		if (tab_flag) this.new_tab();
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
		
		var frame = this.w.document.createElement('iframe');
		frame.setAttribute('flex','1');
		frame.setAttribute('src',url);
		panel.appendChild(frame);

		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			frame.contentWindow.IAMXUL = true;
			frame.contentWindow.xulG = content_params;
		} catch(E) {
			this.error.sdump('D_ERROR', 'main.menu: ' + E);
		}
		return frame;
	}

}

dump('exiting main/menu.js\n');
