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

		var cmd_close_window = this.w.document.getElementById('cmd_close_window');
			if (cmd_close_window)  {
				var f = function() { obj.w.close(); };
				cmd_close_window.addEventListener('command', f, false);
				cmd_close_window.addEventListener('keypress', f, false);
			}
			
		var cmd_new_window = this.w.document.getElementById('cmd_new_window');
			if (cmd_new_window) {
				var f = function() { 
					obj.window.open('/xul/server/main/menu_frame.xul','test' + obj.window.appshell_name_increment++ ,'chrome'); 
				};
				cmd_new_window.addEventListener('command', f, false );
				cmd_new_window.addEventListener('keypress', f, false );
			}

		var cmd_new_tab = this.w.document.getElementById('cmd_new_tab');
			if (cmd_new_tab) {
				var f = function(ev) {
					obj.new_tab();
				};
				cmd_new_tab.addEventListener('command', f, false );
				cmd_new_tab.addEventListener('keypress', f, true );
			}

		var cmd_close_tab = this.w.document.getElementById('cmd_close_tab');
			if (cmd_new_tab) {
				var f = function(ev) { obj.close_tab(); };
				cmd_close_tab.addEventListener('command', f, false );
				cmd_close_tab.addEventListener('keypress', f, false );
			}

		var cmd_broken = this.w.document.getElementById('cmd_broken');
			if (cmd_broken) {
				var f = function() { alert('Not Yet Implemented'); };
				cmd_broken.addEventListener('command', f, false);
				cmd_broken.addEventListener('keypress', f, false);
			}
		
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
					this.error.sdump('D_TAB','failed again tabs.advanceSelectedTab(-1):'+js2JSON(E) + '\n');
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
					this.error.sdump('D_TAB','failed again tabs.advanceSelectedTab(+1):'+js2JSON(E) + '\n');
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

	'new_tab' : function() {
		var tc = this.find_free_tab();
		if (tc == -1) { return null; } // 9 tabs max
		var tab = this.tabs.childNodes[ tc ];
		//tab.setAttribute('label','Tab ' + (tc + 1) );
		tab.hidden = false;
		try {
			this.tabs.selectedIndex = tc;
			//this.replace_tab(tc,'about:blank');
		} catch(E) {
			this.error.sdump('D_ERROR',E);
		}
	}

}

dump('exiting main/menu.js\n');
