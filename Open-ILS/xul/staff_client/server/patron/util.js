dump('entering patron/util.js\n');

if (typeof patron == 'undefined') var patron = {};
patron.util = {};

patron.util.EXPORT_OK	= [ 
	'columns', 'std_map_row_to_column', 'retrieve_au_via_id', 'retrieve_fleshed_au_via_id', 'set_penalty_css'
];
patron.util.EXPORT_TAGS	= { ':all' : patron.util.EXPORT_OK };

patron.util.columns = function(modify) {
	
	JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});

	function getString(s) { return data.entities[s]; }

	var c = [
		{
			'id' : 'barcode', 'label' : 'Barcode', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.card().barcode()'
		},
		{ 
			'id' : 'usrname', 'label' : 'Login Name', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.usrname()'
		},
		{ 
			'id' : 'profile', 'label' : 'Group', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'obj.OpenILS.data.hash.pgt[ my.au.profile() ].name()'
		},
		{ 
			'id' : 'active', 'label' : getString('staff.au_label_active'), 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.active() ? "Yes" : "No"'
		},
		{ 
			'id' : 'id', 'label' : getString('staff.au_label_id'), 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.id()'
		},
		{ 
			'id' : 'prefix', 'label' : getString('staff.au_label_prefix'), 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.prefix()'
		},
		{ 
			'id' : 'family_name', 'label' : getString('staff.au_label_family_name'), 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.family_name()'
		},
		{ 
			'id' : 'first_given_name', 'label' : getString('staff.au_label_first_given_name'), 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.first_given_name()'
		},
		{ 
			'id' : 'second_given_name', 'label' : getString('staff.au_label_second_given_name'), 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.second_given_name()'
		},
		{ 
			'id' : 'suffix', 'label' : getString('staff.au_label_suffix'), 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.suffix()'
		},
		{ 
			'id' : 'alert_message', 'label' : 'Alert', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.alert_message()'
		},
		{ 
			'id' : 'claims_returned_count', 'label' : 'Returns Claimed', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.claims_returned_count()'
		},
		{ 
			'id' : 'create_date', 'label' : 'Created On', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.create_date()'
		},
		{ 
			'id' : 'expire_date', 'label' : 'Expires On', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.expire_date()'
		},
		{ 
			'id' : 'home_ou', 'label' : 'Home Lib', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'obj.OpenILS.data.hash.aou[ my.au.home_ou() ].shortname()'
		},
		{ 
			'id' : 'credit_forward_balance', 'label' : 'Credit', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.credit_forward_balance()'
		},
		{ 
			'id' : 'day_phone', 'label' : 'Day Phone', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.day_phone()'
		},
		{ 
			'id' : 'evening_phone', 'label' : 'Evening Phone', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.evening_phone()'
		},
		{ 
			'id' : 'other_phone', 'label' : 'Other Phone', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.other_phone()'
		},
		{ 
			'id' : 'email', 'label' : 'Email', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.email()'
		},
		{ 
			'id' : 'dob', 'label' : 'Birth Date', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.dob()'
		},
		{ 
			'id' : 'ident_type', 'label' : 'Ident Type', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'obj.OpenILS.data.hash.cit[ my.au.ident_type() ].name()'
		},
		{ 
			'id' : 'ident_value', 'label' : 'Ident Value', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.ident_value()'
		},
		{ 
			'id' : 'ident_type2', 'label' : 'Ident Type 2', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'obj.OpenILS.data.hash.cit[ my.au.ident_type2() ].name()'
		},
		{ 
			'id' : 'ident_value2', 'label' : 'Ident Value 2', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.ident_value2()'
		},
		{ 
			'id' : 'net_access_level', 'label' : 'Net Access', 'flex' : 1, 
			'primary' : false, 'hidden' : true, 'render' : 'my.au.net_access_level()'
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

patron.util.std_map_row_to_column = function() {
	return function(row,col) {
		// row contains { 'my' : { 'au' : {} } }
		// col contains one of the objects listed above in columns
		
		var obj = {}; obj.OpenILS = {}; 
		JSAN.use('util.error'); obj.error = new util.error();
		JSAN.use('OpenILS.data'); obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'});

		var my = row.my;
		var value;
		try { 
			value = eval( col.render );
		} catch(E) {
			obj.error.sdump('D_ERROR','map_row_to_column: ' + E);
			value = '???';
		}
		return value;
	}
}

patron.util.retrieve_au_via_id = function(session, id) {
	JSAN.use('util.network');
	var network = new util.network();
	var patron = network.request(
		api.FM_AU_RETRIEVE_VIA_ID.app,
		api.FM_AU_RETRIEVE_VIA_ID.method,
		[ session, id ]
	);
	return patron;
}

patron.util.retrieve_fleshed_au_via_id = function(session, id) {
	JSAN.use('util.network');
	var network = new util.network();
	var patron = network.simple_request(
		'FM_AU_FLESHED_RETRIEVE_VIA_ID',
		[ session, id ]
	);
	patron.util.set_penalty_css(patron);
	return patron;
}

patron.util.set_penalty_css = function(patron) {
	try {
		var penalties = patron.standing_penalties();
		for (var i = 0; i < penalties.length; i++) {
			/* this comes from /opac/common/js/utils.js */
			addCSSClass(document.documentElement,penalties[i].penalty_type());
		}
	} catch(E) {
		dump('patron.util.set_penalty_css: ' + E + '\n');
		alert('patron.util.set_penalty_css: ' + E + '\n');
	}
}


dump('exiting patron/util.js\n');
