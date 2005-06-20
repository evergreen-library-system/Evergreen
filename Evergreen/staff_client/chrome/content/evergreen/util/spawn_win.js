function spawn_batch_copy_editor(d,tab,params) {
	sdump('D_SPAWN','trying to spawn_copy_editor(' + params + ')');
	var w;
	var chrome = 'chrome://evergreen/content/cat/copy_edit.xul';
	if (tab) {
		if (tab != 'replace') { new_tab(d,'main_tabbox'); }
		w = replace_tab(d,'main_tabbox','COPIES EDITOR',chrome);
	} else {
		w = mw.new_window( chrome );
	}
	w.params = params;
}

function spawn_bill_pay(d,tab,patron,params) {
	sdump('D_SPAWN','trying to spawn_bill_pay('+js2JSON(patron)+')\n');
	sdump('D_SPAWN','barcode: ' + patron.barcode() + '\n');
	var w;
	var chrome = 'chrome://evergreen/content/bill/bill.xul';
	var params = { 'barcode' : patron.barcode() };
	if (tab) {
		if (tab != 'replace') { new_tab(d,'main_tabbox'); }
		w = replace_tab(d,'main_tabbox','BILLS',chrome,params);
	} else {
		w = mw.new_window( chrome,params );
	}
}

function spawn_check_out(d,tab,patron,params) {
	sdump('D_SPAWN','trying to spawn_check_out('+js2JSON(patron)+')\n');
	sdump('D_SPAWN','barcode: ' + patron.barcode() + '\n');
	var w;
	var chrome = 'chrome://evergreen/content/circ/checkout.xul';
	var params = { 'barcode' : patron.barcode() };
	if (tab) {
		if (tab != 'replace') { new_tab(d,'main_tabbox'); }
		w = replace_tab(d,'main_tabbox','CHECK OUT',chrome,params);
	} else {
		w = mw.new_window( chrome,params );
	}
}

function spawn_circ_list(d,tab,patron,params) {
	sdump('D_SPAWN','trying to spawn_circ_list('+js2JSON(patron)+')\n');
	sdump('D_SPAWN','barcode: ' + patron.barcode() + '\n');
	var w;
	var chrome = 'chrome://evergreen/content/circ/circ_list.xul';
	var params = { 'barcode' : patron.barcode() };
	if (tab) {
		if (tab != 'replace') { new_tab(d,'main_tabbox'); }
		w = replace_tab(d,'main_tabbox','ITEMS OUT',chrome,params);
	} else {
		w = mw.new_window( chrome,params );
	}
}


function spawn_copy_browser(d,tab,params) {
	sdump('D_SPAWN','trying to spawn_copy_browser('+js2JSON(params)+')\n');
	var w;
	var chrome = 'chrome://evergreen/content/cat/browse_list.xul';
	if (tab) {
		if (tab != 'replace') { new_tab(d,'main_tabbox'); }
		w = replace_tab(d,'main_tabbox','COPIES',chrome);
	} else {
		w = mw.new_window( chrome );
	}
	w.find_this_id = params[0];
	w.record_columns = params;
}

function spawn_main() {
	try {
		var w = new_window('chrome://evergreen/content/evergreen/main/app_shell.xul');
		if (!w) { throw('window ref == null'); }
		try {
			w.document.title = mw.G.user.usrname() + '@' + mw.G.user_ou.name();
		} catch(E) {
			alert('Hrmm. ' + pretty_print( js2JSON(E) ) );
		}
	} catch(E) {
		incr_progressmeter('auth_meter',-100);
		alert('Login failed on new_window: ' + js2JSON(E)); enable_login_prompts(); return;
	}
	incr_progressmeter('auth_meter',100);
}


function spawn_marc_editor(d,tab,params) {
	sdump('D_SPAWN','trying to spawn_marc_editor('+js2JSON(params)+')\n');
	var w;
	var chrome = 'chrome://evergreen/content/cat/marc.xul';
	if (tab) {
		if (tab != 'replace') { new_tab(d,'main_tabbox'); }
		w = replace_tab(d,'main_tabbox','MARC',chrome);
	} else {
		w = mw.new_window( chrome );
	}
	w.find_this_id = params[0];
	w.record_columns = params;
	w.params = params;
}

function spawn_oclc_import(d,tab,params) {
	sdump('D_SPAWN','trying to spawn_marc_editor('+js2JSON(params)+')\n');
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
			if (tab != 'replace') { new_tab(d,'main_tabbox'); }
			w = replace_tab(d,'main_tabbox','MARC',chrome);
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

function spawn_patron_edit(d,tab,patron,params) {
	sdump('D_SPAWN','trying to spawn_patron_edit('+js2JSON(patron)+')\n');
	sdump('D_SPAWN','barcode: ' + patron.barcode() + '\n');
	var w;
	var chrome = 'chrome://evergreen/content/patron/patron_edit.xul';
	var params = { 'barcode' : patron.barcode() };
	if (tab) {
		if (tab != 'replace') { new_tab(d,'main_tabbox'); }
		w = replace_tab(d,'main_tabbox','PATRON EDIT',chrome,params);
	} else {
		w = mw.new_window( chrome, params );
	}
}

function spawn_test(d) {
	var chrome = 'chrome://evergreen/content/patron/patron_edit.xul';
	var params = { 'barcode':'101010101010101' };
	var w = replace_tab(d,'main_tabbox','TEST',chrome,params);
}


