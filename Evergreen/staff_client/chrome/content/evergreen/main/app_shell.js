sdump('D_TRACE','Loading app_shell.js\n');

function app_shell_init(p) {
	sdump('D_TAB',"TESTING: app_shell.js: " + mw.G['main_test_variable'] + '\n');

	p.w.close_tab = function (t1,t2) { return close_tab(p.w.document,t1,t2); };
	p.w.find_free_tab = function (tabs) { return find_free_tab(tabs); };
	p.w.new_tab = function () { return new_tab(p.w.document,p.tabbox); };
	p.w.replace_tab = function (label,chrome,params) { return replace_tab(p.w.document,p.tabbox,label,chrome,params); };
	p.w.get_frame_in_tab = function (idx, all_or_vis) { return get_frame_in_tab( p.w.document, p.tabbox, idx, all_or_vis ); }; 
	
	//p.w.replace_tab('Tab','chrome://evergreen/content/main/about.xul');
	spawn_javascript_shell(p.w.document,'replace_tab','main_tabbox',{});
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
				sdump('D_TAB','failed tabs.advanceSelectedTab(+1):'+js2JSON(E) + '\n');
				try {
					tabs.advanceSelectedTab(-1);
				} catch(E) {
					sdump('D_TAB','failed again tabs.advanceSelectedTab(-1):'+js2JSON(E) + '\n');
				}
			}
		} else {
			try {
				tabs.advanceSelectedTab(-1);
			} catch(E) {
				sdump('D_TAB','failed tabs.advanceSelectedTab(-1):'+js2JSON(E) + '\n');
				try {
					tabs.advanceSelectedTab(+1);
				} catch(E) {
					sdump('D_TAB','failed again tabs.advanceSelectedTab(+1):'+js2JSON(E) + '\n');
				}
			}

		}
		
		sdump('D_TAB','\tnew tabbox.selectedIndex = ' + tabbox.selectedIndex + '\n');

		tabs.childNodes[ idx ].hidden = true;
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
		sdump('D_ERROR',E+'\n');
		throw(E);
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

function get_frame_in_tab( d, tabbox, idx, all_or_visible ) {
	sdump('D_TAB',arg_dump(arguments));
	if (typeof(tabbox)!='object')
		tabbox = d.getElementById(tabbox);
	if (typeof(tabbox)!='object')
		throw('Could not find tabbox. d = ' + d + ' tabbox = ' + tabbox + '\n');
	var tabs = tabbox.firstChild;
	var panels = tabbox.lastChild;
	try {
		if (all_or_visible == 'visible') {
			var count = 0;
			for (var i = 0; i < tabs.childNodes.length; i++) {
				if (!tabs.childNodes[i].hidden) count++;
				if (count==idx) return panels.childNodes[i].getElementsByTagName('iframe')[0];
			}
		} else {
			return panels.childNodes[ idx ].getElementsByTagName('iframe')[0];
		}
	} catch(E) {
		sdump('D_ERROR',js2JSON(E) + '\n');
	}
	return null;
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
		sdump('D_ERROR','+++++++++++++++++++++++++++++' + E + ' : ' + js2JSON(E)+'\n');
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
		var tab = tabs.childNodes[ idx ];
		var panel = panels.childNodes[ idx ];

		tab.hidden = false;
		tab.setAttribute('label',label + ' ' + (idx+1));

		var frame = d.createElement('iframe');
		frame.setAttribute('flex','1');
		frame.setAttribute('src',chrome);
		panel.appendChild(frame);
		panel.replaceChild(panel.lastChild,panel.firstChild);
		frame.setAttribute('id','frame_'+idx);
		
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
		sdump('D_ERROR',js2JSON(E)+'\n');
	}
	//debug_tabs(d,tabbox);
}
