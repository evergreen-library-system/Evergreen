var tab_count = [ false, false, false, false, false, false, false, false, false, false ];

function app_shell_init() {
	dump("TESTING: app_shell.js: " + mw.G['main_test_variable'] + '\n');
	replace_tab('main_tabbox','Tab','chrome://evergreen/content/main/about.xul');
	mw.G.sound.beep();
}

function close_tab( d, tabbox ) {
	var tbox = d.getElementById(tabbox);
	var tabs = tbox.firstChild;
	var panels = tbox.lastChild;
	if (tabs.childNodes.length == 0) { return 0; }
	try {
		var tab = tabs.selectedItem;
		var panel = tbox.selectedPanel;
		tab_count[ tab.getAttribute('count') ] = false;
		tabs.advanceSelectedTab(-1);
		tabs.removeChild( tab );
		panels.removeChild( panel );
	} catch(E) {
		alert(E);
	}
	if (tabs.childNodes.length == 0) { 
		new_tab('main_tabbox');
	}
}

function delete_tab_contents( tab, panel ) {
	try {
		while (tab.lastChild) { tab.removeChild(tab.lastChild); }
		while (panel.lastChild) { panel.removeChild(panel.lastChild); }
	} catch(E) {
		alert(E);
	}
}

function first_free_tab_count() {
	for (var i = 0; i<10; i++) {
		if (! tab_count[i]) {
			tab_count[i] = true;
			return i;
		}
	}
	return -1;
}

function new_tab( d, tabbox ) {
	var tbox = d.getElementById(tabbox);
	var tabs = tbox.firstChild;
	var panels = tbox.lastChild;
	var tc = first_free_tab_count();
	if (tc == -1) { return; } // let's only have up to 10 tabs
	var panel = d.createElement('tabpanel');
		var pl = d.createElement('label');
		pl.setAttribute('value','Panel ' + tc);
		panel.setAttribute('flex','1');
		//panel.setAttribute('style','overflow: auto; min-width: 500px; min-height: 500px;');
		panel.setAttribute('id','panel'+tc);
		panel.appendChild(pl);
	panels.appendChild(panel);

	var tab = d.createElement('tab');
		tab.setAttribute('label','Tab ' + tc );
		tab.setAttribute('count',tc);
		tab.setAttribute('accesskey',tc);
		tab.setAttribute('linkedpanel','panel'+tc);
	tabs.appendChild(tab);
	try {
		tbox.selectedIndex = tc;
		tabs.selectedIndex = tc;
		//tbox.selectedIndex = tabs.childNodes.length - 1;
		//tabs.selectedIndex = tabs.childNodes.length - 1;
		replace_tab(tabbox,'Tab','chrome://evergreen/content/about.xul');
	} catch(E) {
		alert(E);
	}
}

function replace_tab( d, tabbox, label, chrome, params ) {
	var tbox = d.getElementById(tabbox);
	var tabs = tbox.firstChild;
	var panels = tbox.lastChild;
	if (tabs.childNodes.length == 0) { new_tab(tabbox); }
	try {
		var tab = tabs.selectedItem;
		var panel = tbox.selectedPanel;
		delete_tab_contents(tab,panel);

		tab.setAttribute('label',label + ' ' + tab.getAttribute('count') );

		var frame = d.createElement('iframe');
		frame.setAttribute('flex','1');
		//frame.setAttribute('style','overflow: scroll; min-height: 500px; min-width: 500px;');
		frame.setAttribute('src',chrome);
		panel.appendChild(frame);
		frame.contentWindow.parentWindow = parentWindow;
		frame.contentWindow.tabWindow = this;
		dump('replace_tab.tabWindow = ' + this + '\n');
		frame.contentWindow.mw = mw;
		frame.contentWindow.am_i_a_top_level_tab = true;
		if (params) {
			frame.contentWindow.params = params;
		}
		return frame.contentWindow;
	} catch(E) {
		alert(E);
	}

}
