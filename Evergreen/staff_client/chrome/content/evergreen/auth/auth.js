// the master Global variable
var G = { 
/////////////////////////////////////////////////////////////////////////////////////

	// pointer to the auth window
	'main_window' : self, 	

	// list of open window references, used for debugging in shell
	'win_list' : [],	

	// list of Top Level menu interface window references
	'appshell_list' : [],	

	// list of documents for debugging.  BROKEN
	'doc_list' : [],	

	// Windows need unique names.  This number helps.
	'window_name_increment' : 0, 

	// This number gets put into the title bar for Top Level menu interface windows
	'appshell_name_increment' : 0,

	// I was using this to make sure I could shove references into new windows
	// correctly.  However, it's JSON that tends to behave weirdly when crossing
	// window boundaries.  [ 'a', 'b', 'c' ] could turn into { '1' : 'a', '2' : 'b',
	'main_test_variable' : 'Hello World',

/////////////////////////////////////////////////////////////////////////////////////

	// Flag for whether the staff client should act as if it were offline or not
	'offline' : false,

	// Array of Session Keys.  This is an array mostly by accident, we usually
	// only deal with one session.  But this could be useful for implementing
	// overrides with other logins.
	'auth_ses' : [],

	// Org Unit for the login user
	'user_ou' : '',

	// The related org units for the login user
	'my_orgs' : [], 'my_orgs_hash' : {},

/////////////////////////////////////////////////////////////////////////////////////

	// The Org Unit tree
	'org_tree' : '', 'org_tree_hash' : {},

/////////////////////////////////////////////////////////////////////////////////////

	// Historically, was the list of actor::profile's, but now it's user groups.
	'ap_list' : [], 'ap_hash' : {},

	// config::identification_type
	'cit_list' : [], 'cit_hash' : {},

	// config::standing
	'cst_list' : [], 'cst_hash' : {},

	// assett::copy_location, and for my_orgs
	'acpl_list' : [], 'acpl_hash' : {},
	'acpl_my_orgs' : [], 'acpl_my_orgs_hash' : {},

	// actor::org_unit_type
	'aout_list' : [], 'aout_hash' : {},

	// config::copy_status
	'ccs_list' : [], 'ccs_hash' : {},

	// asset::stat_cat.   WHERE IS THIS POPULATED AGAIN?
	'asc_list' : [],

	// actor::stat_cat
	'actsc_list' : [], 'actsc_hash' : {},

/////////////////////////////////////////////////////////////////////////////////////

	'itemsout_header' : 'Welcome %PATRON_FIRSTNAME%, to %LIBRARY%!\r\nYou have the following items:<hr/><ol>',
	'itemsout_line_item' : '<li>%TITLE: 50%\r\nBarcode: %COPY_BARCODE% Due: %DUE_D%\r\n',
	'itemsout_footer' : '</ol><hr />%PINES_CODE% %TODAY%\r\nYou were helped by %STAFF_FIRSTNAME% %STAFF_LASTNAME%',

	'checkout_header' : 'Welcome %PATRON_FIRSTNAME%, to %LIBRARY%!\r\nYou checked out the following items:<hr/><ol>',
	'checkout_line_item' : '<li>%TITLE%\r\nBarcode: %COPY_BARCODE% Due: %DUE_D%\r\n',
	'checkout_footer' : '</ol><hr />%PINES_CODE% %TODAY%\r\nYou were helped by %STAFF_FIRSTNAME% %STAFF_LASTNAME%'

/////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////
};

var debug_ignore_auth_failures = false;

var mw = G['main_window'];
var auth_meter_incr = 10;

/////////////////////////////////////////////////////////////////////////////////////

function auth_init() {
	sdump('D_AUTH','TESTING: auth.js: ' + mw.G['main_test_variable'] + '\n');
	sdump('D_AUTH',arg_dump(arguments));

	var np = document.getElementById('name_prompt');
		np.addEventListener("keypress",handle_keypress,false);
		np.focus();
	var pp = document.getElementById('password_prompt');
		pp.addEventListener("keypress",handle_keypress,false);
	self.addEventListener("unload",nice_shutdown,false);

	G['sound'] = xp_sound_init(); snd_logon();
}

function handle_keypress(ev) {
	if (ev.keyCode && ev.keyCode == 13) {
		switch(this) {
			case document.getElementById('name_prompt') :
				ev.preventDefault();
				var pp = document.getElementById('password_prompt');
				pp.focus(); pp.select();
			break;
			case document.getElementById('password_prompt') :
				ev.preventDefault();
				var sb = document.getElementById('submit_button');
				sb.focus();
				authenticate();
			break;
			default:
			break;
		}
	}
}

function disable_login_prompts() {
	sdump('D_AUTH',arg_dump(arguments));
	disable_widgets(document,'password_prompt','name_prompt','submit_button');
	G.sound.beep();
}

function enable_login_prompts() {
	sdump('D_AUTH',arg_dump(arguments));
	enable_widgets(document,'password_prompt','name_prompt','submit_button');
	document.getElementById('password_prompt').value = '';
	var np = document.getElementById('name_prompt');
		np.focus(); np.select();
	document.getElementById('auth_meter').value = 0;
	document.getElementById('auth_meter').setAttribute('real', '0.0');
	G.sound.beep();
}

/////////////////////////////////////////////////////////////////////////////////////

function authenticate() {
	sdump('D_AUTH',arg_dump(arguments));
	timer_init('cat');
	var name = document.getElementById('name_prompt').value;
	if (name.length == 0) { enable_login_prompts(); return; }
	// Talk to the system and authenticate the user.
	user_async_request(
		'open-ils.auth',
		'open-ils.auth.authenticate.init',
		[ name ],
		auth_init_callback
	);
}

function auth_init_callback(request) {
	sdump('D_AUTH',arg_dump(arguments));
	var auth_init;
	try {
		auth_init = request.getResultObject();
		if (!auth_init) { throw('null result'); }
	} catch(E) {
		G.offline = true;
		sdump('D_ERROR','Error trying to communicate with the server.  Entering OFFLINE mode.\n' + js2JSON(E) + '\n');
		s_alert('Error trying to communicate with the server.  Entering OFFLINE mode.\n' + js2JSON(E) + '\n');
	}

	sdump( 'D_AUTH', 'D_AUTH_INIT: ' + typeof(auth_init) + ' : ' + auth_init + '\n');
	var name = document.getElementById('name_prompt').value;
	var pw = document.getElementById('password_prompt').value;
	G.name = name; G.pw = pw;

	/////////////////////////////////////////////////////////////////////////////////////////////////////
	user_async_request(
		'open-ils.auth',
		'open-ils.auth.authenticate.complete',
		[ name, hex_md5(auth_init + hex_md5(pw)) ],
		auth_ses_callback
	);
	incr_progressmeter(document,'auth_meter',auth_meter_incr);
}

function auth_ses_callback(request) {
	sdump('D_AUTH',arg_dump(arguments));
	var auth_ses;
	try {
		auth_ses = request.getResultObject();
		if (!auth_ses) { if (!G.offline) { throw('null result'); } }
		if (auth_ses == 0) { throw('0 result'); }
		if (instanceOf(auth_ses,ex)) {
			throw(auth_ses.err_msg());
		}
	} catch(E) {
		alert('Login failed on auth_ses: ' + js2JSON(E)); 
		if (!debug_ignore_auth_failures) {
			enable_login_prompts(); return;
		}
	}
	mw.G.auth_ses = [ auth_ses ];
	sdump( 'D_AUTH', 'D_AUTH_SES: ' + typeof(mw.G['auth_ses'][0]) + ' : ' + mw.G['auth_ses'][0] + '\n');

	/////////////////////////////////////////////////////////////////////////////////////////////////////
	//'open-ils.actor.user.profiles.retrieve',
	user_async_request(
		'open-ils.actor',
		'open-ils.actor.groups.retrieve',
		[],
		ap_list_callback
	);
	incr_progressmeter(document,'auth_meter',auth_meter_incr);
}

function ap_list_callback(request) {
	sdump('D_AUTH',arg_dump(arguments));
	var ap_file = get_file('ap_list');
	var ap_list;
	try {
		ap_list = request.getResultObject();
		if (!ap_list && G.offline) { 
			ap_list = get_object_in_file('ap_list');
		}
		if (!ap_list) { throw('null result'); }
		if (ap_list.length == 0) { throw('zero length result'); }
	} catch(E) {
		handle_error('Login failed on ap_list: ' + js2JSON(E)); 
		if (!debug_ignore_auth_failures) {
			enable_login_prompts(); return;
		}
	}
	try { set_object_in_file('ap_list',ap_list); } catch(E) { handle_error(E); }
	mw.G.ap_list = ap_list;
	mw.G.ap_hash = convert_object_list_to_hash( ap_list );

	/////////////////////////////////////////////////////////////////////////////////////////////////////
	user_async_request(
		'open-ils.actor',
		'open-ils.actor.user.ident_types.retrieve',
		[],
		cit_list_callback
	);
	incr_progressmeter(document,'auth_meter',auth_meter_incr);
}

function cit_list_callback(request) {
	sdump('D_AUTH',arg_dump(arguments));
	var cit_list;
	try {
		cit_list = request.getResultObject();
		if (!cit_list && G.offline) { cit_list = get_object_in_file('cit_list'); }
		if (!cit_list) { throw('null result'); }
		if (cit_list.length == 0) { throw('zero length result'); }
	} catch(E) {
		alert('Login failed on cit_list: ' + js2JSON(E)); 
		if (!debug_ignore_auth_failures) {
			enable_login_prompts(); return;
		}
	}
	try { set_object_in_file('cit_list',cit_list); } catch(E) { handle_error(E); }
	mw.G.cit_list = cit_list;
	mw.G.cit_hash = convert_object_list_to_hash( cit_list );
	
	/////////////////////////////////////////////////////////////////////////////////////////////////////
	user_async_request(
		'open-ils.actor',
		'open-ils.actor.standings.retrieve',
		[],
		cst_list_callback
	);

	incr_progressmeter(document,'auth_meter',auth_meter_incr);
}

function cst_list_callback(request) {
	sdump('D_AUTH',arg_dump(arguments));
	var cst_list;
	try {
		cst_list = request.getResultObject();
		if (!cst_list && G.offline) { cst_list = get_object_in_file('cst_list'); }
		if (!cst_list) { throw('null result'); }
		if (cst_list.length == 0) { throw('zero length result'); }
	} catch(E) {
		alert('Login failed on cst_list: ' + js2JSON(E)); 
		if (!debug_ignore_auth_failures) {
			enable_login_prompts(); return;
		}
	}
	try { set_object_in_file('cst_list',cst_list); } catch(E) { handle_error(E); }
	mw.G.cst_list = cst_list;
	mw.G.cst_hash = convert_object_list_to_hash( cst_list );
	sdump('D_AUTH', 'cst_list = ' + js2JSON(cst_list) + '\n');

	/////////////////////////////////////////////////////////////////////////////////////////////////////
	user_async_request(
		'open-ils.search',
		'open-ils.search.config.copy_location.retrieve.all',
		[],
		acpl_list_callback
	);
	incr_progressmeter(document,'auth_meter',auth_meter_incr);

}

function acpl_list_callback(request) {
	sdump('D_AUTH',arg_dump(arguments));
	var acpl_list;
	try {
		acpl_list = request.getResultObject();
		if (!acpl_list && G.offline) { acpl_list = get_object_in_file('acpl_list'); }
		if (!acpl_list) { throw('null result'); }
		if (acpl_list.length == 0) { throw('zero length result'); }
	} catch(E) {
		alert('Login failed on acpl_list: ' + js2JSON(E)); 
		if (!debug_ignore_auth_failures) {
			enable_login_prompts(); return;
		}
	}
	try { set_object_in_file('acpl_list',acpl_list); } catch(E) { handle_error(E); }
	mw.G.acpl_list = acpl_list;
	mw.G.acpl_hash = convert_object_list_to_hash( acpl_list );
	sdump('D_AUTH', 'acpl_list = ' + js2JSON(acpl_list) + '\n');

	/////////////////////////////////////////////////////////////////////////////////////////////////////
	user_async_request(
		'open-ils.search',
		'open-ils.search.config.copy_status.retrieve.all',
		[],
		ccs_list_callback
	);
	incr_progressmeter(document,'auth_meter',auth_meter_incr);
}

function ccs_list_callback(request) {
	sdump('D_AUTH',arg_dump(arguments));
	var ccs_list;
	try {
		ccs_list = request.getResultObject();
		if (!ccs_list && G.offline) { ccs_list = get_object_in_file('ccs_list'); }
		if (!ccs_list) { throw('null result'); }
		if (ccs_list.length == 0) { throw('zero length result'); }
	} catch(E) {
		alert('Login failed on ccs_list: ' + js2JSON(E)); 
		if (!debug_ignore_auth_failures) {
			enable_login_prompts(); return;
		}
	}
	try { set_object_in_file('ccs_list',ccs_list); } catch(E) { handle_error(E); }
	mw.G.ccs_list = ccs_list;
	mw.G.ccs_hash = convert_object_list_to_hash( ccs_list );
	sdump('D_AUTH', 'ccs_list = ' + js2JSON(ccs_list) + '\n');

	/////////////////////////////////////////////////////////////////////////////////////////////////////
	user_async_request(
		'open-ils.search',
		'open-ils.search.actor.user.session',
		[ mw.G['auth_ses'][0] ],
		user_callback
	);
	incr_progressmeter(document,'auth_meter',auth_meter_incr);
}

function user_callback(request) {
	sdump('D_AUTH',arg_dump(arguments));
	var user;
	var user_ou;
	try {
		user = request.getResultObject();
		if (!user && G.offline) { 
			user = new au(); 
			user.home_ou( get_object_in_file('user_ou') );
		}
		if (!user) { throw('null result'); }
		if (typeof(user) != 'object') { throw('result not an object' + user); }
	} catch(E) {
		alert('Login failed on user: ' + js2JSON(E)); 
		if (!debug_ignore_auth_failures) {
			enable_login_prompts(); return;
		}
	}
	try { set_object_in_file('user_ou',user.home_ou()); } catch(E) { handle_error(E); }
	mw.G.user = user;
	mw.G.user_ou = user.home_ou();
	sdump('D_AUTH', "user: " + js2JSON(mw.G['user']) + '\n');
	sdump('D_AUTH', "user_ou: " + js2JSON(mw.G['user_ou']) + '\n');

	/////////////////////////////////////////////////////////////////////////////////////////////////////
	user_async_request(
		'open-ils.actor',
		'open-ils.actor.org_tree.retrieve',
		[],
		org_tree_callback
	);
	incr_progressmeter(document,'auth_meter',auth_meter_incr);
}

function org_tree_callback(request) {
	var org_tree;
	try {
		org_tree = request.getResultObject();
		if (!org_tree && G.offline) { org_tree = get_object_in_file('org_tree'); }
		if (!org_tree) { throw('null result'); }
		if (typeof(org_tree) != 'object') { throw('result not an object' + org_tree); }
	} catch(E) {
		alert('Login failed on org_tree: ' + js2JSON(E)); enable_login_prompts(); return;
	}

	//mw.G.org_tree = globalOrgTree;
	try { set_object_in_file('org_tree',org_tree); } catch(E) { handle_error(E); }
	mw.G.org_tree = org_tree;
	mw.G.org_tree_hash = convert_object_list_to_hash( flatten_ou_branch( mw.G.org_tree ) );
	mw.G.user_ou = find_ou( mw.G.org_tree, mw.G.user_ou );

	/////////////////////////////////////////////////////////////////////////////////////////////////////
	/*user_async_request(
		'open-ils.actor',
		'open-ils.actor.org_types.retrieve',
		[ mw.G.auth_ses[0] ],
		org_type_callback
	);*/
	org_type_callback();
}

function org_type_callback(request) {
	sdump('D_AUTH',arg_dump(arguments));
	var aout_list = globalOrgTypes;
	/*try {
		aout_list = request.getResultObject();
		if (!aout_list) { throw('null result'); }
		if (typeof(aout_list) != 'object') { throw('result not an object' + aout_list); }
		if (aout_list.length == 0) { throw('empty aout_list'); }
	} catch(E) {
		alert('Login failed on aout_list: ' + js2JSON(E)); enable_login_prompts(); return;
	}*/
	mw.G.aout_list = aout_list;
	mw.G.aout_hash = convert_object_list_to_hash( aout_list );

	/////////////////////////////////////////////////////////////////////////////////////////////////////
	user_async_request(
		'open-ils.actor',
		'open-ils.actor.org_unit.full_path.retrieve',
		[ mw.G.auth_ses[0] ],
		my_orgs_callback
	);
	incr_progressmeter(document,'auth_meter',auth_meter_incr);
}

function my_orgs_callback(request) {
	sdump('D_AUTH',arg_dump(arguments));
	var my_orgs;
	try {
		my_orgs = request.getResultObject();
		if (!my_orgs && G.offline) { my_orgs = get_object_in_file('my_orgs'); }
		if (!my_orgs) { throw('null result'); }
		if (typeof(my_orgs) != 'object') { throw('result not an object' + my_orgs); }
		if (my_orgs.length == 0) { throw('empty my_orgs'); }
	} catch(E) {
		alert('Login failed on my_orgs: ' + js2JSON(E)); 
		if (!debug_ignore_auth_failures) {
			enable_login_prompts(); return;
		}
	}

	try { set_object_in_file('my_orgs',my_orgs); } catch(E) { handle_error(E); }
	mw.G.my_orgs = my_orgs;
	mw.G.my_orgs_hash = convert_object_list_to_hash( my_orgs );
	sdump('D_AUTH','my_orgs = ' + js2JSON(my_orgs) + '\n');
	mw.G.acpl_my_orgs = filter_list( 
		mw.G.acpl_list, 
		function (obj) {
			if ( typeof obj != 'object' ) return null;
			if ( mw.G.my_orgs_hash[ obj.owning_lib() ] ) return obj;
		}
	);
	mw.G.acpl_my_orgs_hash = convert_object_list_to_hash( mw.G.acpl_my_orgs );
	//sdump('D_AUTH', 'my_orgs.length = ' + mw.G.my_orgs.length + '   other_orgs.length = ' + mw.G.other_orgs.length + '\n');

	/////////////////////////////////////////////////////////////////////////////////////////////////////
	user_async_request(
		'open-ils.circ',
		'open-ils.circ.stat_cat.actor.retrieve.all',
		[ mw.G.auth_ses[0], mw.G.user_ou.id() ],
		my_actsc_list_callback
	);

	incr_progressmeter(document,'auth_meter',auth_meter_incr);
}

function my_actsc_list_callback(request) {
	sdump('D_AUTH',arg_dump(arguments));
	var actsc_list;
	try {
		actsc_list = request.getResultObject();
		if (!actsc_list && G.offline) { actsc_list = get_object_in_file('actsc_list'); }
		if (!actsc_list) { throw('null result'); }
		//if (actsc_list.length == 0) { throw('zero length result'); }
	} catch(E) {
		alert('Login failed on actsc_list: ' + js2JSON(E)); 
		if (!debug_ignore_auth_failures) {
			enable_login_prompts(); return;
		}
	}
	try { set_object_in_file('actsc_list',actsc_list); } catch(E) { handle_error(E); }
	mw.G.actsc_list = actsc_list;
	mw.G.actsc_hash = convert_object_list_to_hash( actsc_list );
	sdump('D_AUTH', 'actsc_list = ' + js2JSON(actsc_list) + '\n');

	incr_progressmeter(document,'auth_meter',auth_meter_incr);

	spawn_main();

	mw.minimize();

}


function logoff() {
	sdump('D_AUTH',arg_dump(arguments));
	mw.G['auth_ses'] = '';
	close_all_windows();
	enable_login_prompts();
	incr_progressmeter(document,'auth_meter',-100);
	snd_logoff();
}

function nice_shutdown() {
	sdump('D_AUTH',arg_dump(arguments));
	if (ses) { logoff(); ses.disconnect(); }
	snd_exit;
	close_all_windows();
	window.close();
}

