mw.sdump('D_LEGACY','Loading patron.js\n');
//var newdoctype = document.implementation.createDocumentType("HTML", "-//W3C//DTD HTML 4.01 Transitional//EN","");
var HTMLdoc;// = document.implementation.createDocument("", "", newdoctype);
try {
	if (typeof(PATRON)=='object') { 
		mw.sdump('D_LEGACY','Already loaded\n');
		exit; 
	}
} catch(E) {
}
var PATRON = {};
PATRON['search'] = {};
PATRON['search_results'] = [];
PATRON['checkouts'] = [];
var hash_aua = {};
var hash_au = {};
var hash_ac = {};
var backup_au = {};
//var hash_ap = {};
var response_list = [];
var local_stat_cats = [];
var local_stat_cat_entries = {};
var patron_hits_per_page = 20;

var new_id = -1;

var patron_list_columns = [ 
	{ 'f' : 'prefix', 'v' : 'Prefix', 'hidden' : true },
	{ 'f' : 'family_name', 'v' : 'Family Name', 'primary' : true },
	{ 'f' : 'first_given_name', 'v' : 'First Name' },
	{ 'f' : 'second_given_name', 'v' : 'Middle Name' },
	{ 'f' : 'suffix', 'v' : 'Suffix', 'hidden' : false },
	{ 'f' : 'email', 'v' : 'Email', 'hidden' : true  },
	{ 'f' : 'day_phone', 'v' : 'Day Phone', 'hidden' : false },
	{ 'f' : 'evening_phone', 'v' : 'Evening Phone', 'hidden' : true },
	{ 'f' : 'other_phone', 'v' : 'Other Phone', 'hidden' : true },
	{ 'f' : 'ident_value', 'v' : 'Ident Value', 'hidden' : false },
	{ 'f' : 'ident_type', 'v' : 'Ident Type', 'hidden' : true },
	{ 'f' : 'ident_value2', 'v' : 'Ident Value 2', 'hidden' : true },
	{ 'f' : 'ident_type2', 'v' : 'Ident Type 2', 'hidden' : true},
	{ 'f' : 'dob', 'v' : 'Date of Birth', 'hidden' : true},
	{ 'f' : 'active', 'v' : 'Active', 'hidden' : true},
	{ 'f' : 'expire_date', 'v' : 'Expire Date', 'hidden' : true},
	{ 's' : 'home_ou', 'f' : 'shortname', 'v' : 'Home Lib', 'hidden' : true},
	{ 'f' : 'usrname', 'v' : 'Login Name', 'hidden' : true},
	{ 'f' : 'usrgroup', 'v' : 'Group', 'hidden' : true},
	{ 's' : 'mailing_address', 'f' : 'street1', 'v' : 'Mailing Address - Street 1', 'hidden' : true},
	{ 's' : 'mailing_address', 'f' : 'street2', 'v' : 'Mailing Address - Street 2', 'hidden' : true},
	{ 's' : 'mailing_address', 'f' : 'city', 'v' : 'Mailing Address - City', 'hidden' : true},
	{ 's' : 'mailing_address', 'f' : 'state', 'v' : 'Mailing Address - State', 'hidden' : true},
	{ 's' : 'mailing_address', 'f' : 'post_code', 'v' : 'Mailing Address - ZIP', 'hidden' : false},
	{ 's' : 'billing_address', 'f' : 'street1', 'v' : 'Physical Address - Street 1', 'hidden' : true},
	{ 's' : 'billing_address', 'f' : 'street2', 'v' : 'Physical Address - Street 2', 'hidden' : true},
	{ 's' : 'billing_address', 'f' : 'city', 'v' : 'Physical Address - City', 'hidden' : true},
	{ 's' : 'billing_address', 'f' : 'state', 'v' : 'Physical Address - State', 'hidden' : true},
	{ 's' : 'billing_address', 'f' : 'post_code', 'v' : 'Physical Address - ZIP', 'hidden' : false}
];


function patron_init() {
	mw.sdump('D_LEGACY','**** TESTING: patron.js: patron_init(): ' + mw.G.main_test_variable + '\n');
	mw.sdump('D_LEGACY','PATRON = ' + js2JSON(PATRON) + '\n');
	var textbox = document.getElementById('patron_scan_textbox');
	if (textbox) textbox.addEventListener("keypress",patron_handle_keypress,false);
	/* 
	Originally, the idea here was to setup the PATRON object based on barcode if the bundle loader
	set a params.barcode.  This would also switch the barcode scan prompt to the patron summary
	sidebar.
	*/
	patron_init_if_barcode();
}

function patron_handle_keypress(ev) {
	if (ev.keyCode && ev.keyCode == 13) {
		switch(this) {
			case document.getElementById('patron_scan_textbox') :
				ev.preventDefault();
				PATRON.scan_submit(ev);
			break;
			default:
			break;
		}
	}
}

function patron_new_init() {
	mw.sdump('D_LEGACY','**** TESTING: patron.js: patron_new_init(): ' + mw.G.main_test_variable + '\n');
	mw.sdump('D_LEGACY','PATRON = ' + js2JSON(PATRON) + '\n');
	PATRON.au = new au();
	PATRON.au.id( new_id-- );
	PATRON.au.isnew( '1' );
	PATRON.au.profile( mw.G.ap_list[0].id() );
	PATRON.au.ident_type( mw.G.cit_list[0].id() );
	PATRON.au.home_ou( mw.G.user_ou.id() );
	PATRON.au.addresses( [] );
	PATRON.au.stat_cat_entries( [] );

		var card = new ac();
		card.id( new_id-- );
		card.isnew( '1' );
		card.barcode( 'REQUIRED' );
		//PATRON.barcode = 'REQUIRED';
		card.usr( PATRON.au.id() );
		hash_ac[ card.id() ] =  card;

	PATRON.au.card( card );
	PATRON.au.cards( [ card ] );
	PATRON.related_refresh(PATRON.au.id());

	var passwd = document.getElementById( 'patron_edit_system_new_passwd_textbox' );
	passwd.value = Math.floor( (Math.random() * 9000) + 1000 );
	PATRON.au.passwd( passwd.value );

	var textbox = document.getElementById( 'patron_edit_system_barcode_textbox' );
	textbox.select(); textbox.focus();
}

function patron_edit_init() {
	mw.sdump('D_LEGACY','**** TESTING: patron.js: patron_edit_init(): ' + mw.G.main_test_variable + '\n');
	mw.sdump('D_LEGACY','PATRON = ' + js2JSON(PATRON) + '\n');
	//mw.sdump('D_LEGACY','PATRON.au.array.length = ' + PATRON.au.array.length + '\n');
	populate_patron_edit_library_menu();
	populate_patron_edit_prefix_menu();
	populate_patron_edit_suffix_menu();
	populate_patron_edit_profile_menu();
	populate_patron_edit_ident_type_menu();
	populate_patron_edit_ident_type_menu2();
	PATRON.summary_refresh();
	local_stat_cats = mw.G.actsc_list;
	populate_rows_with_local_stat_cats(
		local_stat_cats,
		local_stat_cat_entries,
		'pescg_rows',
		true
	);
	PATRON.summary_refresh();
}

function patron_init_if_barcode() {
	try {
		if ( params.barcode ) {
			mw.sdump('D_LEGACY','patron_init(): patron.refresh()\n');
			PATRON.retrieve_patron(params.barcode);
			var deck = document.getElementById('patron_scan_deck');
			if (deck) { deck.setAttribute('selectedIndex','1'); }
		}
	} catch(E) {
		//mw.sdump('D_LEGACY','patron_init_if_barcode ERROR: ' + js2JSON(E) + '\n');
		mw.sdump('D_LEGACY','patron_init_if_barcode failed\n');
	}
}

function populate_patron_edit_library_menu() {
	try {
		//populate_lib_list(
		populate_lib_list_with_branch(
			'patron_edit_system_library_menulist',
			'patron_edit_system_library_menupopup',
			mw.G.user_ou,
			mw.G.org_tree,
			true
		);
	} catch(E) {
		mw.sdump('D_LEGACY','populate_patron_edit_library_menu ERROR: ' + js2JSON(E) + '\n');
		//mw.sdump('D_LEGACY','populate_patron_edit_library_menu failed\n');
	}
}

function set_patron_edit_library_menu() {
	var menuitem_id = 
		'libitem' +
		find_ou(
			mw.G.org_tree,
			PATRON.au.home_ou()
		).id();
	var menuitem = document.getElementById(
		menuitem_id
	);
	var homelib_e = document.getElementById('patron_edit_system_library_menulist');
	if (homelib_e) { 
		homelib_e.selectedItem = menuitem; 
		mw.sdump('D_LEGACY','\tShould be set\n');
	}
}

function populate_patron_edit_prefix_menu() {
	try {
		populate_name_prefix(
			'patron_edit_system_prefix_menulist',
			'patron_edit_system_prefix_menupopup'	
		);
	} catch(E) {
		//mw.sdump('D_LEGACY','populate_patron_edit_prefix_menu ERROR: ' + js2JSON(E) + '\n');
		mw.sdump('D_LEGACY','populate_patron_edit_prefix_menu failed\n');
	}
}

function populate_patron_edit_suffix_menu() {
	try {
		populate_name_suffix(
			'patron_edit_system_suffix_menulist',	
			'patron_edit_system_suffix_menupopup'	
		);
	} catch(E) {
		//mw.sdump('D_LEGACY','populate_patron_edit_suffix_menu ERROR: ' + js2JSON(E) + '\n');
		mw.sdump('D_LEGACY','populate_patron_edit_suffix_menu failed\n');
	}
}

function populate_patron_edit_profile_menu() {
	try {
		populate_user_profile(
			'patron_edit_system_profile_menulist',	
			'patron_edit_system_profile_menupopup'
		);
	} catch(E) {
		//mw.sdump('D_LEGACY','populate_patron_edit_profile_menu ERROR: ' + js2JSON(E) + '\n');
		mw.sdump('D_LEGACY','populate_patron_edit_profile_menu failed\n');
	}
}

function set_patron_edit_profile_menu() {
	var menuitem_id = 'profileitem' + PATRON.au.profile();
	var menuitem = document.getElementById(
		menuitem_id
	);
	var profile_e = document.getElementById('patron_edit_system_profile_menulist');
	if (profile_e) { profile_e.selectedItem = menuitem; }
}

function populate_patron_edit_ident_type_menu() {
	try {
		populate_ident_types(
			'patron_edit_system_id1type_menulist',	
			'patron_edit_system_id1type_menupopup',
			'1'
		);
	} catch(E) {
		mw.sdump('D_LEGACY','populate_patron_edit_ident_type_menu ERROR: ' + js2JSON(E) + '\n');
		//mw.sdump('D_LEGACY','populate_patron_edit_ident_type_menu failed\n');
	}
}

function set_patron_edit_ident_type_menu() {
	var menuitem_id = 'ident1item' + PATRON.au.ident_type();
	var menuitem = document.getElementById(
		menuitem_id
	);
	var id1 = document.getElementById('patron_edit_system_id1type_menulist');
	if (id1) { id1.selectedItem = menuitem; }
}

function populate_patron_edit_ident_type_menu2() {
	try {
		populate_ident_types(
			'patron_edit_system_id2type_menulist',	
			'patron_edit_system_id2type_menupopup',
			'2'
		);
	} catch(E) {
		//mw.sdump('D_LEGACY','populate_patron_edit_ident_type_menu2 ERROR: ' + js2JSON(E) + '\n');
		mw.sdump('D_LEGACY','populate_patron_edit_ident_type_menu2 failed\n');
	}
}

function set_patron_edit_ident_type_menu2() {
	var menuitem_id = 'ident2item' + PATRON.au.ident_type2();
	var menuitem = document.getElementById(
		menuitem_id
	);
	var id2_e = document.getElementById('patron_edit_system_id2type_menulist');
	if (id2_e) { id2_e.selectedItem = menuitem; }
}

function populate_patron_survey_grid(grid) {
	if (typeof(grid) != 'object') {
		grid = document.getElementById(grid);
	}
	if (!grid) { return; }
	var rows = grid.lastChild; if (!rows) { return; }
	try {
		empty_widget( rows );
		// 'open-ils.circ.survey.required.retrieve',
		// 'open-ils.circ.survey.retrieve.all',
		var result = mw.user_request(
			'open-ils.circ',
			'open-ils.circ.survey.retrieve.required',
			[ mw.G.auth_ses[0] ]
		)[0];
		if (typeof(result) != 'object') { throw('survey.retrieve.all did not return an object'); }
		var desc_1 = new Object();
		var desc_3 = new Object();
		var survey_hash = new Object();
		for (var i in result) {
			var survey = result[i];
			survey_hash[ survey.id() ] = survey; 
			if ( (survey.required() == '0') && (survey.usr_summary() == '0') ) { continue; }
			//mw.sdump('D_LEGACY','Survey: ' + survey.id() + ' : ' + survey.name() + '\n');
			var row = document.createElement('row');
			rows.appendChild(row);
			desc_1[ survey.id() ] = document.createElement('description');
				desc_1[ survey.id() ].setAttribute('value', 'Not Taken');
			row.appendChild(desc_1[ survey.id() ]);
			var desc_2 = document.createElement('label');
				desc_2.setAttribute('class','link');
				desc_2.setAttribute('onclick','survey_test(event,' + survey.id() + ');');
			row.appendChild(desc_2);
			desc_2.setAttribute('value', survey.name() );
			desc_3[ survey.id() ] = document.createElement('description');
			row.appendChild(desc_3[ survey.id() ]);

			if (survey.required() == '1') {
				row.setAttribute('hidden','false');
			} else {
				row.setAttribute('hidden','true');
			}
			//mw.sdump('D_LEGACY','creating desc_1: ' + desc_1 + '\n');
			var result2 = mw.user_async_request(
				'open-ils.circ',
				'open-ils.circ.survey.response.retrieve',
				[ mw.G.auth_ses[0], survey.id(), PATRON.au.id() ],
				function (request) {
					var result2 = request.getResultObject();
					mw.sdump('D_LEGACY','result2 = ' + js2JSON(result2) + '\n');
					if (result2.length > 0) {
						var last_response = result2.pop();
						//mw.sdump('D_LEGACY','desc_1 = ' + desc_1[ last_response.survey() ] + '\n');
						//mw.sdump('D_LEGACY','effective_date = [' + last_response.effective_date() + ']  answer_date = [' + last_response.answer_date() + ']\n');
						var date = last_response.effective_date().substr(0,10);
						if (!date) { date = last_response.answer_date().substr(0,10); }
						var first_answer = '';
						try {
							first_answer = find_id_object_in_list(
								find_id_object_in_list(
									survey_hash[ last_response.survey() ].questions(),
									last_response.question()
								).answers(),
								last_response.answer()
							).answer();
						} catch(E) {
							mw.sdump('D_LEGACY',js2JSON(E) + '\n');
						}
						desc_1[ last_response.survey() ].setAttribute('value', date);
						desc_3[ last_response.survey() ].setAttribute('value', first_answer);
						//mw.sdump('D_LEGACY','desc_1 = ' + date + '\n');
					}
				}
			);
		}
	} catch(E) {
		mw.sdump('D_LEGACY','populate_patron_edit_survey_grid ERROR: ' + js2JSON(E) + '\n');
		mw.handle_error(E);
	}
}

function toggle_patron_survey_grid_rows(e,grid) {
	var label = e.target.getAttribute('label');
	var alt_label = e.target.getAttribute('alt_label');
	e.target.setAttribute('label',alt_label);
	e.target.setAttribute('alt_label',label);
	toggle_hidden_grid_rows(grid);	
}

function retrieve_patron_by_barcode(barcode,method) {
	if (!barcode) { barcode = PATRON.barcode(); }
	mw.sdump('D_LEGACY','Entering PATRON.retrieve_patron() with barcode: ' + barcode + '\n');
	//unregister_patron_window(this);
	var result;
	if (!method) method = 'open-ils.actor.user.fleshed.retrieve_by_barcode';
	try {
		result = mw.user_request(
				'open-ils.actor',
				method,
				[ mw.G.auth_ses[0], barcode ]
			);
		if (typeof(result[0]) != 'object') {
			mw.sdump('D_LEGACY','unexpected result1 : ' + typeof(result[0]) + ' : ' + js2JSON(result) + '\n');
			throw('unexpected result1 : ' + typeof(result[0]) + ' : ' + js2JSON(result) + '\n');
		}
	} catch(E) {
		mw.sdump('D_LEGACY','error in search.actor.user.barcode\n' + js2JSON(E) + '\n');
		mw.handle_error(E);
		return false;
	}
	/*for (var i in result[0]) {
		var element = result[0][i];
		if (typeof(element) != 'function') {
			mw.sdump('D_LEGACY','Copying ' + i + ' to PATRON\n');
			PATRON[i] = element;
		}
	}*/
	PATRON.au = result[0];
	//register_patron_window(this);
	//PATRON.barcode = find_id_object_in_list(PATRON.au.cards(),PATRON.au.card()).barcode();
	patron_callback('retrieve_patron');
	return PATRON.related_refresh(PATRON.au.id());
}
PATRON.retrieve_patron_by_barcode = retrieve_patron_by_barcode;
PATRON.retrieve_patron = retrieve_patron_by_barcode;
PATRON.retrieve_via_method = retrieve_patron_by_barcode;
PATRON.refresh = retrieve_patron_by_barcode;

function get_barcode() {
	try {
		//mw.sdump('D_LEGACY','PATRON.au.array.length = ' + PATRON.au.array.length + '\n');
		//mw.sdump('D_LEGACY','get_barcode: PATRON.au = ' + js2JSON(PATRON.au) + '\n.cards() = ' + js2JSON(PATRON.au.cards()) + '\n.card() = ' + js2JSON(PATRON.au.card()) + '\n');
		//return find_id_object_in_list(PATRON.au.cards(),PATRON.au.card()).barcode();
		return PATRON.au.card().barcode();
	} catch(E) {
		mw.sdump('D_LEGACY','get_barcode() error == ' + js2JSON(E) + '\n');
		return '';
	}
}
PATRON.barcode = get_barcode;

function validate_patron() {
	//mw.sdump('D_LEGACY','validate_patron: PATRON.au = ' + js2JSON(PATRON.au) + '\nPATRON.au.array.length = ' + PATRON.au.array.length + '\n');
	var s = '';
	if ( PATRON.barcode() == 'REQUIRED') {
		if (!s) {
			var textbox = document.getElementById( 'patron_edit_system_barcode_textbox' );
			textbox.select(); textbox.focus();
		}
		s += ('Barcode required\n');
	}
	if ( ! PATRON.au.usrname() ) {
		if (!s) {
			var textbox = document.getElementById( 'patron_edit_system_usrname_textbox' );
			textbox.select(); textbox.focus();
		}
		s += ('Login Name required\n');
	}

	if ( ! PATRON.au.family_name() ) {
		if (!s) {
			var textbox = document.getElementById( 'patron_edit_system_family_name_textbox' );
			textbox.select(); textbox.focus();
		}
		s += ('Family Name required\n');
	}
	if ( ! PATRON.au.first_given_name() ) {
		if (!s) {
			var textbox = document.getElementById( 'patron_edit_system_first_given_name_textbox' );
			textbox.select(); textbox.focus();
		}
		s += ('First Given Name required\n');
	}
	if ( ! PATRON.au.ident_value() ) {
		if (!s) {
			var textbox = document.getElementById( 'patron_edit_system_id1value_textbox' );
			textbox.select(); textbox.focus();
		}
		s += ('Identification required\n');
	}
	if ( ! PATRON.au.dob() ) {
		if (!s) {
			var textbox = document.getElementById( 'patron_edit_system_dob_textbox' );
			textbox.select(); textbox.focus();
		}
		s += ('Date of Birth required\n');
	}
	if ( ! PATRON.au.mailing_address() ) {
		s += ('Mailing Address required\n');
	}
	if ( ! PATRON.au.billing_address() ) {
		s += ('Billing Address required\n');
	}
	if (s) {
		mw.sdump('D_LEGACY',s); alert(s); return false;
	}
	return true;
}

function backup_patron(P) {
	backup_au = P.au.clone();
}

function restore_patron(P) {
	P.au = backup_au.clone();
	//hash_ac[ P.au.card() ] = find_id_object_in_list( P.au.cards(), P.au.card() );
	hash_ac[ P.au.card().id() ] = P.au.card();
	hash_au[ P.au.id() ] = P.au;
}

function save_patron() {
	mw.sdump('D_LEGACY','Entering PATRON.save()\n\n=-=-=-=-=-=-=-=\n\n');
	mw.sdump('D_LEGACY','PATRON.au = ' + js2JSON(PATRON.au) + '\n');
	mw.sdump('D_LEGACY','PATRON.au.a.length = ' + PATRON.au.a.length + '\n\n');
	//var backup_json = js2JSON(PATRON.au);
	//mw.sdump('D_LEGACY','backup_json = ' + backup_json + '\n\n');
	backup_patron(PATRON);
	mw.sdump('D_LEGACY','\n\n=-=-=-=-=-=-=-=-=-=-\n\n');
	check_for_new_addresses();
	check_for_new_stat_cats();
	if (! validate_patron() ) { 
		mw.sdump('D_LEGACY','restoring backup\n');
		restore_patron(PATRON);
		return false; 
	}
	if (! PATRON.au.usrname() ) { 
		PATRON.au.usrname( 
			PATRON.barcode()
		);
	}
	PATRON.au.survey_responses( response_list );
	mw.sdump('D_LEGACY','before PATRON.au = ' + js2JSON(PATRON.au) + '\n');
	var result;
	try {
		result = mw.user_request(
				'open-ils.actor',
				'open-ils.actor.patron.update',
				[ mw.G.auth_ses[0], PATRON.au ]
			);
		if (typeof(result[0]) != 'object') {
			mw.sdump('D_LEGACY','unexpected result1 : ' + typeof(result[0]) + ' : ' + js2JSON(result) + '\n');
			throw('unexpected result1 : ' + typeof(result[0]) + ' : ' + js2JSON(result) + '\n');
		}
	} catch(E) {
		mw.sdump('D_LEGACY','error in \n' + js2JSON(E) + '\n');
		mw.sdump('D_LEGACY','restoring backup 2\n');
		restore_patron(PATRON);
		mw.handle_error(E);
		//mw.sdump('D_LEGACY','PATRON.au = ' + js2JSON(PATRON.au) + '\nPATRON.au.a.length = ' + PATRON.au.a.length + '\n');
		//PATRON.summary_refresh();
		return false;
	}
	PATRON.au = result[0];
	if (! PATRON.au) { 
		mw.sdump('D_LEGACY','Restoring backup\n'); 
		restore_patron(PATRON);
		mw.handle_error('Save Failed'); 
		return; 
	}
	hash_aua = {};
	response_list = [];
	mw.sdump('D_LEGACY','after  PATRON.au = ' + js2JSON(PATRON.au) + '\n');
	//PATRON.barcode = find_id_object_in_list(PATRON.au.cards(),PATRON.au.card()).barcode();
	PATRON.summary_refresh();
	patron_callback('save');
	var refresh_result = PATRON.related_refresh(PATRON.au.id());
	alert('Patron successfully updated.');
	return refresh_result;
}
PATRON.save = save_patron;

function check_for_new_addresses() {
	for (var id in hash_aua) {
		if ( (id < 0) && ( hash_aua[id].ischanged() ) ) {
			mw.sdump('D_LEGACY','Pushing new address\n');
			if (!PATRON.au.addresses()) { PATRON.au.addresses( [] ); }
			PATRON.au.addresses().push( hash_aua[id] );
		}
	}
}

function check_for_new_stat_cats() {
	var entries = new Array();
	var grid = document.getElementById('patron_edit_stat_cat_grid');
	var nl = grid.getElementsByTagName('menulist');
	for (var i = 0; i < nl.length; i++) {
		var menulist = nl[i];
		if (menulist.getAttribute('original') != menulist.value) {
			var n_actscecm = new actscecm();
			var id = menulist.getAttribute('entry_id')
			//alert('check_for_new_stat_cats: id = ' + id );
			if (id) {
				n_actscecm.ischanged('1');
				n_actscecm.id( id );
			} else {
				n_actscecm.isnew('1');
				n_actscecm.id( new_id-- );
			}
			n_actscecm.stat_cat( menulist.getAttribute('stat_cat_id') );
			n_actscecm.stat_cat_entry( menulist.value );
			n_actscecm.target_usr( PATRON.au.id() );
			entries.push( n_actscecm );
		}

	}
	//alert( 'entries = ' + js2JSON( entries ) );
	PATRON.au.stat_cat_entries( entries );
}

function retrieve_patron_related_info(id) {
	if (!id) { id = PATRON.au.id(); }
	mw.sdump('D_LEGACY','Entering PATRON.related_refresh() with id: ' + id + '\n');
	/*
	var checkouts = [];
	if (id > 0) {
		try {
			checkouts = mw.user_request(
				'open-ils.circ',
				'open-ils.circ.actor.user.checked_out',
				[ mw.G.auth_ses[0], id ]
			)[0];
		} catch(E) {
			mw.handle_error(E);
		}
	}
	PATRON.checkouts = checkouts;
	PATRON.nearest_due = '';
	for (var i in checkouts) {
		var checkout = checkouts[i];
		mw.sdump('D_LEGACY','checkout = ' + js2JSON(checkout) + '\n');
	}
	PATRON.holds = [];
	PATRON.bills = [];
	PATRON.summary_refresh();
	try {
		//circ_init_list();
	} catch(E) {
		mw.sdump('D_LEGACY',js2JSON(E) + '\n');
	}
	patron_callback('related_refresh');
	*/
	return true;
}
PATRON.related_refresh = retrieve_patron_related_info;

/* patron_scan_overlay functions */

function patron_callback(s,params) {
	try {
		switch(s) {
			case 'scan_submit' : return patron_scan_submit_callback(params); break;
			case 'related_refresh' : return patron_related_refresh_callback(params); break;
			case 'retrieve_patron' : return patron_retrieve_patron_callback(params); break;
			case 'save' : return patron_save_callback(params); break;
			default : return patron_default_callback(s,params); break;
		}
	} catch(E) {
		/* assume no callback defined */
		return true;
	}
}

function patron_advanced_button(ev) {
	var deck = document.getElementById('patron_scan_deck');
	if (deck) { deck.setAttribute('selectedIndex','2'); }
	focus_widget( 'patron_search_family_name_textbox' );
	deck = document.getElementById('circ_deck_deck');
	if (deck) { deck.setAttribute('selectedIndex','6'); }
	//PATRON.search = {};
}
PATRON.advanced_search = patron_advanced_button;

function patron_scan_submit(ev) {
	mw.sdump('D_LEGACY','Entering PATRON.scan_submit() with target: ' + ev.target + '\n');
	try {
		var rc = PATRON.retrieve_patron( document.getElementById('patron_scan_textbox').value );
		if (rc) {
			/* the PATRON object should already be updated.  Switch deck if there is one */
			var deck = document.getElementById('patron_scan_deck');
			if (deck) { deck.setAttribute('selectedIndex','1'); }
			patron_callback('scan_submit');
			/* enable the scan item widgets if there are some */
			enable_widgets(
				'circ_checkout_scan_search_button',
				'circ_checkout_scan_textbox',
				'circ_checkout_scan_submit_button'
			);
			focus_widget( 'circ_checkout_scan_textbox' );
		} else {
			throw('retrieve_patron return code == false');
		}
	} catch(E) {
		mw.sdump('D_LEGACY','Could not retrieve patron.  Invalid barcode?\n' + js2JSON(E) + '\n');
		alert('Could not retrieve patron.  Invalid barcode?\n' + js2JSON(E) + '\n');
	}
}
PATRON.scan_submit = patron_scan_submit;

function patron_scan_search(ev) {
	mw.sdump('D_LEGACY','Entering PATRON.scan_search() with target: ' + ev.target + '\n');
	//mw.sdump('D_LEGACY','PATRON.search = ' + pretty_print(js2JSON(PATRON.search)) + '\n');
	try {
		var result = mw.user_request(
			'open-ils.actor',
			'open-ils.actor.patron.search.advanced',
			[ mw.G.auth_ses[0], PATRON.search ]
		)[0];
		mw.sdump('D_LEGACY','result = ' + js2JSON(result) + '\n');
		PATRON['search_results'] = result;
		build_patron_search_result_deck();
	} catch(E) {
		mw.handle_error(E);
	}
}
PATRON.scan_search = patron_scan_search;

/* patron_summary_overlay functions */

function make_barcode_handler(card_id,user_id) {
	return function (ev) {
		magic_field_edit(ev,'ac',card_id,'barcode');
		PATRON.au.ischanged('1');
		magic_field_edit(ev,'au',user_id,'usrname');
		var usr_e = document.getElementById('patron_edit_system_usrname_textbox');
		if (usr_e) {
			usr_e.value = ev.target.value;
		}
		/*ev.target.removeEventListener(
			"change",
			this,
			false
		);*/
	}
}

function patron_summary_refresh(ev) {
	//alert( mw.arg_dump(arguments) );
	// This function needs to be broken up.. it sets the patron edit section as well
	if (!PATRON.au) { return; }
	mw.sdump('D_LEGACY','Entering PATRON.summary_refresh()\n');
	hash_au[PATRON.au.id()] = PATRON.au;
	//PATRON.barcode = find_id_object_in_list(PATRON.au.cards(),PATRON.au.card()).barcode();
	/* just redraw the display with the PATRON object as is */
	var barcode_e = document.getElementById('patron_edit_system_barcode_textbox');
	if (barcode_e) {
		//var barcode_v = find_id_object_in_list(PATRON.au.cards(),PATRON.au.card());
		var barcode_v = PATRON.au.card();
		if (barcode_v) {
			barcode_e.value = barcode_v.barcode();
			if (barcode_e.value != 'REQUIRED') {
				barcode_e.disabled = true;
			} else {
				barcode_e.addEventListener(
					"change",
					make_barcode_handler(barcode_v.id(),PATRON.au.id()),
					false
				);
			}
		}
	}
	var usrname_e = document.getElementById('patron_edit_system_usrname_textbox');
	if (usrname_e) {
		usrname_e.value = PATRON.au.usrname();
		usrname_e.setAttribute("onchange",
			"magic_field_edit(event,'au'," + PATRON.au.id() + ",'usrname');");
	}
	var passwd_e = document.getElementById('patron_edit_system_new_passwd_textbox');
	if (passwd_e) {
		passwd_e.setAttribute("onchange",
			"magic_field_edit(event,'au'," + PATRON.au.id() + ",'passwd');");
	}
	var name_e = document.getElementById('patron_status_caption');
	if (name_e) {
		var name = '';
		if (PATRON.au.prefix()) { name += PATRON.au.prefix() + ' '; }
		if (PATRON.au.family_name()) { name += PATRON.au.family_name() + ', '; }
		if (PATRON.au.first_given_name()) { name += PATRON.au.first_given_name() + ' '; }
		if (PATRON.au.second_given_name()) { name += PATRON.au.second_given_name() + ' '; }
		if (PATRON.au.suffix()) { name += PATRON.au.suffix(); }

		name_e.setAttribute('label',name);
	}
	name_e = document.getElementById('patron_edit_system_family_name_textbox');
	if (name_e) {
		if (PATRON.au.family_name()) { name_e.value = PATRON.au.family_name(); }
		name_e.setAttribute("onchange","magic_field_edit(event,'au'," + PATRON.au.id() + ",'family_name');");
	}
	name_e = document.getElementById('patron_edit_system_first_given_name_textbox');
	if (name_e) {
		if (PATRON.au.first_given_name()) { name_e.value = PATRON.au.first_given_name(); }
		name_e.setAttribute("onchange","magic_field_edit(event,'au'," + PATRON.au.id() + ",'first_given_name');");
	}
	name_e = document.getElementById('patron_edit_system_second_given_name_textbox');
	if (name_e) {
		if (PATRON.au.second_given_name()) { name_e.value = PATRON.au.second_given_name(); }
		name_e.setAttribute("onchange","magic_field_edit(event,'au'," + PATRON.au.id() + ",'second_given_name');");
	}
	name_e = document.getElementById('patron_edit_system_prefix_menulist');
	if (name_e) {
		if (PATRON.au.prefix()) { name_e.value = PATRON.au.prefix(); }
		name_e.setAttribute("oncommand","magic_field_edit(event,'au'," + PATRON.au.id() + ",'prefix');");
	}
	name_e = document.getElementById('patron_edit_system_suffix_menulist');
	if (name_e) {
		if (PATRON.au.suffix()) { name_e.value = PATRON.au.suffix(); }
		name_e.setAttribute("oncommand","magic_field_edit(event,'au'," + PATRON.au.id() + ",'suffix');");
	}
	var profile_e = document.getElementById('patron_status_data_profile');
	if (profile_e) {
		//profile_e.setAttribute('value',find_id_object_in_list(mw.G.ap_list, PATRON.au.profile() ).name() );
		profile_e.setAttribute('value',mw.G.ap_hash[ PATRON.au.profile() ].name() );
	}
	profile_e = document.getElementById('patron_edit_system_profile_menulist');
	if (profile_e) {
		//hash_ap[PATRON.au.profile().id()] = PATRON.au.profile();
		profile_e.setAttribute("oncommand","magic_field_edit(event,'au'," + PATRON.au.id() + ",'profile');");
		set_patron_edit_profile_menu();
	}
	var email_e = document.getElementById('patron_edit_contact_email_textbox');
	if (email_e) {
		email_e.value = PATRON.au.email();
		email_e.setAttribute("onchange","magic_field_edit(event,'au'," + PATRON.au.id() + ",'email');");
	}
	var dayphone_e = document.getElementById('patron_contact_dayphone_data');
	if (dayphone_e) {
		dayphone_e.setAttribute('value', PATRON.au.day_phone() );
	}
	dayphone_e = document.getElementById('patron_edit_contact_dayphone_textbox');
	if (dayphone_e) {
		dayphone_e.value = PATRON.au.day_phone();
		dayphone_e.setAttribute("onchange","magic_field_edit(event,'au'," + PATRON.au.id() + ",'day_phone');");
	}
	var eveningphone_e = document.getElementById('patron_contact_eveningphone_data');
	if (eveningphone_e) {
		eveningphone_e.setAttribute('value', PATRON.au.evening_phone() );
	}
	eveningphone_e = document.getElementById('patron_edit_contact_eveningphone_textbox');
	if (eveningphone_e) {
		eveningphone_e.value = PATRON.au.evening_phone();
		eveningphone_e.setAttribute("onchange","magic_field_edit(event,'au'," + PATRON.au.id() + ",'evening_phone');");
	}
	var otherphone_e = document.getElementById('patron_contact_otherphone_data');
	if (otherphone_e) {
		otherphone_e.setAttribute('value', PATRON.au.other_phone() );
	}
	otherphone_e = document.getElementById('patron_edit_contact_otherphone_textbox');
	if (otherphone_e) {
		otherphone_e.value = PATRON.au.other_phone();
		otherphone_e.setAttribute("onchange","magic_field_edit(event,'au'," + PATRON.au.id() + ",'other_phone');");
	}
	var standing_e = document.getElementById('patron_status_data_standing');
	if (standing_e) {
		/*var standing = find_id_object_in_list( 
				mw.G.cst_list,
				PATRON.au.standing() 
			);*/
		var standing = mw.G.cst_hash[ PATRON.au.standing() ];
		mw.sdump('D_LEGACY','standing = ' + js2JSON(standing) + '\n');
		standing_e.setAttribute( 'value', standing.value() );
		if (standing.value() == 'Good') {
			add_css_class(standing_e,'good');
		} else {
			remove_css_class(standing_e,'good');	
		}
	}
	var claims_returned_e = document.getElementById('patron_status_data_claims_returned');
	if (claims_returned_e) {
		claims_returned_e.setAttribute('value',PATRON.au.claims_returned_count());
	}
	var credit_e = document.getElementById('patron_status_data_credit');
	if (credit_e) {
		credit_e.setAttribute('value',PATRON.au.credit_forward_balance());
	}
	var homelib_e = document.getElementById('patron_status_data_homelib');
	if (homelib_e) {
		homelib_e.setAttribute('value', 
			find_ou(
				mw.G.org_tree,
				PATRON.au.home_ou()
			).name()
		);
	}
	homelib_e = document.getElementById('patron_edit_system_library_menulist');
	if (homelib_e) {
		homelib_e.setAttribute("oncommand","magic_field_edit(event,'au'," + PATRON.au.id() + ",'home_ou',false);");
		set_patron_edit_library_menu();
	}
	var fees_e = document.getElementById('patron_status_data_fees');
	if (fees_e) {
		fees_e.setAttribute('value',PATRON.bills.length);
	}
	var checkouts_e = document.getElementById('patron_status_data_checkouts');
	if (checkouts_e) {
		checkouts_e.setAttribute('value',PATRON.checkouts.length);
	}
	var holds_e = document.getElementById('patron_status_data_holds');
	if (holds_e) {
		holds_e.setAttribute('value',PATRON.holds.length);
	}
	var nearest_due_e = document.getElementById('patron_status_data_nearest_due');
	if (nearest_due_e) {
		nearest_due_e.setAttribute('value',PATRON.nearest_due);
	}
	var id1value_e = document.getElementById('patron_edit_system_id1value_textbox');
	if (id1value_e) {
		id1value_e.setAttribute('value',PATRON.au.ident_value());
		id1value_e.setAttribute("onchange","magic_field_edit(event,'au'," + PATRON.au.id() + ",'ident_value');");
	}
	var id2value_e = document.getElementById('patron_edit_system_id2value_textbox');
	if (id2value_e) {
		id2value_e.setAttribute('value',PATRON.au.ident_value2());
		id2value_e.setAttribute("onchange","magic_field_edit(event,'au'," + PATRON.au.id() + ",'ident_value2');");
	}
	var id1type_e = document.getElementById('patron_edit_system_id1type_menulist');
	if (id1type_e) {
		id1type_e.setAttribute("oncommand","magic_field_edit(event,'au'," + PATRON.au.id() + ",'ident_type');");
		set_patron_edit_ident_type_menu(); 
	}
	var id2type_e = document.getElementById('patron_edit_system_id2type_menulist');
	if (id2type_e) {
		id2type_e.setAttribute("oncommand","magic_field_edit(event,'au'," + PATRON.au.id() + ",'ident_type2');");
		set_patron_edit_ident_type_menu2();
	}
	var dob_e = document.getElementById('patron_edit_system_dob_textbox');
	if (dob_e) {
		dob_e.setAttribute('value',PATRON.au.dob());
		dob_e.setAttribute("onchange","magic_field_edit(event,'au'," + PATRON.au.id() + ",'dob',false);");
	}
	//populate_patron_survey_grid('patron_survey_grid');
	populate_patron_survey_grid('patron_edit_survey_grid');
	populate_patron_edit_surveys();

	var address_rows = document.getElementById('patron_contact_address_rows');
	if (address_rows) {
		empty_widget(address_rows);
		var addresses = PATRON.au.addresses();
		for (var i in addresses) { 
			if (typeof(addresses[i])=='object') {
				var address = addresses[i];
				if (
					(address.id() == PATRON.au.mailing_address()) ||
					(address.id() == PATRON.au.billing_address())
				) {
					//mw.sdump('D_LEGACY','address dump: ' + i + ' : ' + addresses[i] + '\n');
					rows_append_address( address_rows, address, false );
				}
			}
		}
	}
	address_rows = document.getElementById('patron_edit_address_rows');
	if (address_rows) {
		empty_widget(address_rows);
		var addresses = PATRON.au.addresses();
		for (var i in addresses) { 
			if (typeof(addresses[i])=='object') {
				//mw.sdump('D_LEGACY','address dump: ' + i + ' : ' + js2JSON(addresses[i]) + '\n');
				rows_append_address( address_rows, addresses[i], true );
			}
		}
		var blank = new aua();
		blank.id( new_id-- );
		blank.isnew("1");
		blank.usr( PATRON.au.id() );
		/*if ( addresses.length == 0 ) {*/
		if (hash_aua.length == 0) {
			blank.address_type( 'REQUIRED' );
			blank.ischanged( "1" );
			PATRON.au.mailing_address( blank.id() );
			PATRON.au.billing_address( blank.id() );
		} else {
			blank.address_type( 'NEW' );
		}
		blank.city( 'CITY' );
		blank.country( 'USA' );
		blank.county( 'COUNTY' );
		blank.post_code( 'ZIP' );
		blank.state( 'GA' );
		blank.street1( 'STREET1' );
		blank.street2( 'STREET2' );
		rows_append_address( address_rows, blank , true );
	}

	var alert_message_e = document.getElementById('patron_edit_system_alert_message_textbox');
	if (alert_message_e) {
		alert_message_e.setAttribute('value',PATRON.au.alert_message());
		alert_message_e.setAttribute("onchange","magic_field_edit(event,'au'," + PATRON.au.id() + ",'alert_message',false);");
	}
	var stat_cats_e = document.getElementById('patron_statcat_rows');
	if (stat_cats_e) {
		try {
			empty_widget( stat_cats_e );
			for (var i = 0; i < PATRON.au.stat_cat_entries().length; i++) {

				// fieldmapper
				var entry = PATRON.au.stat_cat_entries()[i];
				var stat_cat = mw.G.actsc_hash[ entry.stat_cat() ];

				// build XUL
				var row = document.createElement('row');
				stat_cats_e.appendChild(row);
				var sc_label = document.createElement('label');
				row.appendChild(sc_label);
				var sce_label = document.createElement('label');
				row.appendChild(sce_label);

				// set values
				sc_label.setAttribute('value', stat_cat.name() );
				sce_label.setAttribute('value', entry.stat_cat_entry() );
			}
		} catch(E) {
			mw.handle_error(E);
		}
	}
	stat_cats_e = document.getElementById('patron_edit_stat_cat_grid');
	if (stat_cats_e) {
		//alert('stat_cats_e');
		try {
			//alert('in try');
			for (var i = 0; i < PATRON.au.stat_cat_entries().length; i++) {
				var entry = PATRON.au.stat_cat_entries()[i];
				//alert('entry = ' + js2JSON(entry) );
				var stat_cat = entry.stat_cat();
				if (typeof stat_cat == 'object') stat_cat = stat_cat.id();
				var menulist = document.getElementById('menulist_stat_cat_' + stat_cat);
				if (menulist) {

					//alert('menulist');

					menulist.value = entry.stat_cat_entry();
					menulist.setAttribute( 'original', menulist.value );
					menulist.setAttribute( 'entry_id', entry.id() );
					//alert('summary_refresh: entry.id() = ' + entry.id() );

				}
			}
		} catch(E) {
			mw.handle_error(E);
		}
	}
	if (PATRON.au.alert_message()) {
		snd_bad(); snd_bad();
		s_alert(
			'PATRON ALERT MESSAGE\n\n\n\n' +
			PATRON.au.alert_message() +
			'\n\n\n\nTo remove this alert permanently, Edit the patron and erase the message in "Alert Message".\n\n'
		);
	}
}
PATRON.summary_refresh = patron_summary_refresh;

function rows_append_address( rows, address, edit ) {


	// patron_summary

	//mw.sdump('D_LEGACY','Entering rows_append_address()\n');
	if (typeof(rows) != 'object') {
		rows = document.getElementById(box);
	}
	if (typeof(rows) != 'object') {
		mw.sdump('D_LEGACY','rows_append_address: could not find ' + rows + '\n');
		alert('rows_append_address: could not find ' + rows + '\n');
		return false;
	}
	var row = document.createElement('row');
		//row.setAttribute('id','row_address_'+yesno(edit)+address.id());
		hash_aua[ address.id() ] = address;
	rows.appendChild(row);
	var groupbox = document.createElement('groupbox');
		if (edit) {
			groupbox.setAttribute('id','groupbox_address_'+address.id());
		} else {
			groupbox.setAttribute('id','groupbox_summary_address_'+address.id());
		}
		groupbox.setAttribute('flex','1');
	row.appendChild(groupbox);
	var caption = document.createElement('caption');
		var caption_string = address.address_type();
		if ( PATRON.au.mailing_address() == address.id() ) {
			caption_string = '(MAILING) ' + caption_string;
		}
		if ( PATRON.au.billing_address() == address.id() ) {
			caption_string = '(PHYSICAL) ' + caption_string;
		}
		caption.setAttribute( 'label',caption_string );
	groupbox.appendChild(caption);

	// patron_edit

	if (edit) {
		var hbox = document.createElement('hbox');
		groupbox.appendChild(hbox);
			var label = document.createElement('label');
				label.setAttribute('value','Type:');
			hbox.appendChild(label);
			var textbox = document.createElement('textbox');
			textbox.setAttribute('size','20');
			textbox.setAttribute("onchange","magic_field_edit(event,'aua'," + address.id() + ",'address_type');");
			hbox.appendChild(textbox);
				textbox.value = address.address_type();
			var label2 = document.createElement('label');
				label2.setAttribute('value','Physical:');
			hbox.appendChild(label2);
			var checkbox_billing = document.createElement('checkbox');
				checkbox_billing.setAttribute('group','billing');
				checkbox_billing.setAttribute('oncommand','radio_checkbox(event); PATRON.au.billing_address(' + address.id() + '); PATRON.au.ischanged("1");');
			hbox.appendChild(checkbox_billing);
			if ( PATRON.au.billing_address() == address.id() ) {
				checkbox_billing.checked = true;
			}
			var label3 = document.createElement('label');
				label3.setAttribute('value','Mailing:');
			hbox.appendChild(label3);
			var checkbox_mailing = document.createElement('checkbox');
				checkbox_mailing.setAttribute('group','mailing');
				checkbox_mailing.setAttribute('oncommand','radio_checkbox(event); PATRON.au.mailing_address(' + address.id() + '); PATRON.au.ischanged("1");');
			hbox.appendChild(checkbox_mailing);
			if ( PATRON.au.mailing_address() == address.id() ) {
				checkbox_mailing.checked = true;
			}
			var label4 = document.createElement('label');
				label4.setAttribute('value','Invalid:');
			hbox.appendChild(label4);
			var checkbox_invalid = document.createElement('checkbox');
				checkbox_invalid.setAttribute('oncommand','invalid_checkbox(event,' + address.id() + ');');
			hbox.appendChild(checkbox_invalid);
			mw.sdump('D_LEGACY','address ' + address.id() + ' valid = ' + address.valid() + '\n');
			if ( address.valid() == '1' ) {
				checkbox_invalid.checked = false;
			} else {
				checkbox_invalid.checked = true;
			}
			var label5 = document.createElement('spacer');
				label5.setAttribute('flex','1');
			hbox.appendChild(label5);
			if (address.id()>-1) {
				var label6 = document.createElement('button');
					label6.setAttribute('label','Delete');
					label6.setAttribute('alt_label','Un-Delete');
					label6.setAttribute('toggle','0');
					label6.setAttribute('oncommand','toggle_address(event,' + address.id() + ');');
				hbox.appendChild(label6);
			}
	}
	var street1;
		if (edit) {
			street1 = document.createElement('textbox');
			street1.setAttribute('size','40');
			street1.setAttribute("onchange","magic_field_edit(event,'aua'," + address.id() + ",'street1');");
		} else {
			street1 = document.createElement('label');
		}
		street1.setAttribute( 'value',address.street1() );
	groupbox.appendChild(street1);
	var street2;
		if (edit) {
			street2 = document.createElement('textbox');
			street2.setAttribute('size','40');
			street2.setAttribute("onchange","magic_field_edit(event,'aua'," + address.id() + ",'street2');");
		} else {
			street2 = document.createElement('label');
		}
		street2.setAttribute( 'value',address.street2() );
	groupbox.appendChild(street2);
	var hbox = document.createElement('hbox');
	groupbox.appendChild(hbox);
		var city;
			if (edit) {
				city = document.createElement('textbox');
				city.setAttribute('size','20');
				city.setAttribute("onchange","magic_field_edit(event,'aua'," + address.id() + ",'city');");
			} else {
				city = document.createElement('label');
			}
			city.setAttribute( 'value',address.city() );
		hbox.appendChild(city);
		var county;
			if (edit) {
				county = document.createElement('textbox');
				county.setAttribute('size','20');
				county.setAttribute("onchange","magic_field_edit(event,'aua'," + address.id() + ",'county');");
				county.setAttribute( 'value',address.county() );
			} else {
				county = document.createElement('label');
				county.setAttribute( 'value','(' + address.county() + '),');
			}
		hbox.appendChild(county);
		if (!address.county()) {
			if (!edit) {
				county.setAttribute( 'display', 'none' );
				city.setAttribute( 'value',address.city() + ',' );
			}
		}
		var state;
			if (edit) {
				state = document.createElement('textbox');
				state.setAttribute('size','2');
				state.setAttribute("onchange","magic_field_edit(event,'aua'," + address.id() + ",'state');");
			} else {
				state = document.createElement('label');
			}
			state.setAttribute( 'value',address.state() );
		hbox.appendChild(state);
		var country;
			if (edit) {
				country = document.createElement('textbox');
				country.setAttribute('size','3');
				country.setAttribute("onchange","magic_field_edit(event,'aua'," + address.id() + ",'country');");
				country.setAttribute( 'value',address.country() );
			} else {
				country = document.createElement('label');
				country.setAttribute( 'value','(' + address.country() + '),');
			}
		hbox.appendChild(country);
		var zip;
			if (edit) {
				zip = document.createElement('textbox');
				zip.setAttribute('size','10');
				zip.setAttribute("onchange","magic_field_edit(event,'aua'," + address.id() + ",'post_code');");
			} else {
				zip = document.createElement('label');
			}
			zip.setAttribute( 'value',address.post_code() );
		hbox.appendChild(zip);
}

function invalid_checkbox(e,id) {
	if (e.target.checked) {
		mw.sdump('D_LEGACY','Marking address ' + id + ' invalid\n');
		mw.sdump('D_LEGACY','\tbefore address: ' + js2JSON(hash_aua[id]) + '\n');
		hash_aua[id].valid( '0' );
		hash_aua[id].ischanged( '1' );
		mw.sdump('D_LEGACY','\tafter  address: ' + js2JSON(hash_aua[id]) + '\n');
	} else {
		mw.sdump('D_LEGACY','Marking address ' + id + ' valid\n');
		mw.sdump('D_LEGACY','\tbefore address: ' + js2JSON(hash_aua[id]) + '\n');
		hash_aua[id].valid( '1' );
		hash_aua[id].ischanged( '1' );
		mw.sdump('D_LEGACY','\tafter  address: ' + js2JSON(hash_aua[id]) + '\n');
	}
}

function toggle_address(e,id) {
	var groupbox = document.getElementById('groupbox_address_' + id);
	//var address = find_id_object_in_list( hash_aua, id );
	var address = hash_aua[id];
	var button = e.target;
	var label = button.getAttribute('label');
	var alt_label = button.getAttribute('alt_label');
	button.setAttribute('label',alt_label);
	button.setAttribute('alt_label',label);
	var toggle = button.getAttribute('toggle');
	if (toggle == '0') {
		button.setAttribute('toggle','1');
		mw.sdump('D_LEGACY','original node = ' + js2JSON(address) + '\n');
		add_css_class(groupbox,'deleted_address');
		address.isdeleted('1');
		mw.sdump('D_LEGACY','updated  node = ' + js2JSON(address) + '\n');
		mw.sdump('D_LEGACY','PATRON.au.mailing_address() = ' + PATRON.au.mailing_address() + ' address.id() = ' + address.id() + '\n');
		if (PATRON.au.mailing_address() == address.id() ) {
			find_available_address_for('mailing_address');
		}
		mw.sdump('D_LEGACY','PATRON.au.billing_address() = ' + PATRON.au.billing_address() + ' address.id() = ' + address.id() + '\n');
		if (PATRON.au.billing_address() == address.id() ) {
			find_available_address_for('billing_address');
		}
	} else {
		button.setAttribute('toggle','0');
		mw.sdump('D_LEGACY','original node = ' + js2JSON(address) + '\n');
		remove_css_class(groupbox,'deleted_address');
		address.isdeleted('0');
		mw.sdump('D_LEGACY','updated  node = ' + js2JSON(address) + '\n');
	}
	var nl = groupbox.getElementsByTagName('textbox');
		for (var i in nl) {
			if (typeof(nl[i])=='object') {
				var t = nl[i];
				t.disabled = ! t.disabled;
			}
		}
}

function find_available_address_for(which) {
	mw.sdump('D_LEGACY','entering find_avialable_address_for(' + which + ')\n');
	var addresses = PATRON.au.addresses();
	mw.sdump('D_LEGACY','considering existing addresses...\n');
	for (var i in addresses) {
		var address = addresses[i];
		mw.sdump('D_LEGACY','i = ' + i + ' addresses[i] = ' + js2JSON(address) + '\n');
		if ( address.isdeleted() == '1') { continue; }
		if ( (address.address_type() == 'NEW') && (address.id() < 0) ) {
			address.address_type('REQUIRED');
			address.ischanged( '1' );
		}
		mw.sdump('D_LEGACY','PATRON.au before = ' + js2JSON(PATRON.au) + '\n');
		var command = 'PATRON.au.' + which + "( '" + address.id() + "' );";
		mw.sdump('D_LEGACY', command + '\n' );
		eval( command );
		mw.sdump('D_LEGACY','PATRON.au after  = ' + js2JSON(PATRON.au) + '\n');
		return true;
	}
	mw.sdump('D_LEGACY','considering old and new addresses...\n');
	for (var i in hash_aua) {
		var address = hash_aua[i];
		mw.sdump('D_LEGACY','i = ' + i + ' addresses[i] = ' + js2JSON(address) + '\n');
		if ( address.isdeleted() == '1') { continue; }
		if ( (address.address_type() == 'NEW') && (address.id() < 0) ) {
			address.address_type('REQUIRED');
			address.ischanged( '1' );
		}
		mw.sdump('D_LEGACY','PATRON.au before = ' + js2JSON(PATRON.au) + '\n');
		var command = 'PATRON.au.' + which + "( '" + address.id() + "' );";
		mw.sdump('D_LEGACY', command + '\n' );
		eval( command );
		mw.sdump('D_LEGACY','PATRON.au after  = ' + js2JSON(PATRON.au) + '\n');
		return true;
	}
}

function survey_test(ev,survey_id) {

	document.getElementById('circ_deck_deck').setAttribute('selectedIndex','5');
	var vbox = document.getElementById('patron_survey_vbox');
	empty_widget( vbox ); 
	survey_render_with_results(
		vbox,
		survey_id,
		function (survey) {
			return PATRON.refresh();
		}
	);
}

function populate_patron_edit_surveys() {
	var vbox = document.getElementById('patron_edit_survey_vbox');
	if (!vbox) return;

	mw.sdump('D_LEGACY','populate_patron_edit_surveys()\n');

	empty_widget( vbox ); 

	var surveys = [];
	try {
		surveys = mw.user_request(
			'open-ils.circ',
			'open-ils.circ.survey.retrieve.required',
			[ mw.G.auth_ses[0] ]
		)[0];
	} catch(E) {
		mw.handle_error(E);
	}

	for (var i = 0; i < surveys.length; i++) {
		var survey = surveys[i];
		survey_render(
			vbox,
			survey.id(),
			populate_patron_edit_surveys_build_callback( survey ),
			null
		);
	}
}

function populate_patron_edit_surveys_build_callback( survey ) {
	return function (responses) {
		for (var i in responses) {
			response_list.push( responses[i] );
		}
		var nframe = document.getElementById('patron_survey_frame_'+survey.id());
		nframe.contentWindow.document.body.innerHTML = '<h1>' + survey.name() + ' Complete</h1>';
		return true;
	};
}


function survey_render(vbox,survey_id,commit_callback,submit_callback) {
	return; // remove me -- testing XULRUNNER
	if (typeof(vbox) != 'object') { vbox = document.getElementById(vbox); }
	var frame = document.createElement('iframe');
	vbox.appendChild(frame);
	frame.setAttribute('flex','1'); frame.setAttribute('src','about:blank');
	var doc = frame.contentWindow.document;
	HTMLdoc = doc;
	mw.sdump('D_LEGACY', 'before: ' + super_mw.sdump('D_LEGACY', doc ) + '\n');
	doc.write(
		'<body>' + 
		'<LINK href="http://spacely.georgialibraries.org/css/box.css" rel="stylesheet" type="text/css">' +
		'<LINK href="http://spacely.georgialibraries.org/css/survey.css" rel="stylesheet" type="text/css">' +
		'</body>'
	);
	doc.close();
	mw.sdump('D_LEGACY', 'after : ' + super_mw.sdump('D_LEGACY', doc ) + '\n');
	Survey.retrieveById( 
		mw.G.auth_ses[0] , 
		survey_id,
		function(sur) { 
			sur.setUser( PATRON.au.id() ); 
			if (submit_callback) sur.setSubmitCallback( submit_callback );
			if (commit_callback) sur.commitCallback = commit_callback;
			mw.sdump('D_LEGACY','survey id: ' + sur.survey.id() + '\n');
			doc.body.appendChild( sur.getNode() ); 
			frame.setAttribute('style','height: ' + (30+doc.height) + 'px;');
			frame.setAttribute('id','patron_survey_frame_' + sur.survey.id());
		} 
	);

}

function survey_render_with_results(vbox,survey_id,callback) {
	if (typeof(vbox) != 'object') { vbox = document.getElementById(vbox); }
	var frame = document.createElement('iframe');
	frame.setAttribute('id','patron_survey_frame'); vbox.appendChild(frame);
	frame.setAttribute('flex','1'); frame.setAttribute('src','about:blank');
	var doc = frame.contentWindow.document;
	HTMLdoc = doc;
	mw.sdump('D_LEGACY', 'before: ' + super_mw.sdump('D_LEGACY', doc ) + '\n');
	doc.write(
		'<body>' + 
		'<LINK href="http://spacely.georgialibraries.org/css/box.css" rel="stylesheet" type="text/css">' +
		'<LINK href="http://spacely.georgialibraries.org/css/survey.css" rel="stylesheet" type="text/css">' +
		'</body>'
	);
	doc.close();
	mw.sdump('D_LEGACY', 'after : ' + super_mw.sdump('D_LEGACY', doc ) + '\n');
	Survey.retrieveById( 
		mw.G.auth_ses[0] , 
		survey_id,
		function(sur) { 
			sur.setUser( PATRON.au.id() ); 
			sur.setSubmitCallback( callback );
			mw.sdump('D_LEGACY','survey id: ' + sur.survey.id() + '\n');
			doc.body.appendChild( sur.getNode() ); 
			var span = doc.createElement('blockquote');
			span.setAttribute('id','survey_response_' + sur.survey.id());
			span.setAttribute('class','survey');
			var warning = doc.createTextNode('Retrieving Responses...');
			span.appendChild(warning);
			doc.body.appendChild(span);
			mw.user_async_request(
				'open-ils.circ',
				'open-ils.circ.survey.response.retrieve',
				[ mw.G.auth_ses[0], sur.survey.id(), PATRON.au.id() ],
				function (request) {
					result = request.getResultObject().reverse();
					span.removeChild( warning );
					if (result.length == 0) { return; }
					//span.appendChild( doc.createTextNode('Previous Responses:') );
					//span.appendChild( doc.createElement('br') );
					//span.setAttribute('style','border: black solid thin;');
					var num_of_q = sur.survey.questions().length;
					var current_q = 0;
					span.appendChild( doc.createTextNode(
						'Previous Responses:'
					) );
					span.appendChild( doc.createElement('br') );
					span.appendChild( doc.createElement('br') );
					var block;
					for (var i = 0; i < result.length; i++) {
						if (++current_q > num_of_q) { current_q = 1; }
						mw.sdump('D_LEGACY','current_q = ' + current_q + '  num_of_q = ' + num_of_q + '\n');
						if (current_q == 1) {
							block = doc.createElement('blockquote');
							span.appendChild( doc.createTextNode(
								'Answer Date: ' + 
								result[i].answer_date() +
								', Effective Date: ' + 
								result[i].effective_date()
							) );
							span.appendChild( doc.createElement('br') );
							span.appendChild(block);
						}
						block.appendChild(
							doc.createTextNode(
								current_q + ') ' + 
								find_id_object_in_list(
									find_id_object_in_list(
										sur.survey.questions(),
										result[i].question()
									).answers(),
									result[i].answer()
								).answer() + ' '
							)
						);
					}
					span.appendChild( doc.createElement('br') );
					frame.setAttribute('style','height: ' + (30+doc.height) + 'px;');
				}
			);
		} 
	);
}

function createAppElement(name) {
	return HTMLdoc.createElement(name);
}

function createAppTextNode(value) {
	return HTMLdoc.createTextNode(value);
}


function handle_patron_search_textbox(ev,group) {
	var id = ev.target.getAttribute('id');
	var field = id.split(/_/).slice(2,-1).join('_');
	mw.sdump('D_LEGACY','field = ' + field + ' value = ' + ev.target.value + '\n');
	PATRON.search[field] = { 'value' : ev.target.value, 'group' : group };
}

function build_patron_search_result_deck() {
	var label = document.getElementById('patron_search_results_label');
	if (label) {
		var s = 'Found ' + PATRON.search_results.length + ' matches.  ';
		if (PATRON.search_results.length > patron_hits_per_page) {
			s += 'Displaying ' + patron_hits_per_page + ' per page:';
		}
		label.setAttribute('value',s);
	}
	var deck = document.getElementById('patron_search_results_deck');	
	if (!deck) return;

	empty_widget(deck);

	var patron_ids = PATRON.search_results.slice(0,patron_hits_per_page);
	PATRON.search_results = PATRON.search_results.slice(patron_hits_per_page);
	build_patron_search_result_page(deck,patron_ids,PATRON.search_results.length);
}

function build_patron_search_result_page(deck,patron_ids,remaining) {
	mw.sdump('D_LEGACY','build_patron_search_result_page()\n');
	if (typeof(deck)!='object') deck = document.getElementById(deck);
	if (!deck) return;

	if (patron_ids.length == 0) return;

	var vbox = document.createElement('vbox');
	deck.appendChild(vbox);
	vbox.setAttribute('flex','1');

	var idx = deck.childNodes.length - 1;
	deck.selectedIndex = idx;

	var button_box = document.createElement('hbox');
	vbox.appendChild(button_box);

	var back_button = document.createElement('button');
	button_box.appendChild(back_button);
	back_button.setAttribute('label','Previous');
	back_button.disabled = true;
	if (idx > 0) {
		back_button.disabled = false;
		back_button.setAttribute('oncommand',"var deck = document.getElementById('patron_search_results_deck'); deck.selectedIndex = deck.selectedIndex -1;");
	}
	var forward_button = document.createElement('button');
	button_box.appendChild(forward_button);
	forward_button.setAttribute('label','Next');
	forward_button.disabled = true;
	if (remaining > 0) {
		forward_button.disabled = false;
		forward_button.addEventListener(
			'command',
			function (ev) {
				var fired = ev.target.getAttribute('fired');

				if (fired) {
					deck.selectedIndex = idx + 1;
				} else {
					var next_ids = PATRON.search_results.slice(0,patron_hits_per_page);
					PATRON.search_results = PATRON.search_results.slice(patron_hits_per_page);
					build_patron_search_result_page(deck,next_ids,PATRON.search_results.length);
					ev.target.setAttribute('fired',true);
				}
			},
			false
		);
	}
	var tree = document.createElement('tree');
	vbox.appendChild(tree);
	tree.setAttribute('flex','1');
	tree.setAttribute('enableColumnDrag','true');
	tree.addEventListener(
		'select',
		function (ev) {
			var row = get_list_from_tree_selection(ev.target)[0];
			if (row) {
				var patron_id = row.getAttribute('patron_id');
				if (patron_id) {
					PATRON.retrieve_via_method( patron_id, 'open-ils.actor.user.fleshed.retrieve' );
					circ_init();
					set_decks( { 'patron_scan_deck' : '1' } );
					focus_widget( row.parentNode );
				}
			}
		},
		false
	);

	var t_columns = document.createElement('treecols');
	tree.appendChild(t_columns);

	for (var i = 0; i < patron_list_columns.length; i++) {
		var column = patron_list_columns[i];
		var t_column = document.createElement('treecol');
		t_columns.appendChild( t_column );
		t_column.setAttribute('label', column.v);
		if (column.s) {
			t_column.setAttribute('id', 'tc_' + column.s + '_' + column.f);
		} else {
			t_column.setAttribute('id', 'tc_' + column.f);
		}
		t_column.setAttribute('flex', '0');
		try {
			if (column.primary) {
				t_column.setAttribute('primary','true');
				t_column.setAttribute('flex','1');
			}
			if (column.hidden) t_column.setAttribute('hidden','true');
		} catch(E) {
			mw.sdump('D_LEGACY',js2JSON(E) + '\n');
		}
		t_column.setAttribute('field',column.f);
		if (i != (patron_list_columns.length - 1) ) {
			var t_splitter = document.createElement('splitter');
			t_columns.appendChild( t_splitter );
			t_splitter.setAttribute('class','tree-splitter');
		}
	}
	var t_children = document.createElement('treechildren');
	tree.appendChild(t_children);

	for (var i = 0; i < patron_ids.length; i++) {
		var t_item = document.createElement('treeitem');
		t_children.appendChild( t_item );
		t_item.setAttribute('patron_id',patron_ids[i]);

		var t_row = document.createElement('treerow');
		t_item.appendChild( t_row );
		t_row.setAttribute('patron_id',patron_ids[i]);

		//var t_cell = document.createElement('treecell');
		//t_row.appendChild( t_cell );
		//t_cell.setAttribute('label',patron_ids[i]);

		mw.user_async_request(
			'open-ils.actor',
			'open-ils.actor.user.fleshed.retrieve',	
			[ mw.G.auth_ses[0], patron_ids[i] ],
			build_patron_retrieve_for_search_callback( t_row )
		);
		mw.sdump('D_LEGACY','Making call... count = ' + counter_incr('patron_call') + '\n');
	}
	
}

function build_patron_retrieve_for_search_callback(treerow) {
	return function (request) {
		mw.sdump('D_LEGACY','Running callback... count = ' + counter_incr('patron_callback') + '\n');
		var result = request.getResultObject();
		mw.sdump('D_LEGACY','Result = ' + js2JSON(result) + '\n');

		for (var i = 0; i < patron_list_columns.length; i++) {
			var column = patron_list_columns[i];
			var t_cell = document.createElement('treecell');
			treerow.appendChild(t_cell);
			var expression;
			if (column.s) {
				switch(column.s) {
					case 'home_ou':
expression = 'mw.G.org_tree_hash[ result.home_ou() ].' + column.f + '()';
					break;
					case 'mailing_address':
expression = 'find_id_object_in_list( result.addresses() , result.mailing_address() ).' + column.f + '()';
					break;
					case 'billing_address':
expression = 'find_id_object_in_list( result.addresses() , result.billing_address() ).' + column.f + '()';
					break;
				}
			} else {
				expression = 'result.' + column.f + '()';
			}
			//mw.sdump('D_LEGACY','Trying to eval: ' + expression + '\n');
			t_cell.setAttribute(
				'label',
				eval( expression )
			);
		}
	};
}


