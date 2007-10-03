dump('entering cat/util.js\n');

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

		if (!old_bc) old_bc = window.prompt('Enter original barcode for the copy:','','Replace Barcode');
		if (!old_bc) return;

		var copy;
        try {
			copy = network.simple_request('FM_ACP_RETRIEVE_VIA_BARCODE',[ old_bc ]);
			if (typeof copy.ilsevent != 'undefined') throw(copy); 
			if (!copy) throw(copy);
		} catch(E) {
			alert('We were unable to retrieve an item with barcode "' + old_bc + '".\n');
			return old_bc;
		}
	
		// Why did I want to do this twice?  Because this copy is more fleshed?
		try {
			copy = network.simple_request('FM_ACP_RETRIEVE',[ copy.id() ]);
			if (typeof copy.ilsevent != 'undefined') throw(copy);
			if (!copy) throw(copy);
		} catch(E) {
			try { alert('We were unable to retrieve an item with barcode "' + old_bc + '".\n' + (typeof E.ilsevent == 'undefined' ? '' : E.textcode + ' : ' + E.desc)); } catch(F) { alert(E + '\n' + F); }
			return old_bc;
		}
	
		var new_bc = window.prompt('Enter the replacement barcode for the copy:','','Replace Barcode');
		new_bc = String( new_bc ).replace(/\s/g,'');
		if (!new_bc) {
			alert('Rename aborted.  Blank for barcode not allowed.');
			return old_bc;
		}
	
		var test = network.simple_request('FM_ACP_RETRIEVE_VIA_BARCODE',[ new_bc ]);
		if (typeof test.ilsevent == 'undefined') {
			alert('Rename aborted.  Another copy has barcode "' + new_bc + '".');
			return old_bc;
		} else {
			if (test.ilsevent != 1502 /* ASSET_COPY_NOT_FOUND */) {
				obj.error.standard_unexpected_error_alert('Error testing replacement barcode "' . new_bc . '".',test);
				return old_bc;
			}	
		}

		copy.barcode(new_bc); copy.ischanged('1');
		var r = network.simple_request('FM_ACP_FLESHED_BATCH_UPDATE', [ ses(), [ copy ] ]);
		if (typeof r.ilsevent != 'undefined') { 
			if (r.ilsevent != 0) {
				if (r.ilsevent == 5000 /* PERM_FAILURE */) {
					alert('Renamed aborted.  Insufficient permission.');
					return old_bc;
				} else {
					obj.error.standard_unexpected_error_alert('Error renaming item.',r);
					return old_bc;
				}
			}
		}

		return new_bc;
	} catch(E) {
		JSAN.use('util.error'); var error = new util.error();
		error.standard_unexpected_error_alert('Rename did not likely occur.',E);
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
			alert('Please mark a volume as the destination from within holdings maintenance and then try this again.');
			return;
		}
		netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
		var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: auto">';
		if (!params.message) {
			params.message = 'Transfer items from their original volumes to ';
			params.message += data.hash.aou[ params.owning_lib ].shortname() + "'s volume labelled ";
			params.message += '"' + params.volume_label + '" on the following record (and change their circ libs to match)?';
		}

		xml += '<description>' + params.message.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;') + '</description>';
		xml += '<hbox><button label="Transfer" name="fancy_submit"/>';
		xml += '<button label="Cancel" accesskey="C" name="fancy_cancel"/></hbox>';
		xml += '<iframe style="overflow: scroll" flex="1" src="' + urls.XUL_BIB_BRIEF + '?docid=' + params.docid + '"/>';
		xml += '</vbox>';
		//data.temp_transfer = xml; data.stash('temp_transfer');
		JSAN.use('util.window'); var win = new util.window();
		var fancy_prompt_data = win.open(
			urls.XUL_FANCY_PROMPT,
			//+ '?xml_in_stash=temp_transfer'
			//+ '&title=' + window.escape('Item Transfer'),
			'fancy_prompt', 'chrome,resizable,modal,width=500,height=300',
			{ 'xml' : xml, 'title' : 'Item Transfer' }
		);
		if (fancy_prompt_data.fancy_status == 'incomplete') { alert('Transfer Aborted'); return; }

		JSAN.use('util.functional');

		var copies = network.simple_request('FM_ACP_FLESHED_BATCH_RETRIEVE', [ params.copy_ids ]);

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
				'title' : 'Override Transfer Failure?',
				'overridable_events' : [
					1208 /* TITLE_LAST_COPY */,
					1227 /* COPY_DELETE_WARNING */,
				]
			}
		);
		
		if (typeof robj.ilsevent != 'undefined') {
			throw(robj);
		} else {
			alert('Items transferred.');
		}

	} catch(E) {
		error.standard_unexpected_error_alert('All items not likely transferred.',E);
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
			{ 'tab_name' : 'Spine Labels' },
			{}
		);
	} catch(E) {
		error.standard_unexpected_error_alert('Spine Labels',E);
	}
}

cat.util.show_in_opac = function(selection_list) {
	JSAN.use('util.error'); var error = new util.error();
	var doc_id; var seen = {};
	try {
		for (var i = 0; i < selection_list.length; i++) {
			doc_id = selection_list[i].doc_id;
			if (!doc_id) {
				alert(selection_list[i].barcode + ' is not cataloged');
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
		error.standard_unexpected_error_alert('Error opening catalog for document id = ' + doc_id,E);
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

cat.util.spawn_copy_editor = function(list,edit) {
	try {
		var obj = {};
		JSAN.use('util.network'); obj.network = new util.network();
		JSAN.use('util.error'); obj.error = new util.error();
	
		if (list.length == 0) return;
	
		var title = list.length == 1 ? '' : 'Batch '; 
		title += edit == 1 ? 'Edit' : 'View';
		title += ' Copy Attributes';
	
		JSAN.use('util.window'); var win = new util.window();
		//JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
		//obj.data.temp_copies = undefined; obj.data.stash('temp_copies');
		//obj.data.temp_callnumbers = undefined; obj.data.stash('temp_callnumbers');
		//obj.data.temp_copy_ids = js2JSON(list); obj.data.stash('temp_copy_ids');
		var my_xulG = win.open(
			//window.xulG.url_prefix(urls.XUL_COPY_EDITOR),
			(urls.XUL_COPY_EDITOR),
			//	+'?handle_update=1&edit='+edit,
			title,
			'chrome,modal,resizable',
			{
				'handle_update' : 1,
				'edit' : edit,
				'copy_ids' : js2JSON(list),
			}
		);
		//obj.data.stash_retrieve();
		if (!my_xulG.copies) alert('Copies not modified.');
		//if (!obj.data.temp_copies) alert('Copies not modified.');
		//obj.data.temp_copies = undefined; obj.data.stash('temp_copies');
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
		var copies = network.simple_request('FM_ACP_FLESHED_BATCH_RETRIEVE', [ copy_ids ]);
		if (typeof copies.ilsevent != 'undefined') throw(copies);
		var magic_status = false;
		for (var i = 0; i < copies.length; i++) {
			var status = copies[i].status(); if (typeof status == 'object') status = status.id();
			if (typeof my_constants.magical_statuses[ status ] != 'undefined') 
				if (my_constants.magical_statuses[ status ].block_mark_item_action) magic_status = true;
		}
		if (magic_status) {
		
			error.yns_alert('Action failed.  One or more of these items is in a special status (Checked Out, In Transit, etc.) and cannot be changed to the Damaged status.','Action failed.','OK',null,null,'Check here to confirm this message');

		} else {

			var r = error.yns_alert('Change the status for these items to Damaged?  You will have to manually retrieve the last circulation if you need to bill a patron.  Barcodes: ' + util.functional.map_list( copies, function(o) { return o.barcode(); } ).join(", "), 'Mark Damaged', 'OK', 'Cancel', null, 'Check here to confirm this action');

			if (r == 0) {
				var count = 0;
				for (var i = 0; i < copies.length; i++) {
					try {
						var robj = network.simple_request('MARK_ITEM_DAMAGED',[ses(),copies[i].id()]);
						if (typeof robj.ilsevent != 'undefined') throw(robj);
						count++;
					} catch(E) {
						error.standard_unexpected_error_alert('Error marking item ' + copies[i].barcode() + ' damaged.',E);
					}
				}
				alert(count == 1 ? 'Item marked Damaged' : count + ' items marked Damaged.');
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
		var copies = network.simple_request('FM_ACP_FLESHED_BATCH_RETRIEVE', [ copy_ids ]);
		if (typeof copies.ilsevent != 'undefined') throw(copies);
		var magic_status = false;
		for (var i = 0; i < copies.length; i++) {
			var status = copies[i].status(); if (typeof status == 'object') status = status.id();
			if (typeof my_constants.magical_statuses[ status ] != 'undefined') 
				if (my_constants.magical_statuses[ status ].block_mark_item_action) magic_status = true;
		}
		if (magic_status) {
		
			error.yns_alert('Action failed.  One or more of these items is in a special status (Checked Out, In Transit, etc.) and cannot be changed to the Missing status.','Action failed.','OK',null,null,'Check here to confirm this message');

		} else {

			var r = error.yns_alert('Change the status for these items to Missing?  Barcodes: ' + util.functional.map_list( copies, function(o) { return o.barcode(); } ).join(", "), 'Mark Missing', 'OK', 'Cancel', null, 'Check here to confirm this action');

			if (r == 0) {
				var count = 0;
				for (var i = 0; i < copies.length; i++) {
					try {
						var robj = network.simple_request('MARK_ITEM_MISSING',[ses(),copies[i].id()]);
						if (typeof robj.ilsevent != 'undefined') throw(robj);
						count++;
					} catch(E) {
						error.standard_unexpected_error_alert('Error marking item ' + copies[i].barcode() + ' missing.',E);
					}
				}
				alert(count == 1 ? 'Item marked Missing' : count + ' items marked Missing.');
			}
		}

	} catch(E) {
		if (error) error.standard_unexpected_error_alert('cat.util.mark_item_missing',E); else alert('FIXME: ' + E);
	}
}


dump('exiting cat/util.js\n');
