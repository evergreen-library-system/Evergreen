function spawn_interface(d,placement,place,chrome,label,passthru_params,clone) {
	sdump('D_SPAWN',arg_dump(arguments,{0:true,1:true,2:true,3:true,4:true,5:true}));
	var w;
	switch(placement) {
		case 'new_tab' : 
			mw.new_tab(d,place); 
			w = spawn_interface(d,'replace_tab',place,chrome,label,passthru_params,clone); break;

		case 'replace_tab' : 
			w = mw.replace_tab(d,place,label,chrome); break;

		case 'new_window' : 
			w = new_window( chrome, { 'window_name' : label } ); break;


		case 'replace_iframe' :
		case 'replace_browser' :
		case 'replace_editor' :
			var el = placement.slice(8);
			var container = get_widget( d, place );
			empty_widget( d, container );
			w = spawn_interface(d,'new_' + el,place,chrome,label,passthru_params,clone); 
			break;

		case 'new_iframe' :
		case 'new_browser' :
		case 'new_editor' :
			var el = placement.slice(4);
			var frame = d.createElement( el );
			frame.setAttribute('flex','1');
			get_widget( d, place ).appendChild( frame );
			w = spawn_interface(d,'set_frame',frame,chrome,label,passthru_params,clone); 
			break;

		case 'set_frame' :
			var frame = get_widget( d, place );
			if (clone) {
				frame.contentWindow.document = mw.G.test_win.document.cloneNode(true);
			} else {
				frame.setAttribute('src',chrome); 
			}
			w = frame.contentWindow;
			break;
	}
	w.params = passthru_params;
	w.mw = mw;
	if (placement == 'new_tab' || placement == 'replace_tab') w.app_shell = d;
	return w;
}

/* developer utilities */

function spawn_javascript_console(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://global/content/console.xul';
	return spawn_interface(d,placement,place,chrome,getString('javascript_console_label'),passthru_params,clone);
}

function spawn_xuleditor(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/util/xuledit.xul';
	return spawn_interface(d,placement,place,chrome,getString('xuleditor_label'),passthru_params,clone);
}

function spawn_javascript_shell(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/util/shell.html';
	return spawn_interface(d,placement,place,chrome,getString('javascript_shell_label'),passthru_params,clone);
}

function spawn_filter_console(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/util/filter_console.xul';
	return spawn_interface(d,placement,place,chrome,getString('filter_console_label'),passthru_params,clone);
}

function spawn_fieldmapper(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/util/fm_view.xul';
	return spawn_interface(d,placement,place,chrome,getString('fieldmapper_label'),passthru_params,clone);
}

/* current */

function spawn_main() {
	sdump('D_SPAWN','trying to spawn app_shell\n');
	try {
		var w = new_window('chrome://evergreen/content/main/app_shell.xul', {});
		if (!w) { throw('window ref == null'); }
		try {
			w.params = {};
		} catch(E) {
			alert('Hrmm. ' + pretty_print( js2JSON(E) ) );
		}
	} catch(E) {
		dump(js2JSON(E)+'\n');
	}
}

function spawn_checkin(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/circ/checkin.xul';
	return spawn_interface(d,placement,place,chrome,getString('checkin_interface_label'),passthru_params,clone);
}

function spawn_hold_capture(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/circ/hold_capture.xul';
	return spawn_interface(d,placement,place,chrome,getString('hold_capture_interface_label'),passthru_params,clone);
}

function spawn_opac_navigator(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/opac/opac.xul';
	//var chrome = 'http://google.com/';
	return spawn_interface(d,placement,place,chrome,getString('opac_navigator_interface_label'),passthru_params,clone);
}

function spawn_patron_barcode_entry(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/patron/patron_barcode_entry.xul';
	return spawn_interface(d,placement,place,chrome,getString('patron_barcode_entry_interface_label'),passthru_params,clone);
}

function spawn_patron_display(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/patron/patron_display.xul';
	return spawn_interface(d,placement,place,chrome,getString('patron_display_interface_label'),passthru_params,clone);
}

function spawn_patron_search(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/patron/patron_search.xul';
	return spawn_interface(d,placement,place,chrome,getString('patron_search_interface_label'),passthru_params,clone);
}

function spawn_receipt_template_editor(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/circ/receipt_template_editor.xul';
	return spawn_interface(d,placement,place,chrome,getString('receipt_template_editor_interface_label'),passthru_params,clone);
}

/* legacy code, may be removed or refactored */

function spawn_batch_copy_editor(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/cat/copy_edit.xul';
	return spawn_interface(d,placement,place,chrome,getString('copies_editor_interface_label'),passthru_params,clone);
}

function spawn_bill_pay(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/bill/bill.xul';
	return spawn_interface(d,placement,place,chrome,getString('bills_interface_label'),passthru_params,clone);
}

function spawn_copy_browser(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/cat/browse_list.xul';
	return spawn_interface(d,placement,place,chrome,getString('copy_browser_interface_label'),passthru_params,clone);
}

function spawn_marc_editor(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/cat/marc.xul';
	return spawn_interface(d,placement,place,chrome,getString('marc_editor_interface_label'),passthru_params,clone);
}

function spawn_oclc_import(d,placement,place,passthru_params,clone) {
	sdump('D_SPAWN','trying to spawn_oclc_import('+js2JSON(passthru_params)+')\n');
	// sample TCN: 03715963 
	try {
		if (passthru_params.tcn.length < 6) {
			throw("Too short.  At the moment, we're really doing a search rather than a retrieve, and it's a substring search at that.  We grab the result that matches exactly.  But sending a short query would just be mean. :)");
		}
		var result = user_request(
			'open-ils.search',
			'open-ils.search.z3950.import',
			[ mw.G.auth_ses[0], passthru_params.tcn ]
		)[0];
		if (result) {
			if (typeof result == 'object') {
				if (result.records && result.records.length > 0) {	
					passthru_params['import_tree'] = result.records[0];
				} else {
					throw('no records. result = ' + js2JSON(result) + '\n');
				}
			} else {
				throw('result: ' + js2JSON(result) + '\n');
			}
			spawn_marc_editor(d,placement,place,passthru_params);
		}
	} catch(E) {
		mw.handle_error(E);
	}
}

function spawn_patron_edit(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/patron/patron_edit.xul';
	return spawn_interface(d,placement,place,chrome,getString('patron_editor_interface_label'),passthru_params,clone);
}

function spawn_patron_register(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/patron/patron_new_legacy.xul';
	return spawn_interface(d,placement,place,chrome,getString('patron_register_interface_label'),passthru_params,clone);
}

function spawn_copy_stat_cat_edit(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/stat_cat/copy_stat_cat_editor.xul';
	return spawn_interface(d,placement,place,chrome,getString('copy_stat_cat_editor_interface'),passthru_params,clone);
}

function spawn_patron_stat_cat_edit(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/stat_cat/patron_stat_cat_editor.xul';
	return spawn_interface(d,placement,place,chrome,getString('patron_stat_cat_editor_interface'),passthru_params,clone);
}

function spawn_survey_admin_wizard(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/survey/survey_wizard.xul';
	return spawn_interface(d,placement,place,chrome,getString('survey_admin_interface_label'),passthru_params,clone);
}

function spawn_z3950_import(d,placement,place,passthru_params,clone) {
	var chrome = 'chrome://evergreen/content/z39_50/z39_50.xul';
	return spawn_interface(d,placement,place,chrome,getString('z39_50_import_interface_label'),passthru_params,clone);
}


