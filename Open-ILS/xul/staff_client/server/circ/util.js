dump('entering circ/util.js\n');

if (typeof circ == 'undefined') var circ = {};
circ.util = {};

circ.util.EXPORT_OK	= [ 
	'columns', 'hold_columns', 'CHECKIN_VIA_BARCODE', 'std_map_row_to_column', 'hold_capture_via_copy_barcode'
];
circ.util.EXPORT_TAGS	= { ':all' : circ.util.EXPORT_OK };

circ.util.columns = function(modify) {
	
	JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});

	function getString(s) { return data.entities[s]; }

	var c = [
		{
			'id' : 'acp_id', 'label' : getString('staff.acp_label_id'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.id()'
		},
		{
			'id' : 'circ_id', 'label' : getString('staff.circ_label_id'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.circ.id()'
		},
		{
			'id' : 'mvr_doc_id', 'label' : getString('staff.mvr_label_doc_id'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.mvr.doc_id()'
		},
		{
			'id' : 'barcode', 'label' : getString('staff.acp_label_barcode'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.barcode()'
		},
		{
			'id' : 'call_number', 'label' : getString('staff.acp_label_call_number'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'if (my.acp.call_number() == -1) { "Not Cataloged"; } else { var x = obj.network.simple_request("FM_ACN_RETRIEVE",[ my.acp.call_number() ]); if (x.ilsevent) { "Not Cataloged"; } else { x.label(); } }'
		},
		{
			'id' : 'copy_number', 'label' : getString('staff.acp_label_copy_number'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.copy_number()'
		},
		{
			'id' : 'location', 'label' : getString('staff.acp_label_location'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'if (Number(my.acp.location())) obj.data.hash.acpl[ my.acp.location() ].name(); else my.acp.location().name();'
		},
		{
			'id' : 'loan_duration', 'label' : getString('staff.acp_label_loan_duration'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 
			'render' : 'switch(my.acp.loan_duration()){ case 1: "Short"; break; case 2: "Normal"; break; case 3: "Long"; break; }'
		},
		{
			'id' : 'circ_lib', 'label' : getString('staff.acp_label_circ_lib'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'if (Number(my.acp.circ_lib())) obj.data.hash.aou[ my.acp.circ_lib() ].shortname(); else my.acp.circ_lib().shortname();'
		},
		{
			'id' : 'fine_level', 'label' : getString('staff.acp_label_fine_level'), 'flex' : 1,
			'primary' : false, 'hidden' : true,
			'render' : 'switch(my.acp.fine_level()){ case 1: "Low"; break; case 2: "Normal"; break; case 3: "High"; break; }'
		},
		{
			'id' : 'circulate', 'label' : 'Circulate?', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.circulate() == 1 ? "Yes" : "No"'
		},
		{
			'id' : 'holdable', 'label' : 'Holdable?', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.holdable() == 1 ? "Yes" : "No"'
		},
		{
			'id' : 'opac_visible', 'label' : 'OPAC Visible?', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.opac_visible() == 1 ? "Yes" : "No"'
		},
		{
			'id' : 'ref', 'label' : 'Reference?', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.ref() == 1 ? "Yes" : "No"'
		},
		{
			'id' : 'deposit', 'label' : 'Deposit?', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.deposit() == 1 ? "Yes" : "No"'
		},
		{
			'id' : 'deposit_amount', 'label' : getString('staff.acp_label_deposit_amount'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.deposit_amount()'
		},
		{
			'id' : 'price', 'label' : getString('staff.acp_label_price'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.price()'
		},
		{
			'id' : 'circ_as_type', 'label' : getString('staff.acp_label_circ_as_type'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.circ_as_type()'
		},
		{
			'id' : 'circ_modifier', 'label' : getString('staff.acp_label_circ_modifier'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.circ_modifier()'
		},
		{
			'id' : 'xact_start', 'label' : getString('staff.circ_label_xact_start'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.circ.xact_start()'
		},
		{
			'id' : 'xact_finish', 'label' : getString('staff.circ_label_xact_finish'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.circ.xact_finish()'
		},
		{
			'id' : 'due_date', 'label' : getString('staff.circ_label_due_date'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.circ.due_date().substr(0,10)'
		},
		{
			'id' : 'title', 'label' : getString('staff.mvr_label_title'), 'flex' : 2,
			'primary' : false, 'hidden' : true, 'render' : 'try { my.mvr.title(); } catch(E) { my.acp.dummy_title(); }'
		},
		{
			'id' : 'author', 'label' : getString('staff.mvr_label_author'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'try { my.mvr.author(); } catch(E) { my.acp.dummy_author(); }'
		},
		{
			'id' : 'edition', 'label' : 'Edition', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.mvr.edition();'
		},
		{
			'id' : 'isbn', 'label' : 'ISBN', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.mvr.isbn();'
		},
		{
			'id' : 'pubdate', 'label' : 'PubDate', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.mvr.pubdate();'
		},
		{
			'id' : 'publisher', 'label' : 'Publisher', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.mvr.publisher();'
		},
		{
			'id' : 'tcn', 'label' : 'TCN', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.mvr.tcn();'
		},
		{
			'id' : 'renewal_remaining', 'label' : getString('staff.circ_label_renewal_remaining'), 'flex' : 0,
			'primary' : false, 'hidden' : true, 'render' : 'my.circ.renewal_remaining()'
		},
		{
			'id' : 'status', 'label' : getString('staff.acp_label_status'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'if (Number(my.acp.status())) obj.data.hash.ccs[ my.acp.status() ].name(); else my.acp.status().name();'
		},
		{
			'id' : 'route_to', 'label' : 'Route To', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.route_to.toString()'
		},
		{
			'id' : 'message', 'label' : 'Message', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.message.toString()'
		},
		{
			'id' : 'uses', 'label' : '# of Uses', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.uses'
		}
	];
	for (var i = 0; i < c.length; i++) {
		if (modify[ c[i].id ]) {
			for (var j in modify[ c[i].id ]) {
				c[i][j] = modify[ c[i].id ][j];
			}
		}
	}
	return c;
}

circ.util.hold_columns = function(modify) {
	
	JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});

	function getString(s) { return data.entities[s]; }

	var c = [
		{
			'id' : 'request_time', 'label' : getString('staff.ahr_request_time_label'), 'flex' : 0,
			'primary' : false, 'hidden' : true,  
			'render' : 'my.ahr.request_time().toString().substr(0,10)'
		},
		{
			'id' : 'capture_time', 'label' : getString('staff.ahr_capture_time_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : 'my.ahr.capture_time()'
		},
		{
			'id' : 'status', 'label' : getString('staff.ahr_status_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : 'my.ahr.status()'
		},
		{
			'id' : 'hold_type', 'label' : getString('staff.ahr_hold_type_label'), 'flex' : 0,
			'primary' : false, 'hidden' : true,  'render' : 'my.ahr.hold_type()'
		},
		{
			'id' : 'pickup_lib', 'label' : getString('staff.ahr_pickup_lib_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  
			'render' : 'if (Number(my.ahr.pickup_lib())) obj.data.hash.aou[ my.ahr.pickup_lib() ].name(); else my.ahr.pickup_lib().name();'
		},
		{
			'id' : 'pickup_lib_shortname', 'label' : getString('staff.ahr_pickup_lib_label'), 'flex' : 0,
			'primary' : false, 'hidden' : true,  
			'render' : 'if (Number(my.ahr.pickup_lib())) obj.data.hash.aou[ my.ahr.pickup_lib() ].shortname(); else my.ahr.pickup_lib().shortname();'
		},
		{
			'id' : 'current_copy', 'label' : getString('staff.ahr_current_copy_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : 'my.acp.barcode()'
		},
		{
			'id' : 'email_notify', 'label' : getString('staff.ahr_email_notify_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : 'my.ahr.email_notify()'
		},
		{
			'id' : 'expire_time', 'label' : getString('staff.ahr_expire_time_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : 'my.ahr.expire_time()'
		},
		{
			'id' : 'fulfillment_time', 'label' : getString('staff.ahr_fulfillment_time_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : 'my.ahr.fulfillment_time()'
		},
		{
			'id' : 'holdable_formats', 'label' : getString('staff.ahr_holdable_formats_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : 'my.ahr.holdable_formats()'
		},
		{
			'id' : 'id', 'label' : getString('staff.ahr_id_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : 'my.ahr.id()'
		},
		{
			'id' : 'phone_notify', 'label' : getString('staff.ahr_phone_notify_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : 'my.ahr.phone_notify()'
		},
		{
			'id' : 'prev_check_time', 'label' : getString('staff.ahr_prev_check_time_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : 'my.ahr.prev_check_time()'
		},
		{
			'id' : 'requestor', 'label' : getString('staff.ahr_requestor_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : 'my.ahr.requestor()'
		},
		{
			'id' : 'selection_depth', 'label' : getString('staff.ahr_selection_depth_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : 'my.ahr.selection_depth()'
		},
		{
			'id' : 'target', 'label' : getString('staff.ahr_target_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : 'my.ahr.target()'
		},
		{
			'id' : 'usr', 'label' : getString('staff.ahr_usr_label'), 'flex' : 1,
			'primary' : false, 'hidden' : true,  'render' : 'my.ahr.usr()'
		},
		{
			'id' : 'title', 'label' : getString('staff.mvr_label_title'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.mvr.title()'
		},
		{
			'id' : 'author', 'label' : getString('staff.mvr_label_author'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.mvr.author()'
		},
		{
			'id' : 'edition', 'label' : 'Edition', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.mvr.edition();'
		},
		{
			'id' : 'isbn', 'label' : 'ISBN', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.mvr.isbn();'
		},
		{
			'id' : 'pubdate', 'label' : 'PubDate', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.mvr.pubdate();'
		},
		{
			'id' : 'publisher', 'label' : 'Publisher', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.mvr.publisher();'
		},
		{
			'id' : 'tcn', 'label' : 'TCN', 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.mvr.tcn();'
		},


	];
	for (var i = 0; i < c.length; i++) {
		if (modify[ c[i].id ]) {
			for (var j in modify[ c[i].id ]) {
				c[i][j] = modify[ c[i].id ][j];
			}
		}
	}
	return c;
}

circ.util.std_map_row_to_column = function() {
	return function(row,col) {
		// row contains { 'my' : { 'acp' : {}, 'circ' : {}, 'mvr' : {} } }
		// col contains one of the objects listed above in columns
		
		// mimicking some of the obj in circ.checkin and circ.checkout where map_row_to_column is usually defined
		var obj = {}; 
		JSAN.use('util.error'); obj.error = new util.error();
		JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
		JSAN.use('util.network'); obj.network = new util.network();

		var my = row.my;
		var value;
		try { 
			value = eval( col.render );
		} catch(E) {
			obj.error.sdump('D_WARN','map_row_to_column: ' + E);
			value = '???';
		}
		return value;
	}
}

circ.util.checkin_via_barcode = function(session,barcode,backdate) {
	try {
		JSAN.use('util.error'); var error = new util.error();
		JSAN.use('util.network'); var network = new util.network();
		JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
		JSAN.use('util.date');
		if (backdate && (backdate == util.date.formatted_date(new Date(),'%Y-%m-%d')) ) backdate = null;

		var params = { 'barcode' : barcode };
		if (backdate) params.backdate = backdate;

		var check = network.request(
			api.CHECKIN_VIA_BARCODE.app,
			api.CHECKIN_VIA_BARCODE.method,
			[ session, params ]
		);

		check.message = check.textcode;

		if (check.payload && check.payload.copy) check.copy = check.payload.copy;
		if (check.payload && check.payload.record) check.record = check.payload.record;
		if (check.payload && check.payload.circ) check.circ = check.payload.circ;

		if (!check.route_to) check.route_to = '???';

		/* SUCCESS  /  NO_CHANGE  /  ITEM_NOT_CATALOGED */
		if (check.ilsevent == 0 || check.ilsevent == 3 || check.ilsevent == 1202) {
			check.route_to = data.hash.acpl[ check.copy.location() ].name();
			var msg = '';
			if (check.ilsevent == 3) msg = 'This item is already checked in.\n';
			if (check.ilsevent == 1202 && check.copy.status() != 11) {
				msg = 'FIXME -- ITEM_NOT_CATALOGED event but copy status is '
					+ data.hash.ccs[ check.copy.status() ].name() + '\n';
			}
			switch(check.copy.status()) {
				case 0: /* AVAILABLE */
				case 7: /* RESHELVING */
					if (msg) msg += 'This item needs to be routed to ' + check.route_to + '.';
				break;
				case 8: /* ON HOLDS SHELF */
					check.route_to = 'HOLDS SHELF';
					if (check.payload.hold) {
						if (check.payload.hold.pickup_lib() != data.list.au[0].ws_ou()) {
							msg += 'FIXME:  We should have received a ROUTE_ITEM\n';
						} else {
							msg += 'This item needs to be routed to ' + check.route_to + '.\n';
						}
					} else { 
						msg += 'FIXME: status of Holds Shelf, but no hold in payload';
					}
					if (check.payload.hold) {
						JSAN.use('patron.util');
						var au_obj = patron.util.retrieve_au_via_id( session, check.payload.hold.usr() );
						msg += '\nHold for patron ' + au_obj.family_name() + ', ' + au_obj.first_given_name() + '\n';
						msg += 'Barcode: ' + au_obj.card().barcode() + '\n';
						if (check.payload.hold.phone_notify()) msg += 'Notify by phone: ' + check.payload.hold.phone_notify() + '\n';
						if (check.payload.hold.email_notify()) msg += 'Notify by email: ' + check.payload.hold.email_notify() + '\n';
					}
					var rv = error.yns_alert(
						msg,
						'Hold Slip',
						"Print",
						"Don't Print",
						null,
						"Check here to confirm this message"
					);
					if (rv == 0) {
						try {
							JSAN.use('util.print'); var print = new util.print();
							print.simple( msg, { 'no_prompt' : true } );
						} catch(E) {
							dump('FIXME: ' + E + '\n');
							alert('FIXME: ' + E + '\n');
						}
					}
					msg = '';
				break;
				case 6: /* IN TRANSIT */
					check.route_to = 'TRANSIT SHELF??';
					msg += ("FIXME -- I didn't think we could get here.\n");
				break;
				case 11: /* CATALOGING */
					check.route_to = 'CATALOGING';
					msg += 'This item needs to be routed to ' + check.route_to + '.';
				break;
				default:
					msg += ("FIXME -- this case is unhandled\n");
					msg += 'This item needs to be routed to ' + check.route_to + '.';
				break;
			}
			if (msg) error.yns_alert(msg,'Alert',null,'OK',null,"Check here to confirm this message");
		}

		/* ROUTE_ITEM */
		if (check.ilsevent == 7000) {
			var lib = data.hash.aou[ check.org ];
			check.route_to = lib.shortname();
			var msg = 'This item is in transit to ' + check.route_to + '.\n';
			msg += '\n' + lib.name() + '\n';
			msg += 'HOLD ADDRESSS STREET 1\n';
			msg += 'HOLD ADDRESSS STREET 2\n';
			msg += 'HOLD ADDRESSS CITY, STATE, ZIP\n';
			msg += '\nBarcode: ' + check.payload.copy.barcode() + '\n';
			msg += 'Title: ' + check.payload.record.title() + '\n';
			msg += 'Author: ' + check.payload.record.author() + '\n';
			if (check.payload.hold) {
				JSAN.use('patron.util');
				var au_obj = patron.util.retrieve_au_via_id( session, check.payload.hold.usr() );
				msg += '\nHold for patron ' + au_obj.family_name() + ', ' + au_obj.first_given_name() + '\n';
				msg += 'Barcode: ' + au_obj.card().barcode() + '\n';
				if (check.payload.hold.phone_notify()) msg += 'Notify by phone: ' + check.payload.hold.phone_notify() + '\n';
				if (check.payload.hold.email_notify()) msg += 'Notify by email: ' + check.payload.hold.email_notify() + '\n';
			}
			var rv = error.yns_alert(
				msg,
				'Transit Slip',
				"Print",
				"Don't Print",
				null,
				"Check here to confirm this message"
			);
			if (rv == 0) {
				try {
					JSAN.use('util.print'); var print = new util.print();
					print.simple( msg, { 'no_prompt' : true } );
				} catch(E) {
					dump('FIXME: ' + E + '\n');
					alert('FIXME: ' + E + '\n');
				}
			}
		}

		/* COPY_NOT_FOUND */
		if (check.ilsevent == 1502) {
			check.copy = new acp();
			check.copy.barcode( barcode );
			check.copy.status( 11 );
			check.route_to = 'CATALOGING';
			error.yns_alert(
				'The barcode was either mis-scanned or this item needs to be routed to CATALOGING.',
				'Alert',
				null,
				'OK',
				null,
				"Check here to confirm this message"
			);
		}

//				case '2': case 2: /* LOST??? */
//					JSAN.use('patron.util');
//					var au_obj = patron.util.retrieve_au_via_id( session, check.circ.usr() );
//					var msg = check.text + '\r\n' + 'Barcode: ' + barcode + '  Title: ' + 
//							check.record.title() + '  Author: ' + check.record.author() + '\r\n' +
//							'Patron: ' + au_obj.card().barcode() + ' ' + au_obj.family_name() + ', ' +
//							au_obj.first_given_name();
//					var pcheck = error.yns_alert(
//						msg,
//						'Lost Item',
//						'Edit Copy & Patron',
//						"Just Continue",
//						null,
//						"Check here to confirm this message"
//					); 
//					if (pcheck == 0) {
//						//FIXME//Re-implement
//						/*
//						var w = mw.spawn_main();
//						setTimeout(
//							function() {
//								mw.spawn_patron_display(w.document,'new_tab','main_tabbox',{'patron':au_obj});
//								mw.spawn_batch_copy_editor(w.document,'new_tab','main_tabbox',
//									{'copy_ids':[ check.copy.id() ]});
//							}, 0
//						);
//						*/
//					}
//				break;
		return check;
	} catch(E) {
		JSAN.use('util.error'); var error = new util.error();
		var msg = E + '\n---\n' + js2JSON(E);
		error.sdump('D_ERROR',msg);
		alert(msg);
		return null;
	}
}

circ.util.hold_capture_via_copy_barcode = function ( session, barcode, retrieve_flag ) {
	try {
		JSAN.use('util.network'); var network = new util.network();
		JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
		var params = { barcode: barcode }
		if (retrieve_flag) { params.flesh_record = retrieve_flag; params.flesh_copy = retrieve_flag; }
		var robj = network.request(
			api.CAPTURE_COPY_FOR_HOLD_VIA_BARCODE.app,
			api.CAPTURE_COPY_FOR_HOLD_VIA_BARCODE.method,
			[ session, params ]
		);
		var check = robj.payload;
		if (!check) {
			check = {};
			check.status = robj.ilsevent;
			check.copy = new acp(); check.copy.barcode( barcode );
		}
		check.text = robj.textcode;
		check.route_to = robj.route_to;
		//check.text = 'Captured for Hold';
		if (parseInt(check.route_to)) check.route_to = data.hash.aou[ check.route_to ].shortname();
		return check;
	} catch(E) {
		JSAN.use('util.error'); var error = new util.error();
		var msg = E + '\n---\n' + js2JSON(E);
		error.sdump('D_ERROR',msg);
		alert(msg);
		return null;
	}
}


dump('exiting circ/util.js\n');
