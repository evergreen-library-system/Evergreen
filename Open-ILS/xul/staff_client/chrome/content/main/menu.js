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
		return url;
	},

	'init' : function( params ) {

		var session = params['session'];
		var authtime = params['authtime'];
		urls.remote = params['server'];

		var obj = this;

		var cmd_map = {
			'cmd_broken' : [
				['oncommand'],
				function() { alert('Not Yet Implemented'); }
			],

			/* File Menu */
			'cmd_close_window' : [ 
				['oncommand'], 
				function() { obj.w.close(); } 
			],
			'cmd_new_window' : [
				['oncommand'],
				function() {
					obj.window.open(obj.url_prefix(urls.XUL_MENU_FRAME),'test' + 
						obj.window.appshell_name_increment++ ,'chrome'); 
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

			/* Search Menu */
			'cmd_patron_search' : [
				['oncommand'],
				function() {
					obj.set_tab(obj.url_prefix(urls.XUL_PATRON_DISPLAY)
						+ '?session='+obj.w.escape(session),{},{});
				}
			],
			'cmd_search_opac' : [
				['oncommand'],
				function() {
					var content_params = { 'session' : session, 'authtime' : authtime };
					obj.set_tab(obj.url_prefix(urls.XUL_OPAC_WRAPPER), {}, content_params);
				}
			],


			/* Circulation Menu */
			'cmd_circ_checkin' : [
				['oncommand'],
				function() { 
					obj.set_tab(obj.url_prefix(urls.XUL_CHECKIN) + '?session='+obj.w.escape(session),{},{});
				}
			],
			'cmd_circ_checkout' : [
				['oncommand'],
				function() { 
					obj.set_tab(obj.url_prefix(urls.XUL_PATRON_BARCODE_ENTRY) + '?session='+obj.w.escape(session),{},{});
				}
			],
			'cmd_circ_hold_capture' : [
				['oncommand'],
				function() { 
					obj.set_tab(obj.url_prefix(urls.XUL_HOLD_CAPTURE) + '?session='+obj.w.escape(session),{},{});
				}
			],


			/* Admin menu */
			'cmd_stat_cat_edit' : [
				['oncommand'],
				function() {
					obj.set_tab(obj.url_prefix(urls.XUL_STAT_CAT_EDIT) + '?ses='+obj.w.escape(session),{'tab_name':'Stat Cat Editor'},{});
				}
			],
			'cmd_non_cat_type_edit' : [
				['oncommand'],
				function() {
					obj.set_tab(obj.url_prefix(urls.XUL_NON_CAT_LABEL_EDIT) + '?ses='+obj.w.escape(session),{'tab_name':'Non-Cataloged Type Editor'},{});
				}
			],

			'cmd_test' : [
				['oncommand'],
				function() {
					var content_params = { 'session' : session, 'authtime' : authtime };
					obj.set_tab(obj.url_prefix(urls.XUL_OPAC_WRAPPER), {}, content_params);
				}
			],
			'cmd_test_html' : [
				['oncommand'],
				function() {
					obj.set_tab(obj.url_prefix(urls.TEST_HTML) + '?session='+obj.w.escape(session),{},{});
				}
			],
			'cmd_test_xul' : [
				['oncommand'],
				function() {
					obj.set_tab(obj.url_prefix(urls.TEST_XUL) + '?session='+obj.w.escape(session),{},{});
				}
			],
			'cmd_console' : [
				['oncommand'],
				function() {
					obj.set_tab(obj.url_prefix(urls.XUL_DEBUG_CONSOLE),{},{});
				}
			],
			'cmd_shell' : [
				['oncommand'],
				function() {
					obj.set_tab(obj.url_prefix(urls.XUL_DEBUG_SHELL),{},{});
				}
			],
			'cmd_xuleditor' : [
				['oncommand'],
				function() {
					obj.set_tab(obj.url_prefix(urls.XUL_DEBUG_XULEDITOR),{},{});
				}
			],
			'cmd_fieldmapper' : [
				['oncommand'],
				function() {
					obj.set_tab(obj.url_prefix(urls.XUL_DEBUG_FIELDMAPPER),{},{});
				}
			],
			'cmd_survey_wizard' : [
				['oncommand'],
				function() {
					obj.window.open(obj.url_prefix(urls.XUL_SURVEY_WIZARD)+ '?session='+obj.w.escape(session),'survey_wizard','chrome'); 
				}
			],

		};

		JSAN.use('util.controller');
		var cmd;
		obj.controller = new util.controller();
		obj.controller.init( { 'window_knows_me_by' : 'g.menu.controller', 'control_map' : cmd_map } );

		obj.controller.view.tabbox = obj.w.document.getElementById('main_tabbox');
		obj.controller.view.tabs = obj.controller.view.tabbox.firstChild;
		obj.controller.view.panels = obj.controller.view.tabbox.lastChild;

		obj.new_tab(null,{'focus':true},null);
	},

	'close_tab' : function () {
		var idx = this.controller.view.tabs.selectedIndex;
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
		if (!url) url = 'data:text/html,<h1>Hello World</h1>'
		if (!params) params = {};
		if (!content_params) content_params = {};
		var tc = this.find_free_tab();
		if (tc == -1) { return null; } // 9 tabs max
		var tab = this.controller.view.tabs.childNodes[ tc ];
		tab.hidden = false;
		try {
			if (params.focus) this.controller.view.tabs.selectedIndex = tc;
			params.index = tc;
			this.set_tab(url,params,content_params);
		} catch(E) {
			this.error.sdump('D_ERROR',E);
		}
	},

	'set_tab' : function(url,params,content_params) {
		if (!url) url = 'data:text/html,<h1>Hello World</h1>';
		if (!url.match(/:\/\//) && !url.match(/^data:/)) url = urls.remote + url;
		if (!params) params = {};
		if (!content_params) content_params = {};
		var obj = this;
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
