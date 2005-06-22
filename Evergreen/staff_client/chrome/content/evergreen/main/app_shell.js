sdump('D_TRACE','Loading app_shell.js\n');

var tab_count = [ false, false, false, false, false, false, false, false, false, false ];

function debug_tabs( d, tabbox ) {
	if (typeof(tabbox)!='object')
		tabbox = d.getElementById(tabbox);
	if (typeof(tabbox)!='object')
		throw('Could not find tabbox. d = ' + d + ' tabbox = ' + tabbox + '\n');
	var tabs = tabbox.firstChild; 
	var panels = tabbox.lastChild;
	sdump('D_TAB', d.id + '\t' + tabbox.id + '\n');
	sdump('D_TAB','\ttabs.childNodes.length = ' + tabs.childNodes.length + '\n');
	for (var i = 0; i < tabs.childNodes.length; i++) {
		var tab = tabs.childNodes[i];
		sdump('D_TAB','\t\t#' + i + '  tab = ' + tab.tagName + ' : ' + tab.id + '\n' );
		if (tab.childNodes) {
			sdump('D_TAB','\t\t\ttab.childNodes.length = ' + tab.childNodes.length + '\n');
			for (var j = 0; j < tab.childNodes.length; j++) {
				var child = tab.childNodes[j];
				sdump('D_TAB','\t\t\t#' + j + ' ' + child.tagName + ' : ' + child.id + '\n');
			}
		}
	}

	sdump('D_TAB','\tpanels.childNodes.length = ' + panels.childNodes.length + '\n');
	for (var i = 0; i < panels.childNodes.length; i++) {
		var panel = panels.childNodes[i];
		sdump('D_TAB','\t\t#' + i + '  panel = ' + panel.tagName + ' : ' + panel.id + '\n' );
		if (panel.childNodes) {
			sdump('D_TAB','\t\t\tpanel.childNodes.length = ' + panel.childNodes.length + '\n');
			for (var j = 0; j < panel.childNodes.length; j++) {
				var child = panel.childNodes[j];
				sdump('D_TAB','\t\t\t#' + j + ' ' + child.tagName + ' : ' + child.id + '\n');
			}
		}
	}
}

function app_shell_init(params) {
	dump("TESTING: app_shell.js: " + mw.G['main_test_variable'] + '\n');
	replace_tab(params.d,'main_tabbox','Tab','chrome://evergreen/content/main/about.xul');
	mw.G.sound.beep();
}

function close_tab( d, tabbox ) {
	sdump('D_TAB','calling close_tab( ' + d.id + ',' + tabbox + ');\n');
	if (typeof(tabbox)!='object')
		tabbox = d.getElementById(tabbox);
	if (typeof(tabbox)!='object')
		throw('Could not find tabbox. d = ' + d + ' tabbox = ' + tabbox + '\n');
	try {
		var idx = tabbox.selectedIndex;
		var tabs = tabbox.firstChild; 
		var panels = tabbox.lastChild;

		if (idx == 0)
			tabs.advanceSelectedTab(+1);
		else
			tabs.advanceSelectedTab(-1);

		if (tabs.childNodes.length > 1 ) {
			tabs.removeItemAt( idx );
			panels.removeChild( panels.childNodes[ idx ] );
		} else {
			replace_tab(d,tabbox,'Tab','chrome://evergreen/content/main/about.xul');
		}

	} catch(E) {
		dump(E+'\n');
		throw(E);
	}
	debug_tabs(d,tabbox);
}

function delete_tab_contents( tab, panel ) {
	sdump('D_TAB','calling delete_tab_contents( ' + tab.id + ',' + panel.id + ');\n');
	try {
		if (tab.childNodes)
			sdump('D_TAB','before: tab.childNodes.length = ' + tab.childNodes.length + '\n');
		if (panel.childNodes)
			sdump('D_TAB','before: panel.childNodes.length = ' + panel.childNodes.length + '\n');
		while (tab.lastChild) { tab.removeChild(tab.lastChild); }
		while (panel.lastChild) { panel.removeChild(panel.lastChild); }
		if (tab.childNodes)
			sdump('D_TAB','after: tab.childNodes.length = ' + tab.childNodes.length + '\n');
		if (panel.childNodes)
			sdump('D_TAB','after: panel.childNodes.length = ' + panel.childNodes.length + '\n');
	} catch(E) {
		dump(js2JSON(E)+'\n');
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
	sdump('D_TAB','calling new_tab( ' + d.id + ',' + tabbox + ');\n');
	if (typeof(tabbox)!='object')
		tabbox = d.getElementById(tabbox);
	if (typeof(tabbox)!='object')
		throw('Could not find tabbox. d = ' + d + ' tabbox = ' + tabbox + '\n');
	var tabs = tabbox.firstChild;
	var panels = tabbox.lastChild;
	var tc = first_free_tab_count();
	if (tc == -1) { return; } // let's only have up to 10 tabs
	var panel = d.createElement('tabpanel');
		panel.setAttribute('flex','1');
		panel.setAttribute('id','panel'+tc);
	panels.appendChild(panel);
	sdump('D_TAB','Created a tabpanel: ' + panel.id + '\n');

	var tab = d.createElement('tab');
		tab.setAttribute('id','tab' + tc );
		tab.setAttribute('label','Tab ' + tc );
		tab.setAttribute('count',tc);
		tab.setAttribute('accesskey',tc);
		tab.setAttribute('linkedpanel','panel'+tc);
	tabs.appendChild(tab);
	sdump('D_TAB','Created a tab: ' + tab.id + '\n');
	try {
		sdump('D_TAB','before: tabbox.selectedIndex = ' +
			tabbox.selectedIndex +
			' .selectedTab = ' + tabbox.selectedTab.id +
			' .selectedPanel = ' + tabbox.selectedPanel.id + '\n');
		sdump('D_TAB','before: tabs.selectedIndex = ' +
			tabs.selectedIndex + ' .selectedItem = ' +
			tabs.selectedItem.id + '\n');
		sdump('D_TAB','before: panels.selectedIndex = ' +
			panels.selectedIndex + ' .selectedPanel = ' +
			panels.selectedPanel.id + '\n');
		tabbox.selectedIndex = tc;
		tabs.selectedIndex = tc;
		sdump('D_TAB','after: tabbox.selectedIndex = ' +
			tabbox.selectedIndex +
			' .selectedTab = ' + tabbox.selectedTab.id +
			' .selectedPanel = ' + tabbox.selectedPanel.id + '\n');
		sdump('D_TAB','after: tabs.selectedIndex = ' +
			tabs.selectedIndex + ' .selectedItem = ' +
			tabs.selectedItem.id + '\n');
		sdump('D_TAB','after: panels.selectedIndex = ' +
			panels.selectedIndex + ' .selectedPanel = ' +
			panels.selectedPanel.id + '\n');

		//tabbox.selectedIndex = tabs.childNodes.length - 1;
		//tabs.selectedIndex = tabs.childNodes.length - 1;
		replace_tab(d,tabbox,'Tab','chrome://evergreen/content/main/about.xul');
	} catch(E) {
		dump(js2JSON(E)+'\n');
	}
	debug_tabs(d,tabbox);
}

function replace_tab( d, tabbox, label, chrome, params ) {
	sdump('D_TAB','calling replace_tab( ' + d.id + ',' + tabbox + ');\n');
	if (typeof(tabbox)!='object')
		tabbox = d.getElementById(tabbox);
	if (typeof(tabbox)!='object')
		throw('Could not find tabbox. d = ' + d + ' tabbox = ' + tabbox + '\n');
	var tabs = tabbox.firstChild;
	var panels = tabbox.lastChild;
	if (tabs.childNodes.length == 0) { new_tab(d,tabbox); }
	try {
		var tab = tabs.selectedItem;
		var panel = tabbox.selectedPanel;
		delete_tab_contents(tab,panel);

		tab.setAttribute('label',label + ' ' + tab.getAttribute('count') );

		var frame = d.createElement('iframe');
		frame.setAttribute('id','frame'+tab.getAttribute('count'));
		frame.setAttribute('flex','1');
		//frame.setAttribute('style','overflow: scroll; min-height: 500px; min-width: 500px;');
		frame.setAttribute('src',chrome);
		panel.appendChild(frame);
		sdump('D_TAB','Created frame : ' + frame.id + ' for tab : ' + tab.id + ' and panel : ' + panel.id + '\n');
		//frame.contentWindow.parentWindow = parentWindow;
		//frame.contentWindow.tabWindow = this;
		//dump('replace_tab.tabWindow = ' + this + '\n');
		frame.contentWindow.mw = mw;
		//frame.contentWindow.am_i_a_top_level_tab = true;
		if (params) {
			frame.contentWindow.params = params;
		}
		return frame.contentWindow;
	} catch(E) {
		dump(js2JSON(E)+'\n');
	}
	debug_tabs(d,tabbox);
}
