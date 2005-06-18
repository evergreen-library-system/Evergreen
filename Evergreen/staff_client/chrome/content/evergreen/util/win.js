sdump('D_WIN','Loading win.js\n');

function s_alert(s) {
	// alert() replacement, intended to stop barcode scanners from "scanning through" the dialog

	// get a reference to the prompt service component.
	var promptService = Components.classes["@mozilla.org/embedcomp/prompt-service;1"]
		.getService(Components.interfaces.nsIPromptService);

	// set the buttons that will appear on the dialog. It should be
	// a set of constants multiplied by button position constants. In this case,
	// three buttons appear, Save, Cancel and a custom button.
	//var flags=promptService.BUTTON_TITLE_OK * promptService.BUTTON_POS_0 +
	//	promptService.BUTTON_TITLE_CANCEL * promptService.BUTTON_POS_1 +
	//	promptService.BUTTON_TITLE_IS_STRING * promptService.BUTTON_POS_2;
	var flags = promptService.BUTTON_TITLE_IS_STRING * promptService.BUTTON_POS_0;

	// display the dialog box. The flags set above are passed
	// as the fourth argument. The next three arguments are custom labels used for
	// the buttons, which are used if BUTTON_TITLE_IS_STRING is assigned to a
	// particular button. The last two arguments are for an optional check box.
	var check = {};
	sdump('D_WIN','s_alert: ' + s);
	promptService.confirmEx(window,"ALERT",
		s,
		flags, 
		"Enter", null, null, 
		"Check this box to confirm this message", 
		check
	);
	if (!check.value) {
		snd_bad();
		s_alert(s);
	}
}

function new_window(chrome,params) {
	var name = self.name + '_' + ++mw.G['window_name_increment'];
	var options = 'chrome,resizable=yes,scrollbars=yes,width=800,height=600,fullscreen=yes';
	try {
		if (params) {
			if (params['window_name']) { name = params.window_name; }
			if (params['window_options']) { options = params.window_options; }
		}
	} catch(E) {
	}
	//var w = window.open(
	var w = SafeWindowOpen(
		chrome,
		name,
		options
	);
	if (w) {
		if (w != self) { 
			w.parentWindow = self;
			w.mw = mw;
			register_window(w); 
		}
		w.am_i_a_top_level_tab = false;
		if (params) {
			w.params = params;
		}
	}
	return w;
}


// From: Bryan White on netscape.public.mozilla.xpfe, Oct 13, 2004
// Message-ID: <ckjh7a$18q1@ripley.netscape.com>
// Modified to return window handler, and do errors differently
function SafeWindowOpen(url,title,features)
{
	var w;

   netscape.security.PrivilegeManager
     .enablePrivilege("UniversalXPConnect");    
   const CI = Components.interfaces;
   const PB =
     Components.classes["@mozilla.org/preferences-service;1"]
     .getService(CI.nsIPrefBranch);

   var blocked = false;
   try
   {
     // pref 'dom.disable_open_during_load' is the main popup
     // blocker preference
     blocked = PB.getBoolPref("dom.disable_open_during_load");
     if(blocked)
       PB.setBoolPref("dom.disable_open_during_load",false);
     w = window.open(url,title,features);
   }
   catch(e)
   {
     //alert("SafeWindowOpen error:\n\n" + e);
     handle_error(e);
   }
   if(blocked)
     PB.setBoolPref("dom.disable_open_during_load",true);

	return w;
} 

function register_window(w) {
	mw.G['win_list'].push(w);
}

function register_patron_window(w) { }
function unregister_patron_window(w) { }

function close_all_windows() {
	var w;
	while (w = mw.G['win_list'].pop()) {
		w.close();
	}
}

function spawn_copy_browser(tab,params) {
	sdump('D_WIN','trying to spawn_copy_browser('+js2JSON(params)+')\n');
	var w;
	var chrome = 'chrome://evergreen/content/cat/browse_list.xul';
	if (tab) {
		if (tab != 'replace') { tabWindow.new_tab('main_tabbox'); }
		w = tabWindow.replace_tab('main_tabbox','COPIES',chrome);
	} else {
		w = mw.new_window( chrome );
	}
	w.find_this_id = params[0];
	w.record_columns = params;
}

function spawn_batch_copy_editor(tab,params) {
	sdump('D_WIN','trying to spawn_copy_editor(' + params + ')');
	var w;
	var chrome = 'chrome://evergreen/content/cat/copy_edit.xul';
	if (tab) {
		if (tab != 'replace') { tabWindow.new_tab('main_tabbox'); }
		w = tabWindow.replace_tab('main_tabbox','COPIES EDITOR',chrome);
	} else {
		w = mw.new_window( chrome );
	}
	w.params = params;
}

function spawn_marc_editor(tab,params) {
	sdump('D_WIN','trying to spawn_marc_editor('+js2JSON(params)+')\n');
	var w;
	var chrome = 'chrome://evergreen/content/cat/marc.xul';
	if (tab) {
		if (tab != 'replace') { tabWindow.new_tab('main_tabbox'); }
		w = tabWindow.replace_tab('main_tabbox','MARC',chrome);
	} else {
		w = mw.new_window( chrome );
	}
	w.find_this_id = params[0];
	w.record_columns = params;
	w.params = params;
}

function spawn_oclc_import(tab,params) {
	sdump('D_WIN','trying to spawn_marc_editor('+js2JSON(params)+')\n');
	// sample TCN: 03715963 
	try {
		if (params.tcn.length < 6) {
			throw("Too short.  At the moment, we're really doing a search rather than a retrieve, and it's a substring search at that.  We grab the result that matches exactly.  But sending a short query would just be mean. :)");
		}
		var result = user_request(
			'open-ils.search',
			'open-ils.search.z3950.import',
			[ mw.G.auth_ses[0], params.tcn ]
		)[0];
		if (typeof result == 'object') {
			if (result.records.length > 0) {	
				params['import_tree'] = result.records[0];
			} else {
				throw('no records. result = ' + js2JSON(result) + '\n');
			}
		} else {
			throw('result: ' + js2JSON(result) + '\n');
		}
		var w;
		var chrome = 'chrome://evergreen/content/cat/marc.xul';
		if (tab) {
			if (tab != 'replace') { tabWindow.new_tab('main_tabbox'); }
			w = tabWindow.replace_tab('main_tabbox','MARC',chrome);
		} else {
			w = mw.new_window( chrome );
		}
		w.params = params;
		w.find_this_id = -1;
		//w.record_columns = params;

	} catch(E) {
		handle_error(E);
	}

}

function spawn_bill_pay(tab,patron,params) {
	sdump('D_WIN','trying to spawn_bill_pay('+js2JSON(patron)+')\n');
	sdump('D_WIN','barcode: ' + patron.barcode() + '\n');
	var w;
	var chrome = 'chrome://evergreen/content/bill/bill.xul';
	var params = { 'barcode' : patron.barcode() };
	if (tab) {
		if (tab != 'replace') { tabWindow.new_tab('main_tabbox'); }
		w = tabWindow.replace_tab('main_tabbox','BILLS',chrome,params);
	} else {
		w = mw.new_window( chrome,params );
	}
}

function spawn_check_out(tab,patron,params) {
	sdump('D_WIN','trying to spawn_check_out('+js2JSON(patron)+')\n');
	sdump('D_WIN','barcode: ' + patron.barcode() + '\n');
	var w;
	var chrome = 'chrome://evergreen/content/circ/checkout.xul';
	var params = { 'barcode' : patron.barcode() };
	if (tab) {
		if (tab != 'replace') { tabWindow.new_tab('main_tabbox'); }
		w = tabWindow.replace_tab('main_tabbox','CHECK OUT',chrome,params);
	} else {
		w = mw.new_window( chrome,params );
	}
}

function spawn_circ_list(tab,patron,params) {
	sdump('D_WIN','trying to spawn_circ_list('+js2JSON(patron)+')\n');
	sdump('D_WIN','barcode: ' + patron.barcode() + '\n');
	var w;
	var chrome = 'chrome://evergreen/content/circ/circ_list.xul';
	var params = { 'barcode' : patron.barcode() };
	if (tab) {
		if (tab != 'replace') { tabWindow.new_tab('main_tabbox'); }
		w = tabWindow.replace_tab('main_tabbox','ITEMS OUT',chrome,params);
	} else {
		w = mw.new_window( chrome,params );
	}
}

function spawn_patron_edit(tab,patron,params) {
	sdump('D_WIN','trying to spawn_patron_edit('+js2JSON(patron)+')\n');
	sdump('D_WIN','barcode: ' + patron.barcode() + '\n');
	var w;
	var chrome = 'chrome://evergreen/content/patron/patron_edit.xul';
	var params = { 'barcode' : patron.barcode() };
	if (tab) {
		if (tab != 'replace') { tabWindow.new_tab('main_tabbox'); }
		w = tabWindow.replace_tab('main_tabbox','PATRON EDIT',chrome,params);
	} else {
		w = mw.new_window( chrome, params );
	}
}

function spawn_test() {
	var chrome = 'chrome://evergreen/content/patron/patron_edit.xul';
	var params = { 'barcode':'101010101010101' };
	var w = tabWindow.replace_tab('main_tabbox','TEST',chrome,params);
}


