dump('entering main/menu.js\n');

if (typeof main == 'undefined') main = {};
main.menu = function () {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('main.window'); this.window = new main.window();

	this.w = window;
}

main.menu.prototype = {

	'init' : function() {

		var obj = this;

		obj.tabbox = obj.w.document.getElementById('main_tabbox');
		obj.tabs = obj.tabbox.firstChild;
		obj.panels = obj.tabbox.lastChild;

		var cmd_map = {
			'cmd_close_window' : function() { obj.w.close(); },
			'cmd_new_window' : function() {
				obj.window.open('/xul/server/main/menu_frame.xul','test' + 
					obj.window.appshell_name_increment++ ,'chrome'); 
			},
			'cmd_new_tab' : function() { obj.new_tab(true); },
			'cmd_close_tab' : function() { obj.close_tab(); },
			'cmd_broken' : function() { alert('Not Yet Implemented'); },
			'cmd_circ_checkout' : function() { 
				obj.set_tab('/xul/server/patron/patron_barcode_entry.xul');
			}
		};

		for (var i in cmd_map) {
			var cmd = this.w.document.getElementById(i);
			if (cmd) {
				cmd.addEventListener('command',cmd_map[i],false);
				cmd.addEventListener('keypress',cmd_map[i],false);
			}
		}

		obj.new_tab(true);
	},

	'close_tab' : function () {
		var idx = this.tabs.selectedIndex;
		if (idx == 0) {
			try {
				this.tabs.advanceSelectedTab(+1);
			} catch(E) {
				this.error.sdump('D_TAB','failed tabs.advanceSelectedTab(+1):'+js2JSON(E) + '\n');
				try {
					this.tabs.advanceSelectedTab(-1);
				} catch(E) {
					this.error.sdump('D_TAB','failed again tabs.advanceSelectedTab(-1):'+
						js2JSON(E) + '\n');
				}
			}
		} else {
			try {
				this.tabs.advanceSelectedTab(-1);
			} catch(E) {
				this.error.sdump('D_TAB','failed tabs.advanceSelectedTab(-1):'+js2JSON(E) + '\n');
				try {
					this.tabs.advanceSelectedTab(+1);
				} catch(E) {
					this.error.sdump('D_TAB','failed again tabs.advanceSelectedTab(+1):'+
						js2JSON(E) + '\n');
				}
			}

		}
		
		this.error.sdump('D_TAB','\tnew tabbox.selectedIndex = ' + this.tabbox.selectedIndex + '\n');

		this.tabs.childNodes[ idx ].hidden = true;
		this.error.sdump('D_TAB','tabs.childNodes[ ' + idx + ' ].hidden = true;\n');

		// Make sure we keep at least one tab open.
		var tab_flag = true;
		for (var i = 0; i < this.tabs.childNodes.length; i++) {
			var tab = this.tabs.childNodes[i];
			if (!tab.hidden)
				tab_flag = false;
		}
		if (tab_flag) this.new_tab();
	},

	'find_free_tab' : function() {
		var last_not_hidden = -1;
		for (var i = 0; i<this.tabs.childNodes.length; i++) {
			var tab = this.tabs.childNodes[i];
			if (!tab.hidden)
				last_not_hidden = i;
		}
		if (last_not_hidden == this.tabs.childNodes.length - 1)
			last_not_hidden = -1;
		// If the one next to last_not_hidden is hidden, we want it.
		// Basically, we fill in tabs after existing tabs for as 
		// long as possible.
		var idx = last_not_hidden + 1;
		var candidate = this.tabs.childNodes[ idx ];
		if (candidate.hidden)
			return idx;
		// Alright, find the first hidden then
		for (var i = 0; i<this.tabs.childNodes.length; i++) {
			var tab = this.tabs.childNodes[i];
			if (tab.hidden)
				return i;
		}
		return -1;
	},

	'new_tab' : function(focus) {
		var tc = this.find_free_tab();
		if (tc == -1) { return null; } // 9 tabs max
		var tab = this.tabs.childNodes[ tc ];
		//tab.setAttribute('label','Tab ' + (tc + 1) );
		tab.hidden = false;
		try {
			if (focus) this.tabs.selectedIndex = tc;
			this.set_tab('data:text/html,<h1>Hello World</h1>',tc);
		} catch(E) {
			this.error.sdump('D_ERROR',E);
		}
	},

	'set_tab' : function(url,idx) {
		if (!idx) idx = this.tabs.selectedIndex;
		var tab = this.tabs.childNodes[ idx ];
		var panel = this.panels.childNodes[ idx ];
		while ( panel.lastChild ) panel.removeChild( panel.lastChild );
		var frame = this.w.document.createElement('iframe');
		frame.setAttribute('flex','1');
		frame.setAttribute('src',url);
		panel.appendChild(frame);
	}

}

dump('exiting main/menu.js\n');
