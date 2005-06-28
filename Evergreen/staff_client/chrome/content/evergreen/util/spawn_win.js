function spawn_interface(d,tab_flag,tabbox,chrome,label,passthru_params) {
	sdump('D_SPAWN','trying to spawn_window('+d+','+tab_flag+','+tabbox+','+chrome+','+label+','+js2JSON(passthru_params)+')\n');
	var w;
	if (tab_flag) {
		if (tab_flag != 'replace') { new_tab(d,tabbox); }
		w = replace_tab(d,tabbox,label,chrome);
	} else {
		w = new_window( chrome );
	}
	w.params = params;
}

function spawn_batch_copy_editor(d,tab_flag,passthru_params) {
	var chrome = 'chrome://evergreen/content/cat/copy_edit.xul';
	spawn_interface(d,tab_flag,'main_tabbox',chrome,getString('copies_editor_interface_label'),passthru_params);
}

function spawn_bill_pay(d,tab_flag,passthru_params) {
	var chrome = 'chrome://evergreen/content/bill/bill.xul';
	spawn_interface(d,tab_flag,'main_tabbox',chrome,getString('bills_interface_label'),passthru_params);
}

function spawn_check_in(d,tab_flag,passthru_params) {
	var chrome = 'chrome://evergreen/content/circ/checkin.xul';
	spawn_interface(d,tab_flag,'main_tabbox',chrome,getString('checkin_interface_label'),passthru_params);
}

function spawn_check_out(d,tab_flag,passthru_params) {
	var chrome = 'chrome://evergreen/content/circ/checkout.xul';
	spawn_interface(d,tab_flag,'main_tabbox',chrome,getString('checkout_interface_label'),passthru_params);
}

function spawn_circ_display(d,tab_flag,passthru_params) {
	var chrome = 'chrome://evergreen/content/circ/circ_deck_patron.xul';
	spawn_interface(d,tab_flag,'main_tabbox',chrome,getString('display_patron_interface_label'),passthru_params);
}

function spawn_circ_list(d,tab_flag,passthru_params) {
	var chrome = 'chrome://evergreen/content/circ/circ_list.xul';
	spawn_interface(d,tab_flag,'main_tabbox',chrome,getString('items_out_interface_label'),passthru_params);
}

function spawn_circ_search(d,tab_flag,passthru_params) {
	var chrome = 'chrome://evergreen/content/circ/circ_deck_search.xul';
	spawn_interface(d,tab_flag,'main_tabbox',chrome,getString('patron_search_interface_label'),passthru_params);
}

function spawn_copy_browser(d,tab_flag,passthru_params) {
	var chrome = 'chrome://evergreen/content/cat/browse_list.xul';
	spawn_interface(d,tab_flag,'main_tabbox',chrome,getString('copy_browser_interface_label'),passthru_params);
}

function spawn_main() {
	sdump('D_SPAWN','trying to spawn app_shell\n');
	try {
		var w = new_window('chrome://evergreen/content/main/app_shell.xul');
		if (!w) { throw('window ref == null'); }
		try {
			w.document.title = G.user.usrname() + '@' + G.user_ou.name();
		} catch(E) {
			alert('Hrmm. ' + pretty_print( js2JSON(E) ) );
		}
	} catch(E) {
		dump(js2JSON(E)+'\n');
		//incr_progressmeter('auth_meter',-100);
		//alert('Login failed on new_window: ' + js2JSON(E)); enable_login_prompts(); return;
	}
	//incr_progressmeter('auth_meter',100);
}

function spawn_marc_editor(d,tab_flag,passthru_params) {
	var chrome = 'chrome://evergreen/content/cat/marc.xul';
	spawn_interface(d,tab_flag,'main_tabbox',chrome,getString('marc_editor_interface_label'),passthru_params);
}

function spawn_opac_navigator(d,tab_flag,passthru_params) {
	var chrome = 'chrome://evergreen/content/opac/opac.xul';
	spawn_interface(d,tab_flag,'main_tabbox',chrome,getString('opac_navigator_interface_label'),passthru_params);
}

function spawn_oclc_import(d,tab_flag,params) {
	sdump('D_SPAWN','trying to spawn_oclc_import('+js2JSON(passthru_params)+')\n');
	// sample TCN: 03715963 
	try {
		if (params.tcn.length < 6) {
			throw("Too short.  At the moment, we're really doing a search rather than a retrieve, and it's a substring search at that.  We grab the result that matches exactly.  But sending a short query would just be mean. :)");
		}
		var result = user_request(
			'open-ils.search',
			'open-ils.search.z3950.import',
			[ G.auth_ses[0], params.tcn ]
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
		spawn_marc_editor(d,tab_flag,params);
	} catch(E) {
		handle_error(E);
	}
}

function spawn_patron_edit(d,tab_flag,passthru_params) {
	var chrome = 'chrome://evergreen/content/patron/patron_edit.xul';
	spawn_interface(d,tab_flag,'main_tabbox',chrome,getString('patron_editor_interface_label'),passthru_params);
}

function spawn_patron_register(d,tab_flag,passthru_params) {
	var chrome = 'chrome://evergreen/content/patron/patron_new.xul';
	spawn_interface(d,tab_flag,'main_tabbox',chrome,getString('patron_register_interface_label'),passthru_params);
}


function spawn_copy_stat_cat_edit(d,tab_flag,passthru_params) {
	var chrome = 'chrome://evergreen/content/stat_cat/copy_stat_cat_editor.xul';
	spawn_interface(d,tab_flag,'main_tabbox',chrome,getString('copy_stat_cat_editor_interface'),passthru_params);
}

function spawn_patron_stat_cat_edit(d,tab_flag,passthru_params) {
	var chrome = 'chrome://evergreen/content/stat_cat/patron_stat_cat_editor.xul';
	spawn_interface(d,tab_flag,'main_tabbox',chrome,getString('patron_stat_cat_editor_interface'),passthru_params);
}

function spawn_survey_admin_wizard(d,tab_flag,passthru_params) {
	var chrome = 'chrome://evergreen/content/survey/survey_wizard.xul';
	spawn_interface(d,tab_flag,'main_tabbox',chrome,getString('survey_admin_interface_label'),passthru_params);
}


function spawn_z3950_import(d,tab_flag,passthru_params) {
	var chrome = 'chrome://evergreen/content/z39_50/z39_50.xul';
	spawn_interface(d,tab_flag,'main_tabbox',chrome,getString('z39_50_import_interface_label'),passthru_params);
}

