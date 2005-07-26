sdump('D_TRACE','Loading circ_tree.js\n');

function is_barcode_valid( barcode ) {

	// consider checkdigit, length, etc.

	return check_checkdigit( barcode );
}

function cancel_hold( hold ) {
	sdump('D_CIRC_UTILS',arg_dump(arguments,{0:true}));
	try {
		var result = user_request(
			'open-ils.circ',
			'open-ils.circ.hold.cancel',
			[ mw.G.auth_ses[0], hold.id() ]
		)[0];
		sdump('D_CIRC_UTILS','result = ' + result + '\n');
		return result;
	} catch(E) {
		handle_error(E);
		return null;
	}
}

function mark_circ_as_lost(circ) {
	sdump('D_CIRC_UTILS',arg_dump(arguments,{0:true}));
	try {
		var result = user_request(
			'open-ils.circ',
			'open-ils.circ.circulation.set_lost',
			[ mw.G.auth_ses[0], circ.id() ]
		)[0];
		sdump('D_CIRC_UTILS','result = ' + result + '\n');
		return result;
	} catch(E) {
		handle_error(E);
		return null;
	}
}

function mark_circ_as_missing(circ) {
	sdump('D_CIRC_UTILS',arg_dump(arguments,{0:true}));
	try {
		var result = user_request(
			'open-ils.circ',
			'open-ils.circ.circulation.set_missing',
			[ mw.G.auth_ses[0], circ.id() ]
		)[0];
		sdump('D_CIRC_UTILS','result = ' + result + '\n');
		return result;
	} catch(E) {
		handle_error(E);
		return null;
	}
}

function checkout_permit(barcode, patron_id, num_of_open_async_checkout_requests, f) {
	sdump('D_CIRC_UTILS',arg_dump(arguments,{0:true,1:true,2:true}));
	try {
		var check = user_request(
			'open-ils.circ',
			'open-ils.circ.permit_checkout',
			[ mw.G.auth_ses[0], barcode, patron_id, num_of_open_async_checkout_requests ],
			f
		)[0];
		if (!f) sdump('D_CIRC_UTILS','check = ' + js2JSON(check) + '\n');
		return check;	
	} catch(E) {
		handle_error(E);
		return null;
	}	
}

function checkout_by_copy_barcode(barcode, patron_id, f) {
	sdump('D_CIRC_UTILS',arg_dump(arguments,{0:true,1:true}));
	try {
		var check = user_request(
			'open-ils.circ',
			'open-ils.circ.checkout.barcode',
			[ mw.G.auth_ses[0], barcode, patron_id ],
			f
		)[0];
		if (!f) sdump('D_CIRC_UTILS','check = ' + js2JSON(check) + '\n');
		return check;
	} catch(E) {
		sdump('D_ERROR',E);
		return null;
	}
}

function hold_capture_by_copy_barcode( barcode, retrieve_flag ) {
	try {
		var check = user_request(
			'open-ils.circ',
			'open-ils.circ.hold.capture_copy.barcode',
			[ mw.G.auth_ses[0], barcode, retrieve_flag ]
		)[0];
		check.text = 'Captured for Hold';
		if (parseInt(check.route_to)) check.route_to = mw.G.org_tree_hash[ check.route_to ].shortname();
		return check;
	} catch(E) {
		handle_error(E, true);
		return null;
	}
}

function checkin_by_copy_barcode(barcode, backdate, f) {
	sdump('D_CIRC_UTILS',arg_dump(arguments,{0:true}));
	try {
		if (backdate && (backdate == formatted_date(new Date(),'%Y-%m-%d')) ) backdate = null;

		var check = user_request(
			'open-ils.circ',
			'open-ils.circ.checkin.barcode',
			[ mw.G.auth_ses[0], barcode, null, backdate ],
			f
		)[0];

		/*
		{ // REMOVE_ME, forcing a condition for testing
			check.status = 1;
			check.text = 'This copy is the first that could fulfill a hold.  Do it?';
		}
		*/

		if (!f) {
			sdump('D_CIRC_UTILS','check = ' + js2JSON(check) + '\n');
			if (check.status != 0) {
				switch(check.status) {
					case '1': case 1: /* possible hold capture */
						var rv = yns_alert(
							check.text,
							'Alert',
							"Capture",
							"Don't Capture",
							null,
							"Check here to confirm this message"
						);
						switch(rv) {
							case 0: /* capture */
							try {
								var check2 = hold_capture_by_copy_barcode( barcode );
								if (check2) {
									sdump('D_CIRC_UTILS','check2 = ' + js2JSON(check2) + '\n');
									check.copy = check2.copy;
									check.text = check2.text;
									check.route_to = check2.route_to;
									sPrint(check.record.title() + '<br />\r\n' + check.text + '\r\n<br />Barcode: ' + barcode + '  Route to: ' + check.route_to + '\r\n' );
								}

							} catch(E) { 
								sdump('D_ERROR',E + '\n'); 
								/* 
								// demo testing 
								check.text = 'Captured for Hold';
								check.route_to = 'ARL-ATH';
								*/
							}
							break;
							case 1: /* don't capture */

								check.text = 'Not Captured for Hold';
							break;
						}
					break;

					default: 
						if (parseInt(check.route_to)) check.route_to = mw.G.org_tree_hash[ check.route_to ].shortname();
						var msg = check.text + '\r\nBarcode: ' + barcode + '  Route To: ' + check.route_to;
						var pcheck = yns_alert(
							msg,
							'Alert',
							'Print Receipt',
							"Don't Print",
							null,
							"Check here to confirm this message"
						); 
						if (pcheck == 0) {
							sPrint( msg.match( /\n/g, '<br />\r\n'), true );
						}
					break;
				}
			}
		}
		if (parseInt(check.route_to)) check.route_to = mw.G.org_tree_hash[ check.route_to ].shortname();
		return check;
	} catch(E) {
		handle_error(E, true);
		return null;
	}
}

function renew_by_circ_id(id, f) {
	sdump('D_CIRC_UTILS',arg_dump(arguments,{0:true}));
	try {
		var check = user_request(
			'open-ils.circ',
			'open-ils.circ.renew',
			[ mw.G.auth_ses[0], id ],
			f
		)[0];
		if (!f) sdump('D_CIRC_UTILS','check = ' + js2JSON(check) + '\n');
		return check;
	} catch(E) {
		sdump('D_ERROR',E);
		return null;
	}
}

function hold_cols() {
	var cols = [
{
	'id' : 'request_time', 'label' : getString('ahr_request_time_label'), 'flex' : 0,
	'primary' : false, 'hidden' : false, 'fm_class' : 'ahr', 
	'fm_field_render' : '.request_time().toString().substr(0,10)'
},
{
	'id' : 'status', 'label' : getString('ahr_status_label'), 'flex' : 1,
	'primary' : false, 'hidden' : false, 'fm_class' : 'ahr', 'fm_field_render' : '.status()'
},
{
	'id' : 'hold_type', 'label' : getString('ahr_hold_type_label'), 'flex' : 0,
	'primary' : false, 'hidden' : false, 'fm_class' : 'ahr', 'fm_field_render' : '.hold_type()'
},
{
	'id' : 'pickup_lib', 'label' : getString('ahr_pickup_lib_label'), 'flex' : 1,
	'primary' : false, 'hidden' : true, 'fm_class' : 'ahr', 
	'fm_field_render' : 'mw.G.org_tree_hash[ $$.pickup_lib() ].name()'
},
{
	'id' : 'pickup_lib_shortname', 'label' : getString('ahr_pickup_lib_label'), 'flex' : 0,
	'primary' : false, 'hidden' : false, 'fm_class' : 'ahr', 
	'fm_field_render' : 'mw.G.org_tree_hash[ $$.pickup_lib() ].shortname()'
},
		{
			'id' : 'title', 'label' : getString('mvr_label_title'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mvr', 'fm_field_render' : '.title()'
		},
		{
			'id' : 'author', 'label' : getString('mvr_label_author'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mvr', 'fm_field_render' : '.author()'
		},
{
	'id' : 'capture_time', 'label' : getString('ahr_capture_time_label'), 'flex' : 1,
	'primary' : false, 'hidden' : true, 'fm_class' : 'ahr', 'fm_field_render' : '.capture_time()'
},
{
	'id' : 'current_copy', 'label' : getString('ahr_current_copy_label'), 'flex' : 1,
	'primary' : false, 'hidden' : true, 'fm_class' : 'ahr', 'fm_field_render' : '.current_copy()'
},
{
	'id' : 'email_notify', 'label' : getString('ahr_email_notify_label'), 'flex' : 1,
	'primary' : false, 'hidden' : true, 'fm_class' : 'ahr', 'fm_field_render' : '.email_notify()'
},
{
	'id' : 'expire_time', 'label' : getString('ahr_expire_time_label'), 'flex' : 1,
	'primary' : false, 'hidden' : true, 'fm_class' : 'ahr', 'fm_field_render' : '.expire_time()'
},
{
	'id' : 'fulfillment_time', 'label' : getString('ahr_fulfillment_time_label'), 'flex' : 1,
	'primary' : false, 'hidden' : true, 'fm_class' : 'ahr', 'fm_field_render' : '.fulfillment_time()'
},
{
	'id' : 'holdable_formats', 'label' : getString('ahr_holdable_formats_label'), 'flex' : 1,
	'primary' : false, 'hidden' : true, 'fm_class' : 'ahr', 'fm_field_render' : '.holdable_formats()'
},
{
	'id' : 'id', 'label' : getString('ahr_id_label'), 'flex' : 1,
	'primary' : false, 'hidden' : true, 'fm_class' : 'ahr', 'fm_field_render' : '.id()'
},
{
	'id' : 'phone_notify', 'label' : getString('ahr_phone_notify_label'), 'flex' : 1,
	'primary' : false, 'hidden' : true, 'fm_class' : 'ahr', 'fm_field_render' : '.phone_notify()'
},
{
	'id' : 'prev_check_time', 'label' : getString('ahr_prev_check_time_label'), 'flex' : 1,
	'primary' : false, 'hidden' : true, 'fm_class' : 'ahr', 'fm_field_render' : '.prev_check_time()'
},
{
	'id' : 'requestor', 'label' : getString('ahr_requestor_label'), 'flex' : 1,
	'primary' : false, 'hidden' : true, 'fm_class' : 'ahr', 'fm_field_render' : '.requestor()'
},
{
	'id' : 'selection_depth', 'label' : getString('ahr_selection_depth_label'), 'flex' : 1,
	'primary' : false, 'hidden' : true, 'fm_class' : 'ahr', 'fm_field_render' : '.selection_depth()'
},
{
	'id' : 'target', 'label' : getString('ahr_target_label'), 'flex' : 1,
	'primary' : false, 'hidden' : true, 'fm_class' : 'ahr', 'fm_field_render' : '.target()'
},
{
	'id' : 'usr', 'label' : getString('ahr_usr_label'), 'flex' : 1,
	'primary' : false, 'hidden' : true, 'fm_class' : 'ahr', 'fm_field_render' : '.usr()'
}
	];
	return cols;
}

function checkin_cols() {
	var cols = [
		{
			'id' : 'checkin_status', 'label' : getString('checkin_label_status'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : '', 'fm_field_render' : '.status.toString()'
		},
		{
			'id' : 'checkin_route_to', 'label' : getString('checkin_label_route_to'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : '', 'fm_field_render' : '.route_to.toString()'
		},
		{
			'id' : 'checkin_text', 'label' : getString('checkin_label_text'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : '', 'fm_field_render' : '.text.toString()'
		}
	];
	var std_cols = map_list( 
		circ_cols(), 
		function(o){ if ((o.fm_class == 'acp')||(o.fm_class == 'circ')) o.hidden = true; return o; }
	);
	return cols.concat( std_cols );
}

function circ_cols() {
	return  [
		{
			'id' : 'barcode', 'label' : getString('acp_label_barcode'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'acp', 'fm_field_render' : '.barcode()'
		},
		{
			'id' : 'call_number', 'label' : getString('acp_label_call_number'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.call_number()'
		},
		{
			'id' : 'copy_number', 'label' : getString('acp_label_copy_number'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.copy_number()'
		},
		{
			'id' : 'status', 'label' : getString('acp_label_status'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.status()'
		},
		{
			'id' : 'location', 'label' : getString('acp_label_location'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.location()'
		},
		{
			'id' : 'loan_duration', 'label' : getString('acp_label_loan_duration'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.loan_duration()'
		},
		{
			'id' : 'circ_lib', 'label' : getString('acp_label_circ_lib'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.circ_lib()'
		},
		{
			'id' : 'fine_level', 'label' : getString('acp_label_fine_level'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.fine_level()'
		},
		{
			'id' : 'deposit', 'label' : getString('acp_label_deposit'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.deposit()'
		},
		{
			'id' : 'deposit_amount', 'label' : getString('acp_label_deposit_amount'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.deposit_amount()'
		},
		{
			'id' : 'price', 'label' : getString('acp_label_price'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.price()'
		},
		{
			'id' : 'circ_as_type', 'label' : getString('acp_label_circ_as_type'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.circ_as_type()'
		},
		{
			'id' : 'circ_modifier', 'label' : getString('acp_label_circ_modifier'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.circ_modifier()'
		},
		{
			'id' : 'xact_start', 'label' : getString('circ_label_xact_start'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'circ', 'fm_field_render' : '.xact_start()'
		},
		{
			'id' : 'xact_finish', 'label' : getString('circ_label_xact_finish'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'circ', 'fm_field_render' : '.xact_finish()'
		},
		{
			'id' : 'renewal_remaining', 'label' : getString('circ_label_renewal_remaining'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'circ', 'fm_field_render' : '.renewal_remaining()'
		},
		{
			'id' : 'due_date', 'label' : getString('circ_label_due_date'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'circ', 'fm_field_render' : '.due_date().substr(0,10)'
		},
		{
			'id' : 'title', 'label' : getString('mvr_label_title'), 'flex' : 2,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mvr', 'fm_field_render' : '.title()'
		},
		{
			'id' : 'author', 'label' : getString('mvr_label_author'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mvr', 'fm_field_render' : '.author()'
		}
		
	]
};


