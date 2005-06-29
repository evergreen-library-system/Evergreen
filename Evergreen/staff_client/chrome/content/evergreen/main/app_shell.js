sdump('D_TRACE','Loading app_shell.js\n');

function app_shell_init(params) {
	dump("TESTING: app_shell.js: " + mw.G['main_test_variable'] + '\n');
	replace_tab(params.d,'main_tabbox','Tab','chrome://evergreen/content/main/about.xul');
	mw.G.sound.beep();
}

function close_tab( d, t1, t2 ) {
	// t1 = tabbox or tab, if t1 = tabbox, t2 = tab index, otherwise close current tab
	sdump('D_TAB',arg_dump(arguments,{1:true,2:true}));
	if (typeof(t1)!='object')
		t1 = d.getElementById(t1);
	if (typeof(t1)!='object')
		throw('Could not find tab or tabbox. d = ' + d + ' tabbox = ' + t1 + '\n');
	try {
		var tabbox;

		if (t1.tagName == 'tabbox')
			tabbox = t1;
		else
			tabbox = t1.parentNode.parentNode;

		var idx = tabbox.selectedIndex;
		if (t2)
			idx = t2;

		sdump('D_TAB','tabbox.selectedIndex = ' + tabbox.selectedIndex + '\n');
		var tabs = tabbox.firstChild; 
		var panels = tabbox.lastChild;

		if (idx == 0) {
			try {
				tabs.advanceSelectedTab(+1);
			} catch(E) {
				dump('failed tabs.advanceSelectedTab(+1):'+js2JSON(E) + '\n');
				try {
					tabs.advanceSelectedTab(-1);
				} catch(E) {
					dump('failed again tabs.advanceSelectedTab(-1):'+js2JSON(E) + '\n');
				}
			}
		} else {
			try {
				tabs.advanceSelectedTab(-1);
			} catch(E) {
				dump('failed tabs.advanceSelectedTab(-1):'+js2JSON(E) + '\n');
				try {
					tabs.advanceSelectedTab(+1);
				} catch(E) {
					dump('failed again tabs.advanceSelectedTab(+1):'+js2JSON(E) + '\n');
				}
			}

		}
		
		sdump('D_TAB','\tnew tabbox.selectedIndex = ' + tabbox.selectedIndex + '\n');

		tabs.childNodes[ idx ].hidden = true;
		delete_tab_contents( panels.childNodes[ idx ] );
		sdump('D_TAB','tabs.childNodes[ ' + idx + ' ].hidden = true;\n');

		// Make sure we keep at least one tab open.
		var tab_flag = true;
		for (var i = 0; i < tabs.childNodes.length; i++) {
			var tab = tabs.childNodes[i];
			if (!tab.hidden)
				tab_flag = false;
		}
		if (tab_flag)
			new_tab(d,tabbox);

	} catch(E) {
		dump(E+'\n');
		throw(E);
	}
}

function delete_tab_contents( panel ) {
	sdump('D_TAB',arg_dump(arguments,{0:'.tagName'}));
	try {
		while (panel.lastChild) { panel.removeChild(panel.lastChild); }
	} catch(E) {
		dump(js2JSON(E)+'\n');
	}
}

function find_free_tab(tabs) {
	var last_not_hidden = -1;
	for (var i = 0; i<tabs.childNodes.length; i++) {
		var tab = tabs.childNodes[i];
		if (!tab.hidden)
			last_not_hidden = i;
	}
	if (last_not_hidden == tabs.childNodes.length - 1)
		last_not_hidden = -1;
	// If the one next to last_not_hidden is hidden, we want it.
	// Basically, we fill in tabs after existing tabs for as 
	// long as possible.
	var idx = last_not_hidden + 1;
	var candidate = tabs.childNodes[ idx ];
	if (candidate.hidden)
		return idx;
	// Alright, find the first hidden then
	for (var i = 0; i<tabs.childNodes.length; i++) {
		var tab = tabs.childNodes[i];
		if (tab.hidden)
			return i;
	}
	return -1;
}

function new_tab( d, tabbox ) {
	sdump('D_TAB',arg_dump(arguments));
	if (typeof(tabbox)!='object')
		tabbox = d.getElementById(tabbox);
	if (typeof(tabbox)!='object')
		throw('Could not find tabbox. d = ' + d + ' tabbox = ' + tabbox + '\n');
	var tabs = tabbox.firstChild;
	var panels = tabbox.lastChild;
	var tc = find_free_tab(tabs);
	sdump('D_TAB','find_free_tab returned ' + tc + '\n');
	if (tc == -1) { return; } // let's only have up to 10 tabs
	var tab = tabs.childNodes[ tc ];
		tab.setAttribute('label','Tab ' + (tc + 1) );
		tab.hidden = false;
	try {
		tabs.selectedIndex = tc;
		replace_tab(d,tabbox,'Tab','chrome://evergreen/content/main/about.xul');
	} catch(E) {
		dump('+++++++++++++++++++++++++++++' + E + ' : ' + js2JSON(E)+'\n');
	}
}

function replace_tab( d, tabbox, label, chrome, params ) {
	sdump('D_TAB',arg_dump(arguments,{2:true,3:true,4:true}));
	if (typeof(tabbox)!='object')
		tabbox = d.getElementById(tabbox);
	if (typeof(tabbox)!='object')
		throw('Could not find tabbox. d = ' + d + ' tabbox = ' + tabbox + '\n');
	var tabs = tabbox.firstChild;
	var panels = tabbox.lastChild;
	try {
		var idx = tabs.selectedIndex;
		
		delete_tab_contents(panels.childNodes[ idx ]);
		tabs.childNodes[ idx ].hidden = false;
		tabs.childNodes[ idx].setAttribute('label',label + ' ' + (idx+1));

		var frame = d.createElement('iframe');
		frame.setAttribute('id','frame_'+idx);
		frame.setAttribute('flex','1');
		frame.setAttribute('src',chrome);
		panels.childNodes[ idx ].appendChild(frame);
		sdump('D_TAB','Created frame : ' + frame.id + ' for index : ' + idx + ' with src=' + frame.getAttribute('src') + '\n');
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
	//debug_tabs(d,tabbox);
}
