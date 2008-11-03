dump('entering circ/util.js\n');

if (typeof circ == 'undefined') var circ = {};
circ.util = {};

circ.util.EXPORT_OK	= [ 
	'offline_checkout_columns', 'offline_checkin_columns', 'offline_renew_columns', 'offline_inhouse_use_columns', 
	'columns', 'hold_columns', 'checkin_via_barcode', 'std_map_row_to_columns', 
	'show_last_few_circs', 'abort_transits', 'transit_columns', 'renew_via_barcode',
];
circ.util.EXPORT_TAGS	= { ':all' : circ.util.EXPORT_OK };

circ.util.abort_transits = function(selection_list) {
	var obj = {};
	JSAN.use('util.error'); obj.error = new util.error();
	JSAN.use('util.network'); obj.network = new util.network();
	JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
	JSAN.use('util.functional');
	var msg = 'Are you sure you would like to abort transits for copies:' + util.functional.map_list( selection_list, function(o){return o.copy_id;}).join(', ') + '?';
	var r = obj.error.yns_alert(msg,'Aborting Transits','Yes','No',null,'Check here to confirm this action');
	if (r == 0) {
		try {
			for (var i = 0; i < selection_list.length; i++) {
				var copy_id = selection_list[i].copy_id;
				var robj = obj.network.simple_request('FM_ATC_VOID',[ ses(), { 'copyid' : copy_id } ]);
				if (typeof robj.ilsevent != 'undefined') {
					switch(robj.ilsevent) {
						case 1225 /* TRANSIT_ABORT_NOT_ALLOWED */ :
							alert('Copy Id = ' + copy_id + '\n' + robj.desc);
						break;
						case 1504 /* ACTION_TRANSIT_COPY_NOT_FOUND */ :
							alert('This item was no longer in transit at the time of the abort.  Perhaps this happened from a stale display?');
						break;
						case 5000 /* PERM_FAILURE */ :
						break;
						default:
							throw(robj);
						break;
					}
				}
			}
		} catch(E) {
			obj.error.standard_unexpected_error_alert('Transit not likely aborted.',E);
		}
	}
}

circ.util.show_copy_details = function(copy_id) {
	var obj = {};
	JSAN.use('util.error'); obj.error = new util.error();
	JSAN.use('util.window'); obj.win = new util.window();
	JSAN.use('util.network'); obj.network = new util.network();
	JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});

	if (typeof copy_id == 'object' && copy_id != null) copy_id = copy_id.id();

	try {
		var url = xulG.url_prefix( urls.XUL_COPY_DETAILS ); // + '?copy_id=' + copy_id;
		var my_xulG = obj.win.open( url, 'show_copy_details', 'chrome,resizable,modal', { 'copy_id' : copy_id } );

		if (typeof my_xulG.retrieve_these_patrons == 'undefined') return;
		var patrons = my_xulG.retrieve_these_patrons;
		for (var j = 0; j < patrons.length; j++) {
			if (typeof window.xulG == 'object' && typeof window.xulG.new_tab == 'function') {
				try {
					var url = urls.XUL_PATRON_DISPLAY; // + '?id=' + window.escape( patrons[j] );
					window.xulG.new_tab( url, {}, { 'id' : patrons[j] } );
				} catch(E) {
					obj.error.standard_unexpected_error_alert('Problem retrieving patron.',E);
				}
			}
		}

	} catch(E) {
		obj.error.standard_unexpected_error_alert('Problem retrieving copy details.',E);
	}
}


circ.util.show_last_few_circs = function(selection_list,count) {
	var obj = {};
	JSAN.use('util.error'); obj.error = new util.error();
	JSAN.use('util.window'); obj.win = new util.window();
	JSAN.use('util.network'); obj.network = new util.network();
	JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});

	if (!count) count = 4;

	for (var i = 0; i < selection_list.length; i++) {
		try {
			if (typeof selection_list[i].copy_id == 'undefined' || selection_list[i].copy_id == null) continue;
			var url = xulG.url_prefix( urls.XUL_CIRC_SUMMARY ); // + '?copy_id=' + selection_list[i].copy_id + '&count=' + count;
			var my_xulG = obj.win.open( url, 'show_last_few_circs', 'chrome,resizable,modal', { 'copy_id' : selection_list[i].copy_id, 'count' : count } );

			if (typeof my_xulG.retrieve_these_patrons == 'undefined') continue;
			var patrons = my_xulG.retrieve_these_patrons;
			for (var j = 0; j < patrons.length; j++) {
				if (typeof window.xulG == 'object' && typeof window.xulG.new_tab == 'function') {
					try {
						var url = urls.XUL_PATRON_DISPLAY; // + '?id=' + window.escape( patrons[j] );
						window.xulG.new_tab( url, {}, { 'id' : patrons[j] } );
					} catch(E) {
						obj.error.standard_unexpected_error_alert('Problem retrieving patron.',E);
					}
				}
			}

		} catch(E) {
			obj.error.standard_unexpected_error_alert('Problem retrieving circulations.',E);
		}
	}
}

circ.util.offline_checkout_columns = function(modify,params) {
	
	var c = [
		{ 
			'id' : 'timestamp', 
			'label' : 'Timestamp', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : function(my) { return my.timestamp; },
		},
		{ 
			'id' : 'checkout_time', 
			'label' : 'Check Out Time', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : function(my) { return my.checkout_time; },
		},
		{ 
			'id' : 'type', 
			'label' : 'Transaction Type', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : function(my) { return my.type; }, 
		},
		{
			'id' : 'noncat',
			'label' : 'Non-Cataloged?',
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : function(my) { return my.noncat; },
		},
		{
			'id' : 'noncat_type',
			'label' : 'Non-Cat Type ID',
			'flex' : 1, 'primary' : false, 'hidden' : true,
			'render' : function(my) { return my.noncat_type; },
		},
		{
			'id' : 'noncat_count',
			'label' : 'Count', 'sort_type' : 'number',
			'flex' : 1, 'primary' : false, 'hidden' : false,
			'render' : function(my) { return my.noncat_count; },
		},
		{ 
			'id' : 'patron_barcode', 
			'label' : 'Patron Barcode', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : function(my) { return my.patron_barcode; },
		},
		{ 
			'id' : 'barcode', 
			'label' : 'Item Barcode', 
			'flex' : 2, 'primary' : true, 'hidden' : false, 
			'render' : function(my) { return my.barcode; },
		},
		{ 
			'id' : 'due_date', 
			'label' : 'Due Date', 
			'flex' : 1, 'primary' : false, 'hidden' : false, 
			'render' : function(my) { return my.due_date; },
		},
	];
	if (modify) for (var i = 0; i < c.length; i++) {
		if (modify[ c[i].id ]) {
			for (var j in modify[ c[i].id ]) {
				c[i][j] = modify[ c[i].id ][j];
			}
		}
	}
	if (params) {
		if (params.just_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < params.just_these.length; i++) {
				var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
				new_c.push( function(y){ return y; }( x ) );
			}
			c = new_c;
		}
		if (params.except_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < c.length; i++) {
				var x = util.functional.find_list(params.except_these,function(d){return(d==c[i].id);});
				if (!x) new_c.push(c[i]);
			}
			c = new_c;
		}

	}
	return c.sort( function(a,b) { if (a.label < b.label) return -1; if (a.label > b.label) return 1; return 0; } );
}

circ.util.offline_checkin_columns = function(modify,params) {
	
	var c = [
		{ 
			'id' : 'timestamp', 
			'label' : 'Timestamp', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : function(my) { return my.timestamp; },
		},
		{ 
			'id' : 'backdate', 
			'label' : 'Back Date', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : function(my) { return my.backdate; },
		},
		{ 
			'id' : 'type', 
			'label' : 'Transaction Type', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : function(my) { return my.type; },
		},
		{ 
			'id' : 'barcode', 
			'label' : 'Item Barcode', 
			'flex' : 2, 'primary' : true, 'hidden' : false, 
			'render' : function(my) { return my.barcode; },
		},
	];
	if (modify) for (var i = 0; i < c.length; i++) {
		if (modify[ c[i].id ]) {
			for (var j in modify[ c[i].id ]) {
				c[i][j] = modify[ c[i].id ][j];
			}
		}
	}
	if (params) {
		if (params.just_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < params.just_these.length; i++) {
				var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
				new_c.push( function(y){ return y; }( x ) );
			}
			c = new_c;
		}
		if (params.except_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < c.length; i++) {
				var x = util.functional.find_list(params.except_these,function(d){return(d==c[i].id);});
				if (!x) new_c.push(c[i]);
			}
			c = new_c;
		}

	}
	return c.sort( function(a,b) { if (a.label < b.label) return -1; if (a.label > b.label) return 1; return 0; } );
}

circ.util.offline_renew_columns = function(modify,params) {
	
	var c = [
		{ 
			'id' : 'timestamp', 
			'label' : 'Timestamp', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : function(my) { return my.timestamp; },
		},
		{ 
			'id' : 'checkout_time', 
			'label' : 'Check Out Time', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : function(my) { return my.checkout_time; },
		},
		{ 
			'id' : 'type', 
			'label' : 'Transaction Type', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : function(my) { return my.type; },
		},
		{ 
			'id' : 'patron_barcode', 
			'label' : 'Patron Barcode', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : function(my) { return my.patron_barcode; },
		},
		{ 
			'id' : 'barcode', 
			'label' : 'Item Barcode', 
			'flex' : 2, 'primary' : true, 'hidden' : false, 
			'render' : function(my) { return my.barcode; },
		},
		{ 
			'id' : 'due_date', 
			'label' : 'Due Date', 
			'flex' : 1, 'primary' : false, 'hidden' : false, 
			'render' : function(my) { return my.due_date; },
		},
	];
	if (modify) for (var i = 0; i < c.length; i++) {
		if (modify[ c[i].id ]) {
			for (var j in modify[ c[i].id ]) {
				c[i][j] = modify[ c[i].id ][j];
			}
		}
	}
	if (params) {
		if (params.just_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < params.just_these.length; i++) {
				var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
				new_c.push( function(y){ return y; }( x ) );
			}
			c = new_c;
		}
		if (params.except_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < c.length; i++) {
				var x = util.functional.find_list(params.except_these,function(d){return(d==c[i].id);});
				if (!x) new_c.push(c[i]);
			}
			c = new_c;
		}

	}
	return c.sort( function(a,b) { if (a.label < b.label) return -1; if (a.label > b.label) return 1; return 0; } );
}

circ.util.offline_inhouse_use_columns = function(modify,params) {
	
	var c = [
		{ 
			'id' : 'timestamp', 
			'label' : 'Timestamp', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : function(my) { return my.timestamp; },
		},
		{ 
			'id' : 'use_time', 
			'label' : 'Use Time', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : function(my) { return my.use_time; },
		},
		{ 
			'id' : 'type', 
			'label' : 'Transaction Type', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : function(my) { return my.type; },
		},
		{
			'id' : 'count',
			'label' : 'Count', 'sort_type' : 'number',
			'flex' : 1, 'primary' : false, 'hidden' : false,
			'render' : function(my) { return my.count; },
		},
		{ 
			'id' : 'barcode', 
			'label' : 'Item Barcode', 
			'flex' : 2, 'primary' : true, 'hidden' : false, 
			'render' : function(my) { return my.barcode; },
		},
	];
	if (modify) for (var i = 0; i < c.length; i++) {
		if (modify[ c[i].id ]) {
			for (var j in modify[ c[i].id ]) {
				c[i][j] = modify[ c[i].id ][j];
			}
		}
	}
	if (params) {
		if (params.just_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < params.just_these.length; i++) {
				var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
				new_c.push( function(y){ return y; }( x ) );
			}
			c = new_c;
		}
		if (params.except_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < c.length; i++) {
				var x = util.functional.find_list(params.except_these,function(d){return(d==c[i].id);});
				if (!x) new_c.push(c[i]);
			}
			c = new_c;
		}

	}
	return c.sort( function(a,b) { if (a.label < b.label) return -1; if (a.label > b.label) return 1; return 0; } );
}



circ.util.columns = function(modify,params) {
	
	JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
	JSAN.use('util.network'); var network = new util.network();
	JSAN.use('util.money');

	function getString(s) { return data.entities[s]; }

	var c = [
		{
			'id' : 'acp_id', 'label' : getString('staff.acp_label_id'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.acp.id(); }, 'persist' : 'hidden width ordinal',
		},
		{
			'id' : 'circ_id', 'label' : getString('staff.circ_label_id'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.circ ? my.circ.id() : ( my.acp.circulations() ? my.acp.circulations()[0].id() : ""); },
			'persist' : 'hidden width ordinal',
		},
		{
			'id' : 'mvr_doc_id', 'label' : getString('staff.mvr_label_doc_id'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.mvr.doc_id(); },
			'persist' : 'hidden width ordinal',
		},
		{
			'id' : 'barcode', 'label' : getString('staff.acp_label_barcode'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.acp.barcode(); },
			'persist' : 'hidden width ordinal',
		},
		{
			'id' : 'call_number', 'label' : getString('staff.acp_label_call_number'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { if (my.acp && my.acp.call_number() == -1) { return "Not Cataloged"; } else { if (!my.acn) { var x = network.simple_request("FM_ACN_RETRIEVE",[ my.acp.call_number() ]); if (x.ilsevent) { return "Not Cataloged"; } else { my.acn = x; return x.label(); } } else { return my.acn.label(); } } },
			'persist' : 'hidden width ordinal',
		},
		{
			'id' : 'owning_lib', 'label' : 'Owning Lib', 'flex' : 1,
			'primary' : false, 'hidden' : true,
			'render' : function(my) { if (Number(my.acn.owning_lib())>=0) { return data.hash.aou[ my.acn.owning_lib() ].shortname(); } else { return my.acn.owning_lib().shortname(); } }, 
			'persist' : 'hidden width ordinal',
		},
		{
			'id' : 'copy_number', 'label' : getString('staff.acp_label_copy_number'), 'flex' : 1, 'sort_type' : 'number',
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.acp.copy_number(); },
			'persist' : 'hidden width ordinal',
		},
		{
			'id' : 'location', 'label' : getString('staff.acp_label_location'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { if (Number(my.acp.location())>=0) return data.lookup("acpl", my.acp.location() ).name(); else return my.acp.location().name(); },
			'persist' : 'hidden width ordinal',
		},
		{
			'id' : 'loan_duration', 'label' : getString('staff.acp_label_loan_duration'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 
			'render' : function(my) { switch(my.acp.loan_duration()){ case 1: return "Short"; break; case 2: return "Normal"; break; case 3: return "Long"; break; }; },
			'persist' : 'hidden width ordinal',
		},
		{
			'id' : 'circ_lib', 'label' : getString('staff.acp_label_circ_lib'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { if (Number(my.acp.circ_lib())>=0) return data.hash.aou[ my.acp.circ_lib() ].shortname(); else return my.acp.circ_lib().shortname(); },
			'persist' : 'hidden width ordinal',
		},
		{
			'id' : 'fine_level', 'label' : getString('staff.acp_label_fine_level'), 'flex' : 1,
			'primary' : false, 'hidden' : true,
			'render' : function(my) { switch(my.acp.fine_level()){ case 1: return "Low"; break; case 2: return "Normal"; break; case 3: return "High"; break; }; },
			'persist' : 'hidden width ordinal',
		},
		{
			'id' : 'circulate', 'label' : 'Circulate?', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return get_bool( my.acp.circulate() ) ? "Yes" : "No"; },
			'persist' : 'hidden width ordinal',
		},
		{
			'id' : 'deleted', 'label' : 'Deleted?', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return get_bool( my.acp.deleted() ) ? "Yes" : "No"; },
			'persist' : 'hidden width ordinal',
		},
		{
			'id' : 'holdable', 'label' : 'Holdable?', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return get_bool( my.acp.holdable() ) ? "Yes" : "No"; },
			'persist' : 'hidden width ordinal',
		},
		{
			'id' : 'opac_visible', 'label' : 'OPAC Visible?', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return get_bool( my.acp.opac_visible() ) ? "Yes" : "No"; },
			'persist' : 'hidden width ordinal',
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'ref', 'label' : 'Reference?', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return get_bool( my.acp.ref() ) ? "Yes" : "No"; },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'deposit', 'label' : 'Deposit?', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return get_bool( my.acp.deposit() ) ? "Yes" : "No"; },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'deposit_amount', 'label' : getString('staff.acp_label_deposit_amount'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.acp.price() == null ? "<Unset>" : util.money.sanitize(my.acp.deposit_amount()); }, 'sort_type' : 'money',
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'price', 'label' : getString('staff.acp_label_price'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.acp.price() == null ? "<Unset>" : util.money.sanitize(my.acp.price()); }, 'sort_type' : 'money',
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'circ_as_type', 'label' : getString('staff.acp_label_circ_as_type'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.acp.circ_as_type(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'circ_modifier', 'label' : getString('staff.acp_label_circ_modifier'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.acp.circ_modifier(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'checkout_lib', 'label' : 'Checkout Lib', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.circ ? data.hash.aou[ my.circ.circ_lib() ].shortname() : ( my.acp.circulations() ? data.hash.aou[ my.acp.circulations()[0].circ_lib() ].shortname() : ""); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'xact_start_full', 'label' : 'Checkout Timestamp', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.circ ? my.circ.xact_start() : (my.acp.circulations() ? my.acp.circulations()[0].xact_start() : ""); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'checkin_time_full', 'label' : 'Checkin Timestamp', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.circ ? my.circ.checkin_time() : (my.acp.circulations() ? my.acp.circulations()[0].checkin_time() : ""); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'xact_start', 'label' : 'Checkout Date', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.circ ? my.circ.xact_start().substr(0,10) : (my.acp.circulations() ? my.acp.circulations()[0].xact_start().substr(0,10) : ""); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'checkin_time', 'label' : 'Checkin Date', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.circ ? my.circ.checkin_time().substr(0,10) : (my.acp.circulations() ? my.acp.circulations()[0].checkin_time().substr(0,10) : ""); },
		},

		{
			'persist' : 'hidden width ordinal', 'id' : 'xact_finish', 'label' : 'Transaction Finished', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.circ.xact_finish(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'due_date', 'label' : getString('staff.circ_label_due_date'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.circ ? my.circ.due_date().substr(0,10) : (my.acp.circulations() ? my.acp.circulations()[0].due_date().substr(0,10) : ""); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'create_date', 'label' : 'Date Created', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.acp.create_date().substr(0,10); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'edit_date', 'label' : 'Date Last Edited', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.acp.edit_date().substr(0,10); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'title', 'label' : getString('staff.mvr_label_title'), 'flex' : 2, 'sort_type' : 'title',
			'primary' : false, 'hidden' : true, 'render' : function(my) { try {  return my.mvr.title(); } catch(E) { return my.acp.dummy_title(); } }
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'author', 'label' : getString('staff.mvr_label_author'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { try { return my.mvr.author(); } catch(E) { return my.acp.dummy_author(); } }
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'edition', 'label' : 'Edition', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.mvr.edition(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'isbn', 'label' : 'ISBN', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.mvr.isbn(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'pubdate', 'label' : 'PubDate', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.mvr.pubdate(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'publisher', 'label' : 'Publisher', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.mvr.publisher(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'tcn', 'label' : 'TCN', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.mvr.tcn(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'renewal_remaining', 'label' : getString('staff.circ_label_renewal_remaining'), 'flex' : 0,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.circ ? my.circ.renewal_remaining() : (my.acp.circulations() ? my.acp.circulations()[0].renewal_remaining() : ""); }, 'sort_type' : 'number',
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'stop_fines', 'label' : 'Fines Stopped', 'flex' : 0,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.circ ? my.circ.stop_fines() : (my.acp.circulations() ? my.acp.circulations()[0].stop_fines() : ""); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'stop_fines_time', 'label' : 'Fines Stopped Time', 'flex' : 0,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.circ ? my.circ.stop_fines_time() : (my.acp.circulations() ? my.acp.circulations()[0].stop_fines_time() : ""); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'status', 'label' : getString('staff.acp_label_status'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { if (Number(my.acp.status())>=0) return data.hash.ccs[ my.acp.status() ].name(); else return my.acp.status().name(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'route_to', 'label' : 'Route To', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.route_to.toString(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'message', 'label' : 'Message', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.message.toString(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'uses', 'label' : '# of Uses', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.uses; }, 'sort_type' : 'number',
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'alert_message', 'label' : 'Alert Message', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.acp.alert_message(); },
		},
	];
	for (var i = 0; i < c.length; i++) {
		if (modify[ c[i].id ]) {
			for (var j in modify[ c[i].id ]) {
				c[i][j] = modify[ c[i].id ][j];
			}
		}
	}
	if (params) {
		if (params.just_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < params.just_these.length; i++) {
				var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
				new_c.push( function(y){ return y; }( x ) );
			}
			c = new_c;
		}
		if (params.except_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < c.length; i++) {
				var x = util.functional.find_list(params.except_these,function(d){return(d==c[i].id);});
				if (!x) new_c.push(c[i]);
			}
			c = new_c;
		}
	}
	return c.sort( function(a,b) { if (a.label < b.label) return -1; if (a.label > b.label) return 1; return 0; } );
}

circ.util.transit_columns = function(modify,params) {
	
	JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});

	function getString(s) { return data.entities[s]; }

	var c = [
		{
			'persist' : 'hidden width ordinal', 'id' : 'transit_item_barcode', 'label' : 'Barcode', 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.acp.barcode(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'transit_item_title', 'label' : 'Title', 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { try { return my.mvr.title(); } catch(E) { return my.acp.dummy_title(); } },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'transit_item_author', 'label' : 'Author', 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { try { return my.mvr.author(); } catch(E) { return my.acp.dummy_author(); } },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'transit_item_callnumber', 'label' : 'Call Number', 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.acn.label(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'transit_id', 'label' : 'Transit ID', 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.atc.id(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'transit_source', 'label' : 'Transit Source', 'flex' : 1,
			'primary' : false, 'hidden' : false, 'render' : function(my) { return typeof my.atc.source() == "object" ? my.atc.source().shortname() : data.hash.aou[ my.atc.source() ].shortname(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'transit_source_send_time', 'label' : 'Transitted On', 'flex' : 1,
			'primary' : false, 'hidden' : false, 'render' : function(my) { return my.atc.source_send_time(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'transit_dest_lib', 'label' : 'Transit Destination', 'flex' : 1,
			'primary' : false, 'hidden' : false, 'render' : function(my) { return typeof my.atc.dest() == "object" ? my.atc.dest().shortname() : data.hash.aou[ my.atc.dest() ].shortname(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'transit_dest_recv_time', 'label' : 'Transit Completed On', 'flex' : 1,
			'primary' : false, 'hidden' : false, 'render' : function(my) { return my.atc.dest_recv_time(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'transit_target_copy', 'label' : 'Transit Copy ID', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.atc.target_copy(); },
		},
	];
	for (var i = 0; i < c.length; i++) {
		if (modify[ c[i].id ]) {
			for (var j in modify[ c[i].id ]) {
				c[i][j] = modify[ c[i].id ][j];
			}
		}
	}
	if (params) {
		if (params.just_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < params.just_these.length; i++) {
				var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
				new_c.push( function(y){ return y; }( x ) );
			}
			c = new_c;
		}
		if (params.except_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < c.length; i++) {
				var x = util.functional.find_list(params.except_these,function(d){return(d==c[i].id);});
				if (!x) new_c.push(c[i]);
			}
			c = new_c;
		}

	}
	return c.sort( function(a,b) { if (a.label < b.label) return -1; if (a.label > b.label) return 1; return 0; } );
}


circ.util.hold_columns = function(modify,params) {
	
	JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});

	function getString(s) { return data.entities[s]; }

	var c = [
		{
			'persist' : 'hidden width ordinal', 'id' : 'request_lib', 'label' : 'Request Lib (Full Name)', 'flex' : 1,
			'primary' : false, 'hidden' : true,  
			'render' : function(my) { if (Number(my.ahr.request_lib())>=0) return data.hash.aou[ my.ahr.request_lib() ].name(); else return my.ahr.request_lib().name(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'request_lib_shortname', 'label' : 'Request Lib', 'flex' : 0,
			'primary' : false, 'hidden' : true,  
			'render' : function(my) { if (Number(my.ahr.request_lib())>=0) return data.hash.aou[ my.ahr.request_lib() ].shortname(); else return my.ahr.request_lib().shortname(); },
		},

		{
			'persist' : 'hidden width ordinal', 'id' : 'request_timestamp', 'label' : 'Request Timestamp', 'flex' : 0,
			'primary' : false, 'hidden' : true,  
			'render' : function(my) { return my.ahr.request_time().toString(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'request_time', 'label' : 'Request Date', 'flex' : 0,
			'primary' : false, 'hidden' : true,  
			'render' : function(my) { return my.ahr.request_time().toString().substr(0,10); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'available_timestamp', 'label' : 'Available On (Timestamp)', 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.ahr.transit() ? ( my.ahr.transit().dest_recv_time() ? my.ahr.transit().dest_recv_time().toString() : "") : ( my.ahr.capture_time() ? my.ahr.capture_time().toString() : "" ); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'available_time', 'label' : 'Available On', 'flex' : 1,
			'primary' : false, 'hidden' : false,  'render' : function(my) { return my.ahr.transit() ? ( my.ahr.transit().dest_recv_time() ? my.ahr.transit().dest_recv_time().toString().substr(0,10) : "") : ( my.ahr.capture_time() ? my.ahr.capture_time().toString().substr(0,10) : "" ); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'capture_timestamp', 'label' : 'Capture Timestamp', 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.ahr.capture_time() ? my.ahr.capture_time().toString() : ""; },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'capture_time', 'label' : 'Capture Date', 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.ahr.capture_time() ? my.ahr.capture_time().toString().substr(0,10) : ""; },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'status', 'label' : getString('staff.ahr_status_label'), 'flex' : 1,
			'primary' : false, 'hidden' : false,  'render' : function(my) { switch(my.status) { case 1: case "1": return "Waiting for copy"; break; case 2: case "2": return "Waiting for capture"; break; case 3: case "3": return "In-Transit"; break; case 4: case "4" : return "Ready for pickup"; break; default: return my.status; break;}; },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'hold_type', 'label' : getString('staff.ahr_hold_type_label'), 'flex' : 0,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.ahr.hold_type(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'pickup_lib', 'label' : 'Pickup Lib (Full Name)', 'flex' : 1,
			'primary' : false, 'hidden' : true,  
			'render' : function(my) { if (Number(my.ahr.pickup_lib())>=0) return data.hash.aou[ my.ahr.pickup_lib() ].name(); else return my.ahr.pickup_lib().name(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'pickup_lib_shortname', 'label' : getString('staff.ahr_pickup_lib_label'), 'flex' : 0,
			'primary' : false, 'hidden' : true,  
			'render' : function(my) { if (Number(my.ahr.pickup_lib())>=0) return data.hash.aou[ my.ahr.pickup_lib() ].shortname(); else return my.ahr.pickup_lib().shortname(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'current_copy', 'label' : getString('staff.ahr_current_copy_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.acp ? my.acp.barcode() : "No Copy"; },
		},
		{
			'id' : 'current_copy_location', 'label' : 'Current Copy Location', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { if (!my.acp) { return ""; } else { if (Number(my.acp.location())>=0) return data.lookup("acpl", my.acp.location() ).name(); else return my.acp.location().name(); } },
			'persist' : 'hidden width ordinal',
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'email_notify', 'label' : getString('staff.ahr_email_notify_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return get_bool(my.ahr.email_notify()) ? "Yes" : "No"; },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'expire_time', 'label' : getString('staff.ahr_expire_time_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.ahr.expire_time(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'fulfillment_time', 'label' : getString('staff.ahr_fulfillment_time_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.ahr.fulfillment_time(); },
		},
        {
            'persist' : 'hidden width ordinal',
            'id' : 'frozen',
            'label' : 'Active',
            'flex' : 0,
            'primary' : false,
            'hidden' : true,
            'render' : function(my) {
                if (!get_bool( my.ahr.frozen() )) {
                    return 'Yes';
                } else {
                    return 'No';
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'thaw_date',
            'label' : 'Activation Date',
            'flex' : 0,
            'primary' : false,
            'hidden' : true,
            'render' : function(my) {
                if (my.ahr.thaw_date() == null) {
                    return 'None';
                } else {
                    return my.ahr.thaw_date().substr(0,10);
                }
            }
        },
		{
			'persist' : 'hidden width ordinal', 'id' : 'holdable_formats', 'label' : getString('staff.ahr_holdable_formats_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.ahr.holdable_formats(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'id', 'label' : getString('staff.ahr_id_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.ahr.id(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'phone_notify', 'label' : getString('staff.ahr_phone_notify_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.ahr.phone_notify(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'prev_check_time', 'label' : getString('staff.ahr_prev_check_time_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.ahr.prev_check_time(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'requestor', 'label' : getString('staff.ahr_requestor_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.ahr.requestor(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'selection_depth', 'label' : getString('staff.ahr_selection_depth_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.ahr.selection_depth(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'target', 'label' : getString('staff.ahr_target_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.ahr.target(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'usr', 'label' : getString('staff.ahr_usr_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : function(my) { return my.ahr.usr(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'title', 'label' : getString('staff.mvr_label_title'), 'flex' : 1, 'sort_type' : 'title',
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.mvr ? my.mvr.title() : "No Title?"; },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'author', 'label' : getString('staff.mvr_label_author'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.mvr ? my.mvr.author() : "No Author?"; },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'edition', 'label' : 'Edition', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.mvr.edition(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'isbn', 'label' : 'ISBN', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.mvr.isbn(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'pubdate', 'label' : 'PubDate', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.mvr.pubdate(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'publisher', 'label' : 'Publisher', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.mvr.publisher(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'tcn', 'label' : 'TCN', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.mvr.tcn(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'notify_time', 'label' : 'Last Notify Time', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.ahr.notify_time(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'notify_count', 'label' : 'Notices', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.ahr.notify_count(); },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'transit_source', 'label' : 'Transit Source', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.ahr.transit() ?  data.hash.aou[ my.ahr.transit().source() ].shortname() : ""; },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'transit_source_send_time', 'label' : 'Transitted On', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.ahr.transit() ?  my.ahr.transit().source_send_time() : ""; },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'transit_dest_lib', 'label' : 'Transit Destination', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.ahr.transit() ?  data.hash.aou[ my.ahr.transit().dest() ].shortname() : ""; },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'transit_dest_recv_time', 'label' : 'Transit Completed On', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.ahr.transit() ?  my.ahr.transit().dest_recv_time() : ""; },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'patron_barcode', 'label' : 'Patron Barcode', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.patron_barcode ? my.patron_barcode : ""; },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'patron_family_name', 'label' : 'Patron Last Name', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.patron_family_name ? my.patron_family_name : ""; },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'patron_first_given_name', 'label' : 'Patron First Name', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.patron_first_given_name ? my.patron_first_given_name : ""; },
		},
		{
			'persist' : 'hidden width ordinal', 'id' : 'callnumber', 'label' : 'Call Number', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : function(my) { return my.acn.label(); },
		},
	];
	for (var i = 0; i < c.length; i++) {
		if (modify[ c[i].id ]) {
			for (var j in modify[ c[i].id ]) {
				c[i][j] = modify[ c[i].id ][j];
			}
		}
	}
	if (params) {
		if (params.just_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < params.just_these.length; i++) {
				var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
				new_c.push( function(y){ return y; }( x ) );
			}
			c = new_c;
		}
		if (params.except_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < c.length; i++) {
				var x = util.functional.find_list(params.except_these,function(d){return(d==c[i].id);});
				if (!x) new_c.push(c[i]);
			}
			c = new_c;
		}

	}
	return c.sort( function(a,b) { if (a.label < b.label) return -1; if (a.label > b.label) return 1; return 0; } );
}
/*
circ.util.std_map_row_to_column = function(error_value) {
	return function(row,col) {
		// row contains { 'my' : { 'acp' : {}, 'circ' : {}, 'mvr' : {} } }
		// col contains one of the objects listed above in columns
		
		// mimicking some of the obj in circ.checkin and circ.checkout where map_row_to_column is usually defined
		var obj = {}; 
		JSAN.use('util.error'); obj.error = new util.error();
		JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
		JSAN.use('util.network'); obj.network = new util.network();
		JSAN.use('util.money');

		var my = row.my;
		var value;
		try { 
			value = eval( col.render );
		} catch(E) {
			obj.error.sdump('D_WARN','map_row_to_column: ' + E);
			if (error_value) value = error_value; else value = '   ';
		}
		return value;
	}
}
*/
circ.util.std_map_row_to_columns = function(error_value) {
	return function(row,cols) {
		// row contains { 'my' : { 'acp' : {}, 'circ' : {}, 'mvr' : {} } }
		// cols contains all of the objects listed above in columns
		
		var obj = {}; 
		JSAN.use('util.error'); obj.error = new util.error();
		JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
		JSAN.use('util.network'); obj.network = new util.network();
		JSAN.use('util.money');

		var my = row.my;
		var values = [];
		var cmd = '';
		try { 
			for (var i = 0; i < cols.length; i++) {
				switch (typeof cols[i].render) {
					case 'function': try { values[i] = cols[i].render(my); } catch(E) { values[i] = error_value; dump(E+'\n'); } break;
					case 'string' : cmd += 'try { ' + cols[i].render + '; values['+i+'] = v; } catch(E) { values['+i+'] = error_value; }'; break;
					default: cmd += 'values['+i+'] = "??? '+(typeof cols[i].render)+'"; ';
				}
			}
			if (cmd) eval( cmd );
		} catch(E) {
			obj.error.sdump('D_WARN','map_row_to_column: ' + E);
			if (error_value) { value = error_value; } else { value = '   ' };
		}
		return values;
	}
}

circ.util.checkin_via_barcode = function(session,params,backdate,auto_print,async) {
	try {
		JSAN.use('util.error'); var error = new util.error();
		JSAN.use('util.network'); var network = new util.network();
		JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
		JSAN.use('util.date');

		if (backdate && (backdate == util.date.formatted_date(new Date(),'%Y-%m-%d')) ) backdate = null;

		//var params = { 'barcode' : barcode };
		if (backdate) params.backdate = util.date.formatted_date(backdate + ' 00:00:00','%{iso8601}');

		if (typeof async == 'object') {
			try { async.disable_textbox(); } catch(E) { error.sdump('D_ERROR','async.disable_textbox() = ' + E); };
		}
		var check = network.request(
			api.CHECKIN_VIA_BARCODE.app,
			api.CHECKIN_VIA_BARCODE.method,
			[ session, params ],
			async ? function(req) { 
				try {
					var check = req.getResultObject();
					var r = circ.util.checkin_via_barcode2(session,params,backdate,auto_print,check); 
					if (typeof async == 'object') {
						try { async.checkin_result(r); } catch(E) { error.sdump('D_ERROR','async.checkin_result() = ' + E); };
					}
				} catch(E) {
					JSAN.use('util.error'); var error = new util.error();
					error.standard_unexpected_error_alert('Check In Failed (in circ.util.checkin): ',E);
					if (typeof async == 'object') {
						try { async.enable_textbox(); } catch(E) { error.sdump('D_ERROR','async.disable_textbox() = ' + E); };
					}
					return null;
				}
			} : null,
			{
				'title' : 'Override Checkin Failure?',
				'overridable_events' : [ 
					1203 /* COPY_BAD_STATUS */, 
					1213 /* PATRON_BARRED */,
					1217 /* PATRON_INACTIVE */,
					1224 /* PATRON_ACCOUNT_EXPIRED */,
					1234 /* ITEM_DEPOSIT_PAID */,
					7009 /* CIRC_CLAIMS_RETURNED */,
					7010 /* COPY_ALERT_MESSAGE */, 
					7011 /* COPY_STATUS_LOST */, 
					7012 /* COPY_STATUS_MISSING */, 
					7013 /* PATRON_EXCEEDS_FINES */,
				],
				'text' : {
					'1203' : function(r) {
						//return data.hash.ccs[ r.payload.status() ].name();
						return r.payload.status().name();
					},
					'1234' : function(r) {
						return "A paid deposit will be owed to this patron if this action is overrided.";
					},
					'7010' : function(r) {
						return r.payload;
					},
				}
			}
		);
		if (!async) {
			return circ.util.checkin_via_barcode2(session,params,backdate,auto_print,check); 
		}


	} catch(E) {
		JSAN.use('util.error'); var error = new util.error();
		error.standard_unexpected_error_alert('Check In Failed (in circ.util.checkin): ',E);
		if (typeof async == 'object') {
			try { async.enable_textbox(); } catch(E) { error.sdump('D_ERROR','async.disable_textbox() = ' + E); };
		}
		return null;
	}
}

circ.util.checkin_via_barcode2 = function(session,params,backdate,auto_print,check) {
	try {
		JSAN.use('util.error'); var error = new util.error();
		JSAN.use('util.network'); var network = new util.network();
		JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
		JSAN.use('util.date');

		error.sdump('D_DEBUG','check = ' + error.pretty_print( js2JSON( check ) ) );

		check.message = check.textcode;

		if (check.payload && check.payload.copy) check.copy = check.payload.copy;
		if (check.payload && check.payload.record) check.record = check.payload.record;
		if (check.payload && check.payload.circ) check.circ = check.payload.circ;

		if (!check.route_to) check.route_to = '   ';

		if (document.getElementById('no_change_label')) {
			document.getElementById('no_change_label').setAttribute('value','');
			document.getElementById('no_change_label').setAttribute('hidden','true');
		}

		if (check.circ) {
			network.simple_request('FM_MBTS_RETRIEVE',[ses(),check.circ.id()], function(req) {
				JSAN.use('util.money');
				var bill = req.getResultObject();
				if (Number(bill.balance_owed()) == 0) return;
				if (document.getElementById('no_change_label')) {
					var m = document.getElementById('no_change_label').getAttribute('value');
					document.getElementById('no_change_label').setAttribute('value', m + 'Transaction for ' + params.barcode + ' billable $' + util.money.sanitize(bill.balance_owed()) + '  ');
					document.getElementById('no_change_label').setAttribute('hidden','false');
				}
			});
		}

		var msg = '';

		if (check.payload && check.payload.cancelled_hold_transit) {
			msg += 'Original hold for transit cancelled.\n\n';
		}

		/* SUCCESS  /  NO_CHANGE  /  ITEM_NOT_CATALOGED */
		if (check.ilsevent == 0 || check.ilsevent == 3 || check.ilsevent == 1202) {
			try { check.route_to = data.lookup('acpl', check.copy.location() ).name(); } catch(E) { msg += 'Please inform your helpdesk/developers of this error:\nFIXME: ' + E + '\n'; }
			if (check.ilsevent == 3 /* NO_CHANGE */) {
				//msg = 'This item is already checked in.\n';
				if (document.getElementById('no_change_label')) {
					var m = document.getElementById('no_change_label').getAttribute('value');
					document.getElementById('no_change_label').setAttribute('value',m + params.barcode + ' was already checked in.  ');
					document.getElementById('no_change_label').setAttribute('hidden','false');
				}
			}
			if (check.ilsevent == 1202 /* ITEM_NOT_CATALOGED */ && check.copy.status() != 11) {
				msg = 'Please inform your helpdesk/developers of this error:\nFIXME -- ITEM_NOT_CATALOGED event but copy status is '
					+ (data.hash.ccs[ check.copy.status() ] ? data.hash.ccs[ check.copy.status() ].name() : check.copy.status().name() ) + '\n';
			}
			switch(check.copy.status()) {
				case 0: /* AVAILABLE */
				case 7: /* RESHELVING */
					if (msg) msg += 'This item needs to be routed to ' + check.route_to + '.\n';
				break;
				case 8: /* ON HOLDS SHELF */
					check.route_to = 'HOLDS SHELF';
					if (check.payload.hold) {
						if (check.payload.hold.pickup_lib() != data.list.au[0].ws_ou()) {
							msg += 'Please inform your helpdesk/developers of this error:\nFIXME:  We should have received a ROUTE_ITEM\n';
						} else {
							msg += 'This item needs to be routed to ' + check.route_to + '.\n';
						}
					} else { 
						msg += 'Please inform your helpdesk/developers of this error:\nFIXME: status of Holds Shelf, but no actual hold found.\n';
					}
					JSAN.use('util.date'); 
					if (check.payload.hold) {
						JSAN.use('patron.util');
						msg += '\nBarcode: ' + check.payload.copy.barcode() + '\n';
						msg += 'Title: ' + (check.payload.record ? check.payload.record.title() : check.payload.copy.dummy_title() ) + '\n';
						var au_obj = patron.util.retrieve_fleshed_au_via_id( session, check.payload.hold.usr() );
						msg += '\nHold for patron ' + au_obj.family_name() + ', ' + au_obj.first_given_name() + ' ' + au_obj.second_given_name() + '\n';
						msg += 'Barcode: ' + au_obj.card().barcode() + '\n';
						if (check.payload.hold.phone_notify()) msg += 'Notify by phone: ' + check.payload.hold.phone_notify() + '\n';
						if (check.payload.hold.email_notify()) msg += 'Notify by email: ' + (au_obj.email() ? au_obj.email() : '') + '\n';
						msg += '\nRequest Date: ' + util.date.formatted_date(check.payload.hold.request_time(),'%F') + '\n';
					}
					var rv = 0;
					msg += 'Slip Date: ' + util.date.formatted_date(new Date(),'%F') + '\n';
					if (!auto_print) rv = error.yns_alert_formatted(
						msg,
						'Hold Slip',
						"Print",
						"Don't Print",
						null,
						"Check here to confirm this message",
						'/xul/server/skin/media/images/turtle.gif'
					);
					if (rv == 0) {
						try {
							JSAN.use('util.print'); var print = new util.print();
							msg = msg.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g,'<br/>');
							print.simple( msg , { 'no_prompt' : true, 'content_type' : 'text/html' } );
						} catch(E) {
							dump('Please inform your helpdesk/developers of this error:\nFIXME: ' + E + '\n');
							alert('Please inform your helpdesk/developers of this error:\nFIXME: ' + E + '\n');
						}
					}
					msg = '';
					if (document.getElementById('no_change_label')) {
						var m = document.getElementById('no_change_label').getAttribute('value');
						document.getElementById('no_change_label').setAttribute('value',m + params.barcode + ' has been captured for a hold.  ');
						document.getElementById('no_change_label').setAttribute('hidden','false');
					}
				break;
				case 6: /* IN TRANSIT */
					check.route_to = 'TRANSIT SHELF??';
					msg += ("Please inform your helpdesk/developers of this error:\nFIXME -- I didn't think we could get here.\n");
				break;
				case 11: /* CATALOGING */
					check.route_to = 'CATALOGING';
					if (document.getElementById('do_not_alert_on_precat')) {
						var x = document.getElementById('do_not_alert_on_precat');
						if (! x.checked) msg += 'This item needs to be routed to ' + check.route_to + '.';
					} else {
						msg += 'This item needs to be routed to ' + check.route_to + '.';
					}
					if (document.getElementById('no_change_label')) {
						var m = document.getElementById('no_change_label').getAttribute('value');
						document.getElementById('no_change_label').setAttribute('value',m + params.barcode + ' needs to be cataloged.  ');
						document.getElementById('no_change_label').setAttribute('hidden','false');
					}
				break;
				default:
					msg += ('Please inform your helpdesk/developers of this error:\nFIXME -- this case "' + (data.hash.ccs[check.copy.status()] ? data.hash.ccs[check.copy.status()].name() : check.copy.status().name()) + '" is unhandled.\n');
					msg += 'This item needs to be routed to ' + check.route_to + '.';
				break;
			}
			if (msg) error.yns_alert(msg,'Alert',null,'OK',null,"Check here to confirm this message");

		} else /* ROUTE_ITEM */ if (check.ilsevent == 7000) {

			var lib = data.hash.aou[ check.org ];
			check.route_to = lib.shortname();
			msg += 'Destination: ' + check.route_to + '.\n';
			msg += '\n' + lib.name() + '\n';
			try {
				if (lib.holds_address() ) {
					var a = network.simple_request('FM_AOA_RETRIEVE',[ lib.holds_address() ]);
					if (typeof a.ilsevent != 'undefined') throw(a);
					if (a.street1()) msg += a.street1() + '\n';
					if (a.street2()) msg += a.street2() + '\n';
					msg += (a.city() ? a.city() + ', ' : '') + (a.state() ? a.state() + ' ' : '') + (a.post_code() ? a.post_code() : '') + '\n';
				} else {
					msg += "We do not have a holds address for this library.\n";
				}
			} catch(E) {
				msg += 'Unable to retrieve mailing address.\n';
				error.standard_unexpected_error_alert('Unable to retrieve mailing address.',E);
			}
			msg += '\nBarcode: ' + check.payload.copy.barcode() + '\n';
			msg += 'Title: ' + (check.payload.record ? check.payload.record.title() : check.payload.copy.dummy_title() ) + '\n';
			msg += 'Author: ' + (check.payload.record ? check.payload.record.author() :check.payload.copy.dummy_author()  ) + '\n';
			JSAN.use('util.date');
			if (check.payload.hold) {
				JSAN.use('patron.util');
				var au_obj = patron.util.retrieve_fleshed_au_via_id( session, check.payload.hold.usr() );
				msg += '\nHold for patron ' + au_obj.family_name() + ', ' + au_obj.first_given_name() + ' ' + au_obj.second_given_name() + '\n';
				msg += 'Barcode: ' + au_obj.card().barcode() + '\n';
				if (check.payload.hold.phone_notify()) msg += 'Notify by phone: ' + check.payload.hold.phone_notify() + '\n';
				if (check.payload.hold.email_notify()) msg += 'Notify by email: ' + (au_obj.email() ? au_obj.email() : '') + '\n';
				msg += '\nRequest Date: ' + util.date.formatted_date(check.payload.hold.request_time(),'%F');
			}
			var rv = 0;
			msg += '\nSlip Date: ' + util.date.formatted_date(new Date(),'%F') + '\n';
			if (!auto_print) rv = error.yns_alert_formatted(
				msg,
				'Transit Slip',
				"Print",
				"Don't Print",
				null,
				"Check here to confirm this message",
				'/xul/server/skin/media/images/turtle.gif'
			);
			if (rv == 0) {
				try {
					JSAN.use('util.print'); var print = new util.print();
					//print.simple( msg, { 'no_prompt' : true, 'content_type' : 'text/plain' } );
					msg = msg.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g,'<br/>');
					print.simple( msg , { 'no_prompt' : true, 'content_type' : 'text/html' } );
				} catch(E) {
					dump('Please inform your helpdesk/developers of this error:\nFIXME: ' + E + '\n');
					alert('Please inform your helpdesk/developers of this error:\nFIXME: ' + E + '\n');
				}
			}
			if (document.getElementById('no_change_label')) {
				var m = document.getElementById('no_change_label').getAttribute('value');
				document.getElementById('no_change_label').setAttribute('value',m + params.barcode + ' is in transit.  ');
				document.getElementById('no_change_label').setAttribute('hidden','false');
			}

		} else /* ASSET_COPY_NOT_FOUND */ if (check.ilsevent == 1502) {

			check.route_to = 'CATALOGING';
			error.yns_alert(
				'The barcode was either mis-scanned or the item needs to be cataloged.',
				'Alert',
				null,
				'OK',
				null,
				"Check here to confirm this message"
			);
			if (document.getElementById('no_change_label')) {
				var m = document.getElementById('no_change_label').getAttribute('value');
				document.getElementById('no_change_label').setAttribute('value',m + params.barcode + ' is mis-scanned or not cataloged.  ');
				document.getElementById('no_change_label').setAttribute('hidden','false');
			}

		} else /* HOLD_CAPTURE_DELAYED */ if (check.ilsevent == 7019) {

			var rv = 0;
			msg += "\nThis item could fulfill a hold request but capture has been delayed by policy.\n";
			rv = error.yns_alert_formatted(
				msg,
                "Hold Capture Delayed",
				"Do Not Capture",
				"Capture",
				null,
				"Check here to confirm this message",
				'/xul/server/skin/media/images/stop_sign.png'
			);
			params.capture = rv == 0 ? 'nocapture' : 'capture';

			return circ.util.checkin_via_barcode(session,params,backdate,auto_print,false); 

		} else /* NETWORK TIMEOUT */ if (check.ilsevent == -1) {
			error.standard_network_error_alert('Check In Failed.  If you wish to use the offline interface, in the top menubar select Circulation -> Offline Interface');
		} else {

			switch (check.ilsevent) {
				case 1203 /* COPY_BAD_STATUS */ : 
				case 1213 /* PATRON_BARRED */ :
				case 1217 /* PATRON_INACTIVE */ :
				case 1224 /* PATRON_ACCOUNT_EXPIRED */ :
				case 1234 /* ITEM_DEPOSIT_PAID */ :
				case 7009 /* CIRC_CLAIMS_RETURNED */ :
				case 7010 /* COPY_ALERT_MESSAGE */ : 
				case 7011 /* COPY_STATUS_LOST */ : 
				case 7012 /* COPY_STATUS_MISSING */ : 
				case 7013 /* PATRON_EXCEEDS_FINES */ :
					return null; /* handled */
				break;
			}

			throw(check);

		}

		return check;
	} catch(E) {
		JSAN.use('util.error'); var error = new util.error();
		error.standard_unexpected_error_alert('Check In Failed (in circ.util.checkin): ',E);
		return null;
	}
}

circ.util.renew_via_barcode = function ( barcode, patron_id, async ) {
	try {
		var obj = {};
		JSAN.use('util.network'); obj.network = new util.network();
		JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.stash_retrieve();

		var params = { barcode: barcode };
		if (patron_id) params.patron = patron_id;

		function renew_callback(req) {
			try {
				var renew = req.getResultObject();
				if (typeof renew.ilsevent != 'undefined') renew = [ renew ];
				for (var j = 0; j < renew.length; j++) { 
					switch(renew[j].ilsevent) {
						case 0 /* SUCCESS */ : break;
						case 5000 /* PERM_FAILURE */: break;
						case 1212 /* PATRON_EXCEEDS_OVERDUE_COUNT */ : break;
						case 1213 /* PATRON_BARRED */ : break;
						case 1215 /* CIRC_EXCEEDS_COPY_RANGE */ : break;
						case 1224 /* PATRON_ACCOUNT_EXPIRED */ : break;
                        case 1233 /* ITEM_RENTAL_FEE_REQUIRED */ : break;
						case 1500 /* ACTION_CIRCULATION_NOT_FOUND */ : break;
						case 7002 /* PATRON_EXCEEDS_CHECKOUT_COUNT */ : break;
						case 7003 /* COPY_CIRC_NOT_ALLOWED */ : break;
						case 7004 /* COPY_NOT_AVAILABLE */ : break;
						case 7006 /* COPY_IS_REFERENCE */ : break;
						case 7007 /* COPY_NEEDED_FOR_HOLD */ : break;
						case 7008 /* MAX_RENEWALS_REACHED */ : break; 
						case 7009 /* CIRC_CLAIMS_RETURNED */ : break; 
						case 7010 /* COPY_ALERT_MESSAGE */ : break;
						case 7013 /* PATRON_EXCEEDS_FINES */ : break;
						default:
							throw(renew);
						break;
					}
				}
				if (typeof async == 'function') async(renew);
				return renew;
			} catch(E) {
				JSAN.use('util.error'); var error = new util.error();
				error.standard_unexpected_error_alert('Renew Failed for ' + barcode,E);
				return null;
			}
		}

		var renew = obj.network.simple_request(
			'CHECKOUT_RENEW', 
			[ ses(), params ],
			async ? renew_callback : null,
			{
				'title' : 'Override Renew Failure?',
				'overridable_events' : [ 
					1212 /* PATRON_EXCEEDS_OVERDUE_COUNT */,
					1213 /* PATRON_BARRED */,
					1215 /* CIRC_EXCEEDS_COPY_RANGE */,
                    1233 /* ITEM_RENTAL_FEE_REQUIRED */,
					7002 /* PATRON_EXCEEDS_CHECKOUT_COUNT */,
					7003 /* COPY_CIRC_NOT_ALLOWED */,
					7004 /* COPY_NOT_AVAILABLE */,
					7006 /* COPY_IS_REFERENCE */,
					7007 /* COPY_NEEDED_FOR_HOLD */,
					7008 /* MAX_RENEWALS_REACHED */, 
					7009 /* CIRC_CLAIMS_RETURNED */, 
					7010 /* COPY_ALERT_MESSAGE */,
					7013 /* PATRON_EXCEEDS_FINES */,
				],
				'text' : {
					'1212' : function(r) { return 'Barcode: ' + barcode; },
					'1213' : function(r) { return 'Barcode: ' + barcode; },
					'1215' : function(r) { return 'Barcode: ' + barcode; },
                    '1233' : function(r) {
                        return "For item with barcode " + barcode + ", a billing for an Item Rental Fee will be added to the patron's account if this action is overrided.";
                    },
					'7002' : function(r) { return 'Barcode: ' + barcode; },
					'7003' : function(r) { return 'Barcode: ' + barcode; },
					'7004' : function(r) {
						return 'Barcode: ' + barcode + ' Status: ' + r.payload.status().name();
					},
					'7006' : function(r) { return 'Barcode: ' + barcode; },
					'7007' : function(r) { return 'Barcode: ' + barcode; },
					'7008' : function(r) { return 'Barcode: ' + barcode; },
					'7009' : function(r) { return 'Barcode: ' + barcode; },
					'7010' : function(r) {
						return 'Barcode: ' + barcode + ' Message: ' + r.payload;
					},
					'7013' : function(r) { return 'Barcode: ' + barcode; },
				}
			}
		);
		if (! async ) return renew_callback( { 'getResultObject' : function() { return renew; } } );

	} catch(E) {
		JSAN.use('util.error'); var error = new util.error();
		error.standard_unexpected_error_alert('Renew Failed for ' + barcode,E);
		return null;
	}
}



dump('exiting circ/util.js\n');
