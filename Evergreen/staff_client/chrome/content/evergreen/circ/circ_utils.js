sdump('D_TRACE','Loading circ_tree.js\n');

function is_barcode_valid( barcode ) {

	// consider checkdigit, length, etc.

	return check_checkdigit( barcode );
}

function checkout_permit(barcode, patron_id, num_of_open_async_checkout_requests) {
	sdump('D_CIRC_UTILS',arg_dump(arguments,{0:true,1:true,2:true}));
	try {
		var check = user_request(
			'open-ils.circ',
			'open-ils.circ.permit_checkout',
			[ mw.G.auth_ses[0], barcode, patron_id, num_of_open_async_checkout_requests ]
		)[0];
		sdump('D_CIRC_UTILS','check = ' + js2JSON(check) + '\n');
		return check;	
	} catch(E) {
		handle_error(E);
		return null;
	}	
}

function checkout_by_copy_barcode(barcode, patron_id) {
	sdump('D_CIRC_UTILS',arg_dump(arguments,{0:true,1:true}));
	try {
		var check = user_request(
			'open-ils.circ',
			'open-ils.circ.checkout.barcode',
			[ mw.G.auth_ses[0], barcode, patron_id ]
		)[0];
		sdump('D_CIRC_UTILS','check = ' + js2JSON(check) + '\n');
		return check;
	} catch(E) {
		sdump('D_ERROR',E);
		return null;
	}
}

function checkin_by_copy_barcode(barcode) {
	sdump('D_CIRC_UTILS',arg_dump(arguments,{0:true}));
	try {
		var check = user_request(
			'open-ils.circ',
			'open-ils.circ.checkin.barcode',
			[ mw.G.auth_ses[0], barcode ]
		)[0];
		sdump('D_CIRC_UTILS','check = ' + js2JSON(check) + '\n');
		return check;
	} catch(E) {
		sdump('D_ERROR',E);
		return null;
	}
}

function renew_by_circ_id(id) {
	sdump('D_CIRC_UTILS',arg_dump(arguments,{0:true}));
	try {
		var check = user_request(
			'open-ils.circ',
			'open-ils.circ.renew',
			[ mw.G.auth_ses[0], id ]
		)[0];
		sdump('D_CIRC_UTILS','check = ' + js2JSON(check) + '\n');
		return check;
	} catch(E) {
		sdump('D_ERROR',E);
		return null;
	}
}

function checkin_cols() {
	var cols = [
		{
			'id' : 'checkin_status', 'label' : getString('checkin_label_status'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : '', 'fm_field_render' : '.status.toString()'
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
			'primary' : true, 'hidden' : false, 'fm_class' : 'acp', 'fm_field_render' : '.barcode()'
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
			'primary' : false, 'hidden' : false, 'fm_class' : 'circ', 'fm_field_render' : '.due_date()'
		},
		{
			'id' : 'title', 'label' : getString('mvr_label_title'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mvr', 'fm_field_render' : '.title()'
		},
		{
			'id' : 'author', 'label' : getString('mvr_label_author'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mvr', 'fm_field_render' : '.author()'
		}
		
	]
};


