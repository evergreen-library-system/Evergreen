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
		return patron_get_bills_total_from_bills( au.bills );
	}
}

function patron_get_bills_total_from_bills( bills ) {
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
			sdump('D_PATRON_UTILS','checkouts = ' + js2JSON(au.checkouts()) + '\n');
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
