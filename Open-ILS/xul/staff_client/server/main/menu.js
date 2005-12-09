dump('entering main/menu.js\n');

if (typeof main == 'undefined') main = {};
main.menu = function () {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('main.window'); this.window = new main.window();

	this.w = window;
}

main.menu.prototype = {

	'init' : function( params ) {

		var session = params['session'];
		var authtime = params['authtime'];

		var obj = this;
		obj.view = {};

		obj.view.tabbox = obj.w.document.getElementById('main_tabbox');
		obj.view.tabs = obj.view.tabbox.firstChild;
		obj.view.panels = obj.view.tabbox.lastChild;

		var cmd_map = {
			'cmd_close_window' : [ 
				['command','keypress'], 
				function() { obj.w.close(); } 
			],
			'cmd_new_window' : [
				['command','keypress'],
				function() {
					obj.window.open(urls.remote_menu_frame,'test' + 
						obj.window.appshell_name_increment++ ,'chrome'); 
				}
			],
			'cmd_new_tab' : [
				['command','keypress'],
				function() { obj.new_tab(true); }
			],
			'cmd_close_tab' : [
				['command','keypress'],
				function() { obj.close_tab(); }
			],
			'cmd_broken' : [
				['command','keypress'],
				function() { alert('Not Yet Implemented'); }
			],
			'cmd_circ_checkout' : [
				['command','keypress'],
				function() { 
					obj.set_tab(urls.remote_patron_barcode_entry + '?session='+obj.w.escape(session),{},{'yadda':'yadda'});
				}
			],
			'cmd_search_opac' : [
				['command','keypress'],
				function() {
					var content_params = { 'authtoken' : session, 'authtime' : authtime };
					obj.error.sdump('D_MENU','session = ' + session);
					obj.error.sdump('D_MENU','authtime = ' + authtime);
					obj.error.sdump('D_MENU','content_params = ' + js2JSON(content_params));
					obj.set_tab(urls.xul_opac_wrapper,{},content_params);
				}
			]
		};

		for (var i in cmd_map) {
			var cmd = this.w.document.getElementById(i);
			if (cmd) {
				for (var j in cmd_map[i][0]) {
					cmd.addEventListener(cmd_map[i][0][j],cmd_map[i][1],false);
				}
			}
			obj.view[i] = cmd;
		}

		obj.new_tab(true);
	},

	'close_tab' : function () {
		var idx = this.view.tabs.selectedIndex;
		if (idx == 0) {
			try {
				this.view.tabs.advanceSelectedTab(+1);
			} catch(E) {
				this.error.sdump('D_TAB','failed tabs.advanceSelectedTab(+1):'+js2JSON(E) + '\n');
				try {
					this.view.tabs.advanceSelectedTab(-1);
				} catch(E) {
					this.error.sdump('D_TAB','failed again tabs.advanceSelectedTab(-1):'+
						js2JSON(E) + '\n');
				}
			}
		} else {
			try {
				this.view.tabs.advanceSelectedTab(-1);
			} catch(E) {
				this.error.sdump('D_TAB','failed tabs.advanceSelectedTab(-1):'+js2JSON(E) + '\n');
				try {
					this.view.tabs.advanceSelectedTab(+1);
				} catch(E) {
					this.error.sdump('D_TAB','failed again tabs.advanceSelectedTab(+1):'+
						js2JSON(E) + '\n');
				}
			}

		}
		
		this.error.sdump('D_TAB','\tnew tabbox.selectedIndex = ' + this.view.tabbox.selectedIndex + '\n');

		this.view.tabs.childNodes[ idx ].hidden = true;
		this.error.sdump('D_TAB','tabs.childNodes[ ' + idx + ' ].hidden = true;\n');

		// Make sure we keep at least one tab open.
		var tab_flag = true;
		for (var i = 0; i < this.view.tabs.childNodes.length; i++) {
			var tab = this.view.tabs.childNodes[i];
			if (!tab.hidden)
				tab_flag = false;
		}
		if (tab_flag) this.new_tab();
	},

	'find_free_tab' : function() {
		var last_not_hidden = -1;
		for (var i = 0; i<this.view.tabs.childNodes.length; i++) {
			var tab = this.view.tabs.childNodes[i];
			if (!tab.hidden)
				last_not_hidden = i;
		}
		if (last_not_hidden == this.view.tabs.childNodes.length - 1)
			last_not_hidden = -1;
		// If the one next to last_not_hidden is hidden, we want it.
		// Basically, we fill in tabs after existing tabs for as 
		// long as possible.
		var idx = last_not_hidden + 1;
		var candidate = this.view.tabs.childNodes[ idx ];
		if (candidate.hidden)
			return idx;
		// Alright, find the first hidden then
		for (var i = 0; i<this.view.tabs.childNodes.length; i++) {
			var tab = this.view.tabs.childNodes[i];
			if (tab.hidden)
				return i;
		}
		return -1;
	},

	'new_tab' : function(focus) {
		var tc = this.find_free_tab();
		if (tc == -1) { return null; } // 9 tabs max
		var tab = this.view.tabs.childNodes[ tc ];
		//tab.setAttribute('label','Tab ' + (tc + 1) );
		tab.hidden = false;
		try {
			if (focus) this.view.tabs.selectedIndex = tc;
			this.set_tab('data:text/html,<h1>Hello World</h1>',{ 'index' : tc });
		} catch(E) {
			this.error.sdump('D_ERROR',E);
		}
	},

	'set_tab' : function(url,params,content_params) {
		var idx = this.view.tabs.selectedIndex;
		if (params && typeof params.index != 'undefined') idx = params.index;
		var tab = this.view.tabs.childNodes[ idx ];
		var panel = this.view.panels.childNodes[ idx ];
		while ( panel.lastChild ) panel.removeChild( panel.lastChild );
		var frame = this.w.document.createElement('iframe');
		frame.setAttribute('flex','1');
		frame.setAttribute('src',url);
		panel.appendChild(frame);
		if (content_params) {
			try {
				netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
				//this.error.sdump('D_MENU', 'frame.contentWindow = ' + frame.contentWindow + '\n');
				frame.contentWindow.IAMXUL = true;
				frame.contentWindow.xulG = content_params;
				//this.error.sdump('D_MENU','content_params ' + js2JSON(content_params) +
				//'\nframe.contentWindow.xulG = ' + js2JSON(frame.contentWindow.xulG) );
			} catch(E) {
				this.error.sdump('D_ERROR', 'main.menu: ' + E);
			}
		}
		return frame;
	}

}

dump('exiting main/menu.js\n');
