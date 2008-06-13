dump('entering cat/util.js\n');

function $(id) { return document.getElementById(id); }

if (typeof cat == 'undefined') var cat = {};
cat.util = {};

cat.util.EXPORT_OK	= [ 
	'spawn_copy_editor', 'add_copies_to_bucket', 'show_in_opac', 'spawn_spine_editor', 'transfer_copies', 
	'mark_item_missing', 'mark_item_damaged', 'replace_barcode',
];
cat.util.EXPORT_TAGS	= { ':all' : cat.util.EXPORT_OK };

cat.util.replace_barcode = function(old_bc) {
	try {
		JSAN.use('util.network');
		var network = new util.network();

		if (!old_bc) old_bc = window.prompt($("catStrings").getString('staff.cat.util.replace_barcode.old_bc_window_prompt.prompt'),
			'',
			$("catStrings").getString('staff.cat.util.replace_barcode.old_bc_window_prompt.title'));
		if (!old_bc) return;

		var copy;
        try {
			copy = network.simple_request('FM_ACP_RETRIEVE_VIA_BARCODE',[ old_bc ]);
			if (typeof copy.ilsevent != 'undefined') throw(copy); 
			if (!copy) throw(copy);
		} catch(E) {
			alert($("catStrings").getFormattedString('staff.cat.util.replace_barcode.error_alert', [old_bc]) + '\n');
			return old_bc;
		}
	
		// Why did I want to do this twice?  Because this copy is more fleshed?
		try {
			copy = network.simple_request('FM_ACP_RETRIEVE',[ copy.id() ]);
			if (typeof copy.ilsevent != 'undefined') throw(copy);
			if (!copy) throw(copy);
		} catch(E) {
			try {
				alert($("catStrings").getFormattedString('staff.cat.util.replace_barcode.error_alert', [old_bc]) +
					 '\n' + (typeof E.ilsevent == 'undefined' ? '' : E.textcode + ' : ' + E.desc));
			} catch(F) {
				alert(E + '\n' + F);
			}
			return old_bc;
		}
	
		var new_bc = window.prompt($("catStrings").getString('staff.cat.util.replace_barcode.new_bc_window_prompt.prompt'),
			'',
			$("catStrings").getString('staff.cat.util.replace_barcode.new_bc_window_prompt.title'));
		new_bc = String( new_bc ).replace(/\s/g,'');
		if (!new_bc) {
			alert($("catStrings").getString('staff.cat.util.replace_barcode.new_bc.failed'));
			return old_bc;
		}
	
		var test = network.simple_request('FM_ACP_RETRIEVE_VIA_BARCODE',[ new_bc ]);
		if (typeof test.ilsevent == 'undefined') {
			alert('Rename aborted.  Another copy has barcode "' + new_bc + '".');
			return old_bc;
		} else {
			if (test.ilsevent != 1502 /* ASSET_COPY_NOT_FOUND */) {
				obj.error.standard_unexpected_error_alert($("catStrings").getFormattedString('staff.cat.util.replace_barcode.testing_error', [new_bc]), test);
				return old_bc;
			}	
		}

		copy.barcode(new_bc); copy.ischanged('1');
		var r = network.simple_request('FM_ACP_FLESHED_BATCH_UPDATE', [ ses(), [ copy ] ]);
		if (typeof r.ilsevent != 'undefined') { 
			if (r.ilsevent != 0) {
				if (r.ilsevent == 5000 /* PERM_FAILURE */) {
					alert($("catStrings").getString('staff.cat.util.replace_barcode.insufficient_permission_for_rename'));
					return old_bc;
				} else {
					obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.util.replace_barcode.item_rename_error'),r);
					return old_bc;
				}
			}
		}

		return new_bc;
	} catch(E) {
		JSAN.use('util.error'); var error = new util.error();
		error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.util.replace_barcode.rename_error'),E);
		return old_bc;
	}
}

cat.util.transfer_copies = function(params) {
	JSAN.use('util.error'); var error = new util.error();
	JSAN.use('OpenILS.data'); var data = new OpenILS.data();
	JSAN.use('util.network'); var network = new util.network();
	try {
		data.stash_retrieve();
		if (!data.marked_volume) {
			alert($("catStrings").getString('staff.cat.util.transfer_copies.unmarked_volume_alert'));
			return;
		}
		netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
		var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: auto">';
		if (!params.message) {
			params.message = $("catStrings").getFormattedString('staff.cat.util.transfer_copies.params_message', [data.hash.aou[ params.owning_lib ].shortname(), params.volume_label]);
			//params.message = 'Transfer items from their original volumes to ';
			//params.message += data.hash.aou[ params.owning_lib ].shortname() + "'s volume labelled ";
			//params.message += '"' + params.volume_label + '" on the following record (and change their circ libs to match)?';
		}

		xml += '<description>' + params.message.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;') + '</description>';
		xml += '<hbox><button label="' + $("catStrings").getString('staff.cat.util.transfer_copies.transfer.label')+ '" name="fancy_submit"/>';
		xml += '<button label="' + $("catStrings").getString('staff.cat.util.transfer_copies.cancel.label');
		xml += '" accesskey="'+ $("catStrings").getString('staff.cat.util.transfer_copies.cancel.accesskey') +'" name="fancy_cancel"/></hbox>';
		xml += '<iframe style="overflow: scroll" flex="1" src="' + urls.XUL_BIB_BRIEF + '?docid=' + params.docid + '"/>';
		xml += '</vbox>';
		//data.temp_transfer = xml; data.stash('temp_transfer');
		JSAN.use('util.window'); var win = new util.window();
		var fancy_prompt_data = win.open(
			urls.XUL_FANCY_PROMPT,
			//+ '?xml_in_stash=temp_transfer'
			//+ '&title=' + window.escape('Item Transfer'),
			'fancy_prompt', 'chrome,resizable,modal,width=500,height=300',
			{ 'xml' : xml, 'title' : $("catStrings").getString('staff.cat.util.transfer_copies.window_title') }
		);
		if (fancy_prompt_data.fancy_status == 'incomplete') { alert($("catStrings").getString('staff.cat.util.transfer_copies.aborted_transfer')); return; }

		JSAN.use('util.functional');

		var copies = network.simple_request('FM_ACP_FLESHED_BATCH_RETRIEVE.authoritative', [ params.copy_ids ]);

		for (var i = 0; i < copies.length; i++) {
			copies[i].call_number( data.marked_volume );
			copies[i].circ_lib( params.owning_lib );
			copies[i].ischanged( 1 );
		}

		var robj = network.simple_request(
			'FM_ACP_FLESHED_BATCH_UPDATE', 
			[ ses(), copies, true ], 
			null,
			{
				'title' : $("catStrings").getString('staff.cat.util.transfer_copies.override_transfer_failure'),
				'overridable_events' : [
					1208 /* TITLE_LAST_COPY */,
					1227 /* COPY_DELETE_WARNING */,
				]
			}
		);
		
		if (typeof robj.ilsevent != 'undefined') {
			throw(robj);
		} else {
			alert($("catStrings").getString('staff.cat.util.transfer_copies.successful_transfer'));
		}

	} catch(E) {
		error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.util.transfer_copies.transfer_error'),E);
	}
}

cat.util.spawn_spine_editor = function(selection_list) {
	JSAN.use('util.error'); var error = new util.error();
	try {
		JSAN.use('util.functional');
		JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.stash_retrieve();
		data.temp_barcodes_for_labels = util.functional.map_list( selection_list, function(o){return o.barcode;}) ; 
		data.stash('temp_barcodes_for_labels');
		xulG.new_tab(
			xulG.url_prefix( urls.XUL_SPINE_LABEL ),
			{ 'tab_name' : $("catStrings").getString('staff.cat.util.spine_editor.tab_name') },
			{}
		);
	} catch(E) {
		error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.util.spine_editor.spine_editor_error'),E);
	}
}

cat.util.show_in_opac = function(selection_list) {
	JSAN.use('util.error'); var error = new util.error();
	var doc_id; var seen = {};
	try {
		for (var i = 0; i < selection_list.length; i++) {
			doc_id = selection_list[i].doc_id;
			if (!doc_id) {
				alert($("catStrings").getFormattedString('staff.cat.util.show_in_opac.unknown_barcode', [selection_list[i].barcode]));
				continue;
			}
			if (typeof seen[doc_id] != 'undefined') {
				continue;
			}
			seen[doc_id] = true;
			var opac_url = xulG.url_prefix( urls.opac_rdetail ) + '?r=' + doc_id;
			var content_params = { 
				'session' : ses(),
				'authtime' : ses('authtime'),
				'opac_url' : opac_url,
			};
			xulG.new_tab(
				xulG.url_prefix(urls.XUL_OPAC_WRAPPER), 
				{'tab_name':'Retrieving title...'}, 
				content_params
			);
		}
	} catch(E) {
		error.standard_unexpected_error_alert($("catStrings").getFormattedString('staff.cat.util.show_in_opac.catalog_error_for_doc_id', [doc_id]),E);
	}
}

cat.util.add_copies_to_bucket = function(selection_list) {
	JSAN.use('util.functional');
	JSAN.use('util.window'); var win = new util.window();
	JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
	data.cb_temp_copy_ids = js2JSON(
		util.functional.map_list(
			selection_list,
			function (o) {
				if (typeof o.copy_id != 'undefined' && o.copy_id != null) {
					return o.copy_id;
				} else {
					return o;
				}
			}
		)
	);
	data.stash('cb_temp_copy_ids');
	win.open( 
		xulG.url_prefix(urls.XUL_COPY_BUCKETS_QUICK),
		'sel_bucket_win' + win.window_name_increment(),
		'chrome,resizable,center'
	);
}

cat.util.spawn_copy_editor = function(params) {
	try {
        if (!params.copy_ids && !params.copies) return;
		if (params.copy_ids && params.copy_ids.length == 0) return;
		if (params.copies && params.copies.length == 0) return;
        if (params.copy_ids) params.copy_ids = js2JSON(params.copy_ids); // legacy
        if (!params.caller_handles_update) params.handle_update = 1; // legacy

		var obj = {};
		JSAN.use('util.network'); obj.network = new util.network();
		JSAN.use('util.error'); obj.error = new util.error();
	
		var title = '';
		if (params.copy_ids && params.copy_ids.length > 1 && params.edit == 1)
			title += $("catStrings").getString('staff.cat.util.copy_editor.batch_edit');
		else if(params.copies && params.copies.length > 1 && params.edit == 1)
			title += $("catStrings").getString('staff.cat.util.copy_editor.batch_view');
		else if(params.copy_ids && params.copy_ids.length == 1)
			title += $("catStrings").getString('staff.cat.util.copy_editor.edit');
		else
			title += $("catStrings").getString('staff.cat.util.copy_editor.view');

		//FIXME I18N This is a constructed string! No can do! if ((params.copy_ids && params.copy_ids.length > 1) || (params.copies && params.copies.length > 1 )) title += $("catStrings").getString('staff.cat.util.copy_editor.batch_in_title');
		//title += params.edit == 1 ? $("catStrings").getString('staff.cat.util.copy_editor.edit_in_title') : $("catStrings").getString('staff.cat.util.copy_editor.view_in_title');
		//title += $("catStrings").getString('staff.cat.util.copy_editor.copy_attributes_in_title');
	
		JSAN.use('util.window'); var win = new util.window();
		var my_xulG = win.open(
			(urls.XUL_COPY_EDITOR),
			title,
			'chrome,modal,resizable',
            params
		);
		if (!my_xulG.copies && params.edit) {
            alert(typeof params.no_copies_modified_msg != 'undefined' ? params.no_copies_modified_msg : $("catStrings").getString('staff.cat.util.copy_editor.not_modified'));
        } else {
            return my_xulG.copies;
        }
        return [];
	} catch(E) {
		JSAN.use('util.error'); var error = new util.error();
		error.standard_unexpected_error_alert('error in cat.util.spawn_copy_editor',E);
	}
}

cat.util.mark_item_damaged = function(copy_ids) {
	var error;
	try {
		JSAN.use('util.error'); error = new util.error();
		JSAN.use('util.functional');
		JSAN.use('util.network'); var network = new util.network();
		var copies = network.simple_request('FM_ACP_FLESHED_BATCH_RETRIEVE.authoritative', [ copy_ids ]);
		if (typeof copies.ilsevent != 'undefined') throw(copies);
		var magic_status = false;
		for (var i = 0; i < copies.length; i++) {
			var status = copies[i].status(); if (typeof status == 'object') status = status.id();
			if (typeof my_constants.magical_statuses[ status ] != 'undefined') 
				if (my_constants.magical_statuses[ status ].block_mark_item_action) magic_status = true;
		}
		if (magic_status) {
		
			error.yns_alert($("catStrings").getString('staff.cat.util.mark_item_damaged.af_message'),
				$("catStrings").getString('staff.cat.util.mark_item_damaged.af_title'),
				$("catStrings").getString('staff.cat.util.mark_item_damaged.af_ok_label'), null, null,
				$("catStrings").getString('staff.cat.util.mark_item_damaged.af_confirm_action'));

		} else {

			var r = error.yns_alert($("catStrings").getFormattedString('staff.cat.util.mark_item_damaged.md_message', [util.functional.map_list( copies, function(o) { return o.barcode(); } ).join(", ")]),
				$("catStrings").getString('staff.cat.util.mark_item_damaged.md_title'),
				$("catStrings").getString('staff.cat.util.mark_item_damaged.md_ok_label'),
				$("catStrings").getString('staff.cat.util.mark_item_damaged.md_cancel_label'), null,
				$("catStrings").getString('staff.cat.util.mark_item_damaged.md_confirm_action'));

			if (r == 0) {
				var count = 0;
				for (var i = 0; i < copies.length; i++) {
					try {
						var robj = network.simple_request('MARK_ITEM_DAMAGED',[ses(),copies[i].id()]);
						if (typeof robj.ilsevent != 'undefined') throw(robj);
						count++;
					} catch(E) {
						error.standard_unexpected_error_alert($("catStrings").getFormattedString('staff.cat.util.mark_item_damaged.marking_error', [copies[i].barcode()]),E);
					}
				}
				alert(count == 1 ? $("catStrings").getString('staff.cat.util.mark_item_damaged.one_item_damaged') :
					$("catStrings").getFormattedString('staff.cat.util.mark_item_damaged.multiple_item_damaged', [count]));
			}
		}

	} catch(E) {
		if (error) error.standard_unexpected_error_alert('cat.util.mark_item_damaged',E); else alert('FIXME: ' + E);
	}
}

cat.util.mark_item_missing = function(copy_ids) {
	var error;
	try {
		JSAN.use('util.error'); error = new util.error();
		JSAN.use('util.functional');
		JSAN.use('util.network'); var network = new util.network();
		var copies = network.simple_request('FM_ACP_FLESHED_BATCH_RETRIEVE.authoritative', [ copy_ids ]);
		if (typeof copies.ilsevent != 'undefined') throw(copies);
		var magic_status = false;
		for (var i = 0; i < copies.length; i++) {
			var status = copies[i].status(); if (typeof status == 'object') status = status.id();
			if (typeof my_constants.magical_statuses[ status ] != 'undefined') 
				if (my_constants.magical_statuses[ status ].block_mark_item_action) magic_status = true;
		}
		if (magic_status) {
		
			error.yns_alert($("catStrings").getString('staff.cat.util.mark_item_missing.af_message'),
				$("catStrings").getString('staff.cat.util.mark_item_missing.af_title'),
				$("catStrings").getString('staff.cat.util.mark_item_missing.af_ok_label'), null, null,
				$("catStrings").getString('staff.cat.util.mark_item_missing.af_confirm_action'));

		} else {

			var r = error.yns_alert($("catStrings").getFormattedString('staff.cat.util.mark_item_missing.ms_message', [util.functional.map_list( copies, function(o) { return o.barcode(); } ).join(", ")]),
				$("catStrings").getString('staff.cat.util.mark_item_missing.ms_title'),
				$("catStrings").getString('staff.cat.util.mark_item_missing.ms_ok_label'),
				$("catStrings").getString('staff.cat.util.mark_item_missing.ms_cancel_label'), null,
				$("catStrings").getString('staff.cat.util.mark_item_missing.ms_confirm_action'));

			if (r == 0) {
				var count = 0;
				for (var i = 0; i < copies.length; i++) {
					try {
						var robj = network.simple_request('MARK_ITEM_MISSING',[ses(),copies[i].id()]);
						if (typeof robj.ilsevent != 'undefined') throw(robj);
						count++;
					} catch(E) {
						error.standard_unexpected_error_alert($("catStrings").getFormattedString('staff.cat.util.mark_item_missing.marking_error', [copies[i].barcode()]),E);
					}
				}
				alert(count == 1 ? $("catStrings").getString('staff.cat.util.mark_item_missing.one_item_missing') :
					$("catStrings").getFormattedString('staff.cat.util.mark_item_missing.multiple_item_missing', [count]));
			}
		}

	} catch(E) {
		if (error) error.standard_unexpected_error_alert('cat.util.mark_item_missing',E); else alert('FIXME: ' + E);
	}
}


dump('exiting cat/util.js\n');
