sdump('D_TRACE','Loading patron_utils.js\n');

function fake_patron() {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	var p = new au(); 
	p.family_name( 'Retrieving' ); 
	p.checkouts( [] ); 
	p.hold_requests( [] ); 
	p.credit_forward_balance('0.00');
	p.bills = [];
	return p;
}

function hold_status_as_text( status ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	if (typeof(status) == 'object') status = status.status();
	var text;
	switch(status) {
		case "1" : text = getString('holds_status_waiting_for_copy'); break;
		case "2" : text = getString('holds_status_waiting_for_capture'); break;
		case "3" : text = getString('holds_status_in_transit'); break;
		case "4" : text = getString('holds_status_available'); break;
		default : text = "Eh?"; break;
	}
	return text;
}

function patron_get_full_name( au ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	var name = '';
	if (au.prefix()) name += au.prefix() + ' ';	
	if (au.family_name()) name += au.family_name() + ', ';	
	if (au.first_given_name()) name += au.first_given_name() + ' ';	
	if (au.second_given_name()) name += au.second_given_name() + ' ';	
	if (au.suffix()) name += au.suffix() + ' ';	
	return name;
}

function patron_get_barcode( au ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	try {
		if (au && au.card && au.card() ) {
			if ( (au.card()!='null') && (typeof(au.card())=='object') ) {
				return au.card().barcode();
			} else {
				return find_id_object_in_list( au.cards(), au.card() ).barcode();
			}
		}
	} catch(E) {
		sdump('D_ERROR',E);
	}
	return '???';
}

function patron_get_bills( au, f ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	try {
		var bills = user_request(
			'open-ils.actor',
			'open-ils.actor.user.transactions.have_balance',
			[ mw.G.auth_ses[0], au.id() ],
			f
		)[0];

		if (!f) {
			sdump('D_PATRON_UTILS','bills = ' + js2JSON(bills) + '\n');
			au.bills = bills;   // FIXME: make bills a virtual field of au
			return bills;
		}
	} catch(E) {
		sdump('D_ERROR',js2JSON(E) + '\n');
		return null;
	}

}

function patron_get_bills_total( au ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	if (au.bills == null || au.bills == undefined)
		return '???';
	else {
		return get_bills_total( au.bills );
	}
}

function get_bills_total( bills ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	var total = 0;
	for (var i = 0; i < bills.length; i++) {
		total += dollars_float_to_cents_integer( bills[i].balance_owed() );
	}
	sdump('D_PATRON_UTILS','bills_total $$$ = ' + cents_as_dollars( total ) + '\n');
	return cents_as_dollars( total );
}

function patron_get_credit_total( au ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	/* FIXME: I can use CSS to style this number as money. */
	return '$' + au.credit_forward_balance();
}

function patron_get_checkouts( au, f ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	try {
		var checkouts = user_request(
			'open-ils.circ',
			'open-ils.circ.actor.user.checked_out',
			[ mw.G.auth_ses[0], au.id() ],
			f
		)[0];

		if (!f) {
			sdump('D_PATRON_UTILS','checkouts = ' + js2JSON(checkouts) + '\n');
			if (!checkouts) checkouts = [];
			au.checkouts( checkouts );
			return checkouts;
		}
	} catch(E) {
		sdump('D_ERROR',js2JSON(E) + '\n');
		return null;
	}
}

function patron_get_checkouts_total( au ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	if (au.checkouts() == null)
		return '???';
	else
		return au.checkouts().length;
}

// Need an API call or virtual field to determine this
function patron_get_checkouts_overdue_total( au ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	if (! au.checkouts()) patron_get_checkouts( au );
	var total = 0;
	if ( (au.checkouts() != null) && (typeof(au.checkouts())=='object') ) {
		for (var i = 0; i < au.checkouts().length; i++) {
			var item = au.checkouts()[i];
			var due_date = item.circ.due_date();
			due_date = due_date.substr(0,4) + due_date.substr(5,2) + due_date.substr(8,2);
			var today = formatted_date( new Date() , '%Y%m%d' );
			if (today > due_date) total++;
		}
	}
	sdump('D_PATRON_UTILS','\toverdue = ' + total + '\n');
	return total;
}

function patron_get_holds( au, f ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	try {
		var hold_requests = user_request(
			'open-ils.circ',
			'open-ils.circ.holds.retrieve',
			[ mw.G.auth_ses[0], au.id() ],
			f
		)[0];

		if (!f) {
			sdump('D_PATRON_UTILS','holds = ' + js2JSON(au.hold_requests()) + '\n');
			au.hold_requests( hold_requests );
			return hold_requests;
		}
	} catch(E) {
		sdump('D_ERROR',js2JSON(E) + '\n');
		return null;
	}
}

function patron_get_holds_total( au ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	if (au.hold_requests() == null)
		return '???';
	else
		return au.hold_requests().length;
}

function patron_get_hold_status( hold, f ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	try {
		var status = user_request(
			'open-ils.circ',
			'open-ils.circ.hold.status.retrieve',
			[ mw.G.auth_ses[0], hold.id() ],
			f
		)[0];

		if (!f) {
			sdump('D_PATRON_UTILS','status = ' + status + '\n');
			hold.status( status );
			return status;
		}
	} catch(E) {
		sdump('D_ERROR',js2JSON(E) + '\n');
		return null;
	}
}

function patron_get_holds_available_total( au ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	var total = 0;
	if ( (au.hold_requests() != null) && (typeof(au.hold_requests()) == 'object') ) {
		for (var i = 0; i < au.hold_requests().length; i++) {
			var hold = au.hold_requests()[i];
			if (hold.capture_time()) total++;
		}
	}
	sdump('D_PATRON_UTILS','\tavailable = ' + total + '\n');
	return total;
}

function patron_get_home_ou_name( au ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	if (au && 
		au.home_ou && 
		au.home_ou() && 
		mw.G.org_tree_hash &&
		mw.G.org_tree_hash[ au.home_ou() ] && 
		mw.G.org_tree_hash[ au.home_ou() ].name &&
		mw.G.org_tree_hash[ au.home_ou() ].name()
	) {
		return mw.G.org_tree_hash[ au.home_ou() ].name();
	} else {
		return null;
	}
}

function patron_get_ident1_type_as_text( au ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	if (au && 
		au.ident_type && 
		au.ident_type() && 
		mw.G.cit_hash &&
		mw.G.cit_hash[ au.ident_type() ] && 
		mw.G.cit_hash[ au.ident_type() ].name &&
		mw.G.cit_hash[ au.ident_type() ].name()
	) {
		return mw.G.cit_hash[ au.ident_type() ].name();
	} else {
		return null;
	}
}

function patron_get_ident2_type_as_text( au ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	if (au && 
		au.ident_type2 && 
		au.ident_type2() && 
		mw.G.cit_hash &&
		mw.G.cit_hash[ au.ident_type2() ] && 
		mw.G.cit_hash[ au.ident_type2() ].name &&
		mw.G.cit_hash[ au.ident_type2() ].name()
	) {
		return mw.G.cit_hash[ au.ident_type2() ].name();
	} else {
		return null;
	}
}

function patron_get_profile_as_text( au ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	if (au && 
		au.profile && 
		au.profile() && 
		mw.G.ap_hash &&
		mw.G.ap_hash[ au.profile() ] && 
		mw.G.ap_hash[ au.profile() ].name &&
		mw.G.ap_hash[ au.profile() ].name()
	) {
		return mw.G.ap_hash[ au.profile() ].name();
	} else {
		return null;
	}
}

function patron_get_standing_as_text( au ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	if (au && 
		au.standing && 
		au.standing() && 
		mw.G.cst_hash &&
		mw.G.cst_hash[ au.standing() ] && 
		mw.G.cst_hash[ au.standing() ].value &&
		mw.G.cst_hash[ au.standing() ].value()
	) {
		return mw.G.cst_hash[ au.standing() ].value();
	} else {
		return null;
	}
}

function patron_get_standing_css_style( value ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments,{0:true}));
	switch(value) {
		case 'Good' : case '1' : return 'background-color: lightgreen;'; break;
		case 'Barred' : case '2' : return 'background-color: yellow;'; break;
		case 'Blocked' : case '3' : return 'background-color: red;'; break;
		default: return 'background-color: white;'; break;
	}
}

function patron_pay_bills( payment_blob ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments,{0:true}));
	try {
		//alert("Bill's API call goes here.  payment_blob = \n" + pretty_print( js2JSON( payment_blob ) ) + '\n');
		alert( 'payment_blob\n' + js2JSON( payment_blob ) );
		var result = user_request(
			'open-ils.circ',
			'open-ils.circ.money.payment',
			[ mw.G.auth_ses[0], payment_blob ]
		)[0];
		alert( pretty_print( js2JSON( result ) ) );
		return true;
	} catch(E) {
		handle_error(E);
		return false;
	}
}

function retrieve_patron_by_barcode( barcode, f ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	if (!barcode) return null;
	return user_request( 'open-ils.actor', 'open-ils.actor.user.fleshed.retrieve_by_barcode', [ mw.G.auth_ses[0], barcode ], f )[0];
}

function retrieve_patron_by_id( id, f ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	if (!id) return null;
	return user_request( 'open-ils.actor', 'open-ils.actor.user.fleshed.retrieve', [ mw.G.auth_ses[0], id ], f )[0];
}

function save_patron( au, f ) {
	sdump('D_PATRON_UTILS',arg_dump(arguments));
	try {
		var result = user_request(
			'open-ils.actor',
			'open-ils.actor.patron.update',
			[ mw.G.auth_ses[0], au ],
			f
		)[0];
		if (!f) sdump('D_PATRON_UTILS','result = ' + js2JSON(result) + '\n');
		return result;
	} catch(E) {
		handle_error(E);
		return null;
	}
}

function patron_edit_rows() {
	var rows = [
{
	'id' : 'standing', 'label' : getString('au_standing_label'), 'flex' : 1, 'class' : 'pale_violet_red',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : 'mw.G.cst_hash[ $$.standing() ].value()',
	'entry_widget' : 'menulist', 'populate_with' : map_object(mw.G.cst_hash,function(key,value){return [value.value(), key];}),
	'entry_event' : 'command', 'entry_code' : '{ au.standing( ev.target.value ); }',
	'rdefault' : '.standing()'
},
{
	'id' : 'alert_message', 'label' : getString('au_alert_message_label'), 'flex' : 1, 'class' : 'pale_violet_red',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.alert_message()',
	'entry_widget' : 'textbox', 'rdefault' : '.alert_message()',
	'entry_event' : 'change', 'entry_code' : '{ alert(js2JSON(au)); au.alert_message( ev.target.value ); }'
},
{
	'id' : 'create_date', 'label' : getString('au_create_date_label'), 'flex' : 1, 'class' : 'peach_puff',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.create_date()',
	'entry_widget' : 'textbox', 'entry_widget_attributes' : { 'readonly' : 'true' }, 'rdefault' : '.create_date()',
	'entry_event' : 'change', 'entry_code' : '{ au.create_date( ev.target.value ); }'
},
{
	'id' : 'expire_date', 'label' : getString('au_expire_date_label'), 'flex' : 1, 'class' : 'peach_puff',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.expire_date()',
	'entry_widget' : 'textbox', 'rdefault' : '.expire_date()',
	'entry_event' : 'change', 'entry_code' : '{ au.expire_date( ev.target.value ); }'
},
{
	'id' : 'active', 'label' : getString('au_active_label'), 'flex' : 1, 'class' : 'peach_puff',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : 'yesno($$.active())',
	'entry_widget' : 'menulist', 'populate_with' : { 'Yes' : 1 , 'No' : 0 }, 'rdefault' : '.active()',
	'entry_event' : 'command', 'entry_code' : '{ au.active( ev.target.value ); }'
},
{
	'id' : 'card', 'label' : getString('au_card_label'), 'flex' : 1, 'class' : 'peach_puff',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.card().barcode()',
	'entry_widget' : 'button', 'entry_widget_attributes' : { 'label' : 'New Card', 'oncommand' : 'alert("test");' },
	'entry_event' : 'command', 'entry_code' : '{ new_card(au); }'
},
{
	'id' : 'home_ou', 'label' : getString('au_home_ou_label'), 'flex' : 1, 'class' : 'peach_puff',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : 'mw.G.org_tree_hash[ $$.home_ou() ].shortname()',
	'entry_widget' : 'menulist', 'populate_with' : map_object(mw.G.org_tree_hash,function(key,value){return [value.shortname(), key];}),
	'entry_event' : 'command', 'entry_code' : '{ au.home_ou( ev.target.value ); }',
	'rdefault' : '.home_ou()'
},
{
	'id' : 'profile', 'label' : getString('au_profile_label'), 'flex' : 1, 'class' : 'peach_puff',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : 'ap_hash[ $$.profile() ].name()',
	'entry_widget' : 'menulist', 'populate_with' : map_object(mw.G.ap_hash,function(key,value){return [value.name(), key];}),
	'entry_event' : 'command', 'entry_code' : '{ au.profile( ev.target.value ); }',
	'rdefault' : '.profile()'
},
{
	'id' : 'prefix', 'label' : getString('au_prefix_label'), 'flex' : 1, 'class' : 'dark_salmon',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.prefix()',
	'entry_widget' : 'menulist', 'entry_widget_attributes' : { 'editable' : 'true' },
	'entry_event' : 'command', 'entry_code' : '{ au.prefix( ev.target.value ); }',
	'populate_with' : { 'Mr.' : 'Mr.' , 'Mrs.' : 'Mrs.' }, 'rdefault' : '.prefix()'
},
{
	'id' : 'family_name', 'label' : getString('au_family_name_label'), 'flex' : 1, 'class' : 'dark_salmon',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.family_name()',
	'entry_widget' : 'textbox', 'rdefault' : '.family_name()',
	'entry_event' : 'change', 'entry_code' : '{ au.family_name( ev.target.value ); }'
},
{
	'id' : 'first_given_name', 'label' : getString('au_first_given_name_label'), 'flex' : 1, 'class' : 'dark_salmon',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.first_given_name()',
	'entry_widget' : 'textbox', 'rdefault' : '.first_given_name()',
	'entry_event' : 'change', 'entry_code' : '{ au.frist_given_name( ev.target.value ); }'
},
{
	'id' : 'second_given_name', 'label' : getString('au_second_given_name_label'), 'flex' : 1, 'class' : 'dark_salmon',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.second_given_name()',
	'entry_widget' : 'textbox', 'rdefault' : '.second_given_name()',
	'entry_event' : 'change', 'entry_code' : '{ au.second_given_name( ev.target.value ); }'
},
{
	'id' : 'suffix', 'label' : getString('au_suffix_label'), 'flex' : 1, 'class' : 'dark_salmon',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.suffix()',
	'entry_widget' : 'menulist', 'entry_widget_attributes' : { 'editable' : 'true' },
	'populate_with' : { 'Sr.' : 'Sr.' , 'Jr.' : 'Jr.' }, 'rdefault' : '.suffix()',
	'entry_event' : 'command', 'entry_code' : '{ au.suffix( ev.target.value ); }'
},
{
	'id' : 'dob', 'label' : getString('au_dob_label'), 'flex' : 1, 'class' : 'cadet_blue',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.dob()',
	'entry_widget' : 'textbox', 'rdefault' : '.dob()',
	'entry_event' : 'change', 'entry_code' : '{ au.dob( ev.target.value ); }'
},
{
	'id' : 'ident_type', 'label' : getString('au_ident_type_label'), 'flex' : 1, 'class' : 'cadet_blue',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : 'mw.G.cit_hash[ $$.ident_type() ].name()',
	'entry_widget' : 'menulist', 'populate_with' : map_object(mw.G.cit_hash,function(key,value){return [value.name(), key];}), 
	'rdefault' : '.ident_type()',
	'entry_event' : 'command', 'entry_code' : '{ au.ident_type( ev.target.value ); }'
},
{
	'id' : 'ident_value', 'label' : getString('au_ident_value_label'), 'flex' : 1, 'class' : 'cadet_blue',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.ident_value()',
	'entry_widget' : 'textbox', 'rdefault' : '.ident_value()',
	'entry_event' : 'change', 'entry_code' : '{ au.ident_value( ev.target.value ); }'
},
{
	'id' : 'ident_type2', 'label' : getString('au_ident_type2_label'), 'flex' : 1, 'class' : 'cadet_blue',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : 'mw.G.cit_hash[ $$.ident_type2() ].name()',
	'entry_widget' : 'menulist', 'populate_with' : map_object(mw.G.cit_hash,function(key,value){return [value.name(), key];}), 
	'rdefault' : '.ident_type2()',
	'entry_event' : 'command', 'entry_code' : '{ au.ident_type2( ev.target.value ); }'
},
{
	'id' : 'ident_value2', 'label' : getString('au_ident_value2_label'), 'flex' : 1, 'class' : 'cadet_blue',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.ident_value2()',
	'entry_widget' : 'textbox', 'rdefault' : '.ident_value2()',
	'entry_event' : 'change', 'entry_code' : '{ au.ident_value2( ev.target.value ); }'
},
{
	'id' : 'addresses', 'label' : getString('au_addresses_label'), 'flex' : 1, 'class' : 'coral',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.addresses().length + " addresses"',
	'entry_widget' : 'button', 'entry_widget_attributes' : { 'label' : 'View/Edit/New' },
	'entry_event' : 'command', 'entry_code' : '{ edit_addresses(au); }'
},
{
	'id' : 'day_phone', 'label' : getString('au_day_phone_label'), 'flex' : 1, 'class' : 'coral',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.day_phone()',
	'entry_widget' : 'textbox', 'rdefault' : '.day_phone()',
	'entry_event' : 'change', 'entry_code' : '{ au.day_phone( ev.target.value ); }'
},
{
	'id' : 'evening_phone', 'label' : getString('au_evening_phone_label'), 'flex' : 1, 'class' : 'coral',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.evening_phone()',
	'entry_widget' : 'textbox', 'rdefault' : '.evening_phone()',
	'entry_event' : 'change', 'entry_code' : '{ au.evening_phone( ev.target.value ); }'
},
{
	'id' : 'other_phone', 'label' : getString('au_other_phone_label'), 'flex' : 1, 'class' : 'coral',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.other_phone()',
	'entry_widget' : 'textbox', 'rdefault' : '.other_phone()',
	'entry_event' : 'change', 'entry_code' : '{ au.other_phone( ev.target.value ); }'
},
{
	'id' : 'email', 'label' : getString('au_email_label'), 'flex' : 1, 'class' : 'coral',
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.email()',
	'entry_widget' : 'textbox', 'rdefault' : '.email()',
	'entry_event' : 'change', 'entry_code' : '{ au.email( ev.target.value ); }'
},
{
	'id' : 'master_account', 'label' : getString('au_master_account_label'), 'flex' : 1,
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.master_account()',
	'entry_widget' : 'textbox', 'rdefault' : '.master_account()',
	'entry_event' : 'change', 'entry_code' : '{ au.master_account( ev.target.value ); }'
},
{
	'id' : 'net_access_level', 'label' : getString('au_net_access_level_label'), 'flex' : 1,
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.net_access_level()',
	'entry_widget' : 'textbox', 'rdefault' : '.net_access_level()',
	'entry_event' : 'change', 'entry_code' : '{ au.net_access_level( ev.target.value ); }'
},
{
	'id' : 'passwd', 'label' : getString('au_passwd_label'), 'flex' : 1,
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.passwd()',
	'entry_widget' : 'textbox', 'rdefault' : '.passwd()',
	'entry_event' : 'change', 'entry_code' : '{ au.passwd( ev.target.value ); }'
},
{
	'id' : 'photo_url', 'label' : getString('au_photo_url_label'), 'flex' : 1,
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.photo_url()',
	'entry_widget' : 'textbox', 'rdefault' : '.photo_url()',
	'entry_event' : 'change', 'entry_code' : '{ au.photo_url( ev.target.value ); }'
},
{
	'id' : 'stat_cat_entries', 'label' : getString('au_stat_cat_entries_label'), 'flex' : 1,
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.stat_cat_entries().length + " entries"',
	'entry_widget' : 'button', 'entry_widget_attributes' : { 'label' : 'View/Edit' },
	'entry_event' : 'command', 'entry_code' : '{ edit_stat_cat_entries(au); }'
},
{
	'id' : 'survey_responses', 'label' : getString('au_survey_responses_label'), 'flex' : 1,
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.survey_responses().length + " responses"',
	'entry_widget' : 'button', 'entry_widget_attributes' : { 'label' : 'View/New' },
	'entry_event' : 'command', 'entry_code' : '{ new_survey_responses(au); }'
},
{
	'id' : 'usrgroup', 'label' : getString('au_usrgroup_label'), 'flex' : 1,
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.usrgroup()',
	'entry_widget' : 'textbox', 'rdefault' : '.usrgroup()',
	'entry_event' : 'change', 'entry_code' : '{ au.usrgroup( ev.target.value ); }'
},
{
	'id' : 'usrname', 'label' : getString('au_usrname_label'), 'flex' : 1,
	'primary' : false, 'hidden' : false, 'fm_class' : 'au', 'fm_field_render' : '.usrname()',
	'entry_widget' : 'textbox', 'rdefault' : '.usrname()',
	'entry_event' : 'change', 'entry_code' : '{ au.usrname( ev.target.value ); }'
},
];

	return rows;
}
