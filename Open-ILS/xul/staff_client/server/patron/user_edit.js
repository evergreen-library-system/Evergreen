var cgi;
var orgTree;
var user;
var ses_id;
var user_groups = [];
var adv_items = [];
var user_perms = [];
var perm_list = [];


var required_user_parts = {
	usrname:'User Name',
	first_given_name:'First Name',
	family_name:'Last Name',
	dob:'Date of Birth',
	ident_type:'Primary Identification Type',
	ident_value:'Primary Identification',
	day_phone:'Daytime Phone',
	home_ou:'Home Library',
	profile:'Profile Group',
	standing:'Standing',
};

var required_addr_parts = {
	street1:'Street 1',
	city:'City',
	state:'State',
	post_code:'ZIP',
	country:'Country',
	address_type:'Address Label',
};

function set_perm(row) {
	var pid = findNodeByName(row,'p.code').getAttribute('permid');
	var papply = findNodeByName(row,'p.id').checked;
	var pdepth = findNodeByName(row,'p.depth').options[findNodeByName(row,'p.depth').selectedIndex].value;
	var pgrant = findNodeByName(row,'p.grantable').checked;

	var p;
	for (var i in user_perms) {
		if (user_perms[i].perm() == pid) {
			p = user_perms[i];
			if (papply) {
				p.isdeleted(0);
				p.ischanged(1);
				p.depth(pdepth);
				p.grantable(pgrant ? 1 : 0);
			} else {
				if (p.isnew()) {
					user_perms[i] = null;
				} else {
					p.isdeleted(1);
				}
			}
			break;
		}
	}

	if (!p) {
		if (papply) {
			p = new pupm();
			p.isnew(1);
			p.perm(pid);
			p.usr(user.id());
			p.depth('' + pdepth);
			p.grantable(pgrant ? 1 : 0);

			user_perms.push(p);
		}
	}

}

function reset_crc () {
	document.forms.editor.elements["user.claims_returned_count"].value = '0';
	user.claims_returned_count(0);
}

function clear_alert_message () {
	document.forms.editor.elements["user.alert_message"].value = ' ';
	user.alert_message('');
}

function save_user () {
	user.ischanged(1);

	//alert(	js2JSON(user.stat_cat_entries()) );
	//return false;

	try {

		for (var i in user_perms) {
			if (!user_perms[i].depth()) {
				var p;
				for (var j in perm_list) {
					if (perm_list[j].id() == user_perms[i].perm()) {
						p = perm_list[j];
						break;
					}
				}
				throw "Depth is required on the " + p.code() + " permission.";
			}
		}

		user.permissions(user_perms);

		for (var i in required_user_parts) {
			if (!user[i]()) {
				throw required_user_parts[i] + " is required.";
			}
		}

		for (var j in user.addresses()) {
			if (user.addresses()[j].isdeleted()) continue;

			for (var i in required_addr_parts) {
				if (!user.addresses()[j][i]()) {
					throw required_addr_parts[i] + " is required.";
				}
			}
		}

                var res = [];
                for (var i in responses) {
                        if (!i) continue;
                        for (var j in responses[i]) {
                                if (!j) continue;
                                var r = new asvr();
                                r.usr(survey_user);
                                r.survey(i);
                                r.question(j);
                                r.answer(responses[i][j]);
                                r.answer_date( document.getElementById('e_date_'+i).value );
                                res.push(r);
                        }
                }

		user.survey_responses( res );
                responses = {};


		if (user.billing_address().isdeleted()) 
			throw "Please select a valid Billing Address";

		if (user.mailing_address().isdeleted()) 
			throw "Please select a valid Mailing Address";

		var req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.patron.update', ses_id, user );
		req.send(true);
		var ok = req.getResultObject();

		req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.user.set_groups', ses_id, ok.id(), user_groups );
		req.send(true);
		req.getResultObject();

		if (ok) {
			alert(	'User ' + ok.usrname() +
				' [' + ok.card().barcode() + '] ' +
				' successfully saved!');
		}

		init_editor(ok);

	} catch (e) {
		dump( js2JSON( e ));
		alert( js2JSON( e ));
	};



	return false;
}

var _fake_id = 0;
function fakeid () {
	return --_fake_id;
};

var adv_mode = false;
function apply_adv_mode (root) {
	adv_items = findNodesByClass(root,'advanced');
	for (var i in adv_items) {
		adv_mode ?
			removeCSSClass(adv_items[i], 'hideme') :
			addCSSClass(adv_items[i], 'hideme');
	}
}

function init_editor (u) {
	
	var x = document.getElementById('editor').elements;

	
	cgi = new CGI();
	if (cgi.param('adv')) adv_mode = true;
	apply_adv_mode(document.getElementById('editor'));

	if (!u) {
		ses_id = cgi.param('ses');

		var usr_id = cgi.param('usr');
		var usr_barcode = cgi.param('barcode');
		if (!usr_id && !usr_barcode) {

			user = new au();
			user.id(fakeid());
			user.isnew(1);

			user.mailing_address( new aua() );
			user.mailing_address().isnew(1);
			user.mailing_address().id(fakeid());

			user.billing_address( user.mailing_address() );

			user.card( new ac() );
			user.card().isnew(1);
			user.card().id(fakeid());

			user.addresses([]);
			user.addresses().push(user.mailing_address());
			
			user.cards([]);
			user.cards().push(user.card());

		} else {
			var req;
			if (usr_id) {
				req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.user.fleshed.retrieve', ses_id, usr_id );
			} else {
				req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.user.fleshed.retrieve_by_barcode', ses_id, usr_barcode );
			}
			req.send(true);
			user = req.getResultObject();
		}

	} else {
		user = u;
	}

	if (user.id() > 0) x['user.id'].value = user.id();
	if (cgi.param('adv')) x['user.id'].parentNode.parentNode.setAttribute('adv', 'false');

	if (user.create_date()) x['user.create_date'].value = user.create_date();

	if (user.usrname()) x['user.usrname'].value = user.usrname();
	x['user.usrname'].setAttribute('onchange','user.usrname(this.value)');

	if (user.card() && user.card().barcode()) x['user.card.barcode'].value = user.card().barcode();
	x['user.card.barcode'].setAttribute('onchange','user.card().barcode(this.value)');
	if (user.isnew()) {
		x['user.card.barcode'].disabled = false;
	} else {
		x['replace_card'].className = '';
		x['replace_card'].setAttribute('onclick',
			'user.card(new ac()); ' +
			'user.card().isnew(1); ' +
			'user.card().id(fakeid()); ' +
			'user.cards().push(user.card()); ' +
			'this.parentNode.firstChild.disabled = false; ' +
			'this.parentNode.firstChild.value = ""; ' +
			'this.parentNode.firstChild.focus(); ' +
			'return false;'
		);
	}

	if (user.passwd()) x['user.passwd'].value = user.passwd();
	x['user.passwd'].setAttribute('onchange','user.passwd(this.value)');

	if (user.prefix()) x['user.prefix'].value = user.prefix();
	x['user.prefix'].setAttribute('onchange','user.prefix(this.value)');

	if (user.first_given_name()) x['user.first_given_name'].value = user.first_given_name();
	x['user.first_given_name'].setAttribute('onchange','user.first_given_name(this.value)');

	if (user.second_given_name()) x['user.second_given_name'].value = user.second_given_name();
	x['user.second_given_name'].setAttribute('onchange','user.second_given_name(this.value);');

	if (user.family_name()) x['user.family_name'].value = user.family_name();
	x['user.family_name'].setAttribute('onchange','user.family_name(this.value)');

	if (user.suffix()) x['user.suffix'].value = user.suffix();
	x['user.suffix'].setAttribute('onchange','user.suffix(this.value)');

	if (user.dob()) x['user.dob'].value = user.dob();
	x['user.dob'].setAttribute('onchange','user.dob(this.value)');

	if (user.ident_value()) x['user.ident_value'].value = user.ident_value();
	x['user.ident_value'].setAttribute('onchange','user.ident_value(this.value)');

	if (user.ident_value2()) x['user.ident_value2'].value = user.ident_value2();
	x['user.ident_value2'].setAttribute('onchange','user.ident_value2(this.value)');

	if (user.email()) x['user.email'].value = user.email();
	x['user.email'].setAttribute('onchange','user.email(this.value)');

	if (user.day_phone()) x['user.day_phone'].value = user.day_phone();
	x['user.day_phone'].setAttribute('onchange','user.day_phone(this.value)');

	if (user.evening_phone()) x['user.evening_phone'].value = user.evening_phone();
	x['user.evening_phone'].setAttribute('onchange','user.evening_phone(this.value)');

	if (user.other_phone()) x['user.other_phone'].value = user.other_phone();
	x['user.other_phone'].setAttribute('onchange','user.other_phone(this.value)');

	if (user.expire_date()) x['user.expire_date'].value = user.expire_date();
	x['user.expire_date'].setAttribute('onchange','user.expire_date(this.value)');

	if (user.active()) x['user.active'].checked = true;
	x['user.active'].setAttribute('onchange','user.active(this.checked ? "t" : "f" )');

	if (user.master_account()) x['user.master_account'].checked = true;
	x['user.master_account'].setAttribute('onchange','user.master_account(this.checked ? "t" : "f" )');

	if (user.super_user()) x['user.super_user'].checked = true;
	x['user.super_user'].setAttribute('onchange','user.super_user(this.checked ? "t" : "f" )');
	if (cgi.param('adv')) x['user.super_user'].parentNode.parentNode.setAttribute('adv', 'false');

	if (user.claims_returned_count()) x['user.claims_returned_count'].value = user.claims_returned_count();
	// onchange handled by func above

	if (user.alert_message()) x['user.alert_message'].value = user.alert_message();
	x['user.alert_message'].setAttribute('onchange','user.alert_message(this.value)');


	// set up the home_ou selector
	req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.org_tree.retrieve' );
	req.send(true);
	orgTree = req.getResultObject();

	selectBuilder(
		'user.home_ou',
		[orgTree],
		user.home_ou(),
		{ label_field		: 'name',
		  value_field		: 'id',
		  empty_label		: '-- Required --',
		  empty_value		: '',
		  clear			: true,
		  child_field_name	: 'children' }
	);

	x['user.home_ou'].setAttribute('onchange','user.home_ou(this.options[this.selectedIndex].value)');

	// set up the ident_type selector
	req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.user.ident_types.retrieve' );
	req.send(true);
	ident_type_list = req.getResultObject();

	selectBuilder(
		'user.ident_type',
		ident_type_list,
		user.ident_type(),
		{ label_field		: 'name',
		  value_field		: 'id',
		  empty_label		: '-- Required --',
		  empty_value		: '',
		  clear			: true }
	);

	x['user.ident_type'].setAttribute('onchange','user.ident_type(this.options[this.selectedIndex].value)');

	selectBuilder(
		'user.ident_type2',
		ident_type_list,
		(user.ident_value2 == '' ? user.ident_type2() : ''),
		{ label_field		: 'name',
		  value_field		: 'id',
		  empty_label		: '-- Optional --',
		  empty_value		: '',
		  clear			: true }
	);

	x['user.ident_type2'].setAttribute('onchange','var x = this.options[this.selectedIndex].value; x ? user.ident_type2(x) : user.ident_type2(null);');


	// set up the standing selector
	req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.standings.retrieve' );
	req.send(true);
	standing_list = req.getResultObject();

	selectBuilder(
		'user.standing',
		standing_list,
		user.standing(),
		{ label_field		: 'value',
		  value_field		: 'id',
		  empty_label		: '-- Required --',
		  empty_value		: '',
		  clear			: true }
	);

	x['user.standing'].setAttribute('onchange','user.standing(this.options[this.selectedIndex].value)');

	// set up the profile selector
	req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.groups.tree.retrieve' );
	req.send(true);
	group_tree = req.getResultObject();

	selectBuilder(
		'user.profile',
		[group_tree],
		user.profile(),
		{ label_field		: 'name',
		  value_field		: 'id',
		  empty_label		: '-- Required --',
		  empty_value		: '',
		  clear			: true,
		  child_field_name	: 'children' }
	);

	x['user.profile'].setAttribute('onchange','user.profile(this.options[this.selectedIndex].value)');

	// set up the profile selector
	var user_group_objects = [];
	if (user.id() > 0) {
		req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.user.get_groups', ses_id, user.id() );
		req.send(true);
		user_group_objects = req.getResultObject();
	}

	user_groups = [];
	for (var i in user_group_objects) {
		user_groups.push(user_group_objects[i].grp());
	}

	selectBuilder(
		'permgroups',
		[group_tree],
		user_groups,
		{ label_field		: 'name',
		  value_field		: 'id',
		  clear			: true,
		  child_field_name	: 'children' }
	);

	x['permgroups'].setAttribute( 'onchange', 
		'window.user_groups = [];' +
		'for (var i = 0; i < this.options.length; i++) {' +
		'	if (this.options[i].selected)' +
		'		window.user_groups.push(this.options[i].value);' +
		'}');

		display_all_addresses();

	if (cgi.param('adv')) x['permgroups'].parentNode.parentNode.setAttribute('adv', 'false');

	req = new RemoteRequest( 'open-ils.circ', 'open-ils.circ.survey.retrieve.required', ses_id );
	req.send(true);
	surveys = req.getResultObject();

	var f = document.getElementById('surveys');
	while (f.firstChild) f.removeChild(f.lastChild);

	for ( var i in surveys )
		display_survey( f, surveys[i].id(), user.id() );

	req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.permissions.user_perms.retrieve', ses_id );
	req.send(true);
	var staff_perms = req.getResultObject();

	user_perms = [];
	perm_list = [];
	if (user.id() > 0) {
		req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.permissions.user_perms.retrieve', ses_id, user.id() );
		req.send(true);
		var up = req.getResultObject();
		for (var i in up) {
			if (up[i].id() > 0)
				user_perms.push(up[i]);
		}

		req = new RemoteRequest( 'open-ils.actor', 'open-ils.actor.permissions.retrieve' );
		req.send(true);
		perm_list = req.getResultObject();
	}

	f = document.getElementById('permissions');
	while (f.firstChild) f.removeChild(f.lastChild);

	for (var i in perm_list)
		display_perm(f,perm_list[i],staff_perms);


	req = new RemoteRequest( 'open-ils.circ', 'open-ils.circ.stat_cat.actor.retrieve.all', ses_id );
	req.send(true);
	var sc_list = req.getResultObject();

	var missing_scs = [];
	for (var i in user.stat_cat_entries()) {
		var found = 0;
		for (var j in sc_list) {
			if (sc_list[j].id() == user.stat_cat_entries()[i].stat_cat()) {
				found = 1;
				break;
			}
		}
		if (!found)
			missing_scs.push(user.stat_cat_entries()[i].stat_cat());
	}
	
	req = new RemoteRequest( 'open-ils.circ', 'open-ils.circ.stat_cat.actor.retrieve.batch', ses_id, missing_scs );
	req.send(true);
	var foreign_sc_list = req.getResultObject();

	f = document.getElementById('statcats');
	while (f.firstChild) f.removeChild(f.lastChild);

	for (var i in sc_list)
		display_sc(f,sc_list[i],user.stat_cat_entries());

	for (var i in foreign_sc_list)
		display_sc(f,foreign_sc_list[i],user.stat_cat_entries(), true);

	return true;
}

function set_sc_value (node) {
	var id = parseInt(node.getAttribute('scid'));
	var value = node.value;


	var sc;
	for (var i in user.stat_cat_entries()) {
		if (user.stat_cat_entries()[i].stat_cat() == id) {
			user.stat_cat_entries()[i].stat_cat_entry(value);
			if (value == '') {
				user.stat_cat_entries()[i].isdeleted(1);
			} else {
				user.stat_cat_entries()[i].isdeleted(0);
				user.stat_cat_entries()[i].ischanged(1);
			}
			sc = user.stat_cat_entries()[i];
			break;
		}
	}

	if (!sc) {
		sc = new actscecm();
		sc.isnew(1);
		sc.stat_cat_entry(value);
		sc.stat_cat(id);
		sc.target_usr(user.id());

		user.stat_cat_entries().push(sc);
	}
}

function display_sc (root,sc_def, user_scs, foreign) {

	var sc;
	for (var i in user_scs) {
		if (sc_def.id() == user_scs[i].stat_cat()) {
			sc = user_scs[i];
			break;
		}
	}

	var sc_row = findNodeByName(document.getElementById('statcat-tmpl'), 'scrow').cloneNode(true);
	root.appendChild(sc_row);

	findNodeByName(sc_row,'sc.name').appendChild(text(sc_def.name()));

	var text_box = findNodeByName(sc_row,'sce.value');
	text_box.setAttribute('scid', sc_def.id());
	if (sc) text_box.value = sc.stat_cat_entry();

	if (!foreign) {
		if (sc_def.entries().length > 0) {
			var selector = findNodeByName(sc_row,'sce_select');
			selector.id = 'scid-' + sc_def.id();

			removeCSSClass(selector.parentNode, 'hideme');
	
			selectBuilder(
				'scid-' + sc_def.id(),
				sc_def.entries(),
				(sc ? sc.stat_cat_entry() : ''),
				{ label_field		: 'value',
			  	value_field		: 'value',
			  	empty_label		: '-- Select One --',
			  	empty_value		: '',
			  	clear			: true }
			);
		}
	} else {
		text_box.disabled = true;
		text_box.parentNode.appendChild(text('(Foreign Stat Cat)'));
	}
}

function display_perm (root,perm_def,staff_perms) {

	var prow = findNodeByName(document.getElementById('permission-tmpl'), 'prow').cloneNode(true);
	root.appendChild(prow);

	var all = false;
	for (var i in staff_perms) {
		if (staff_perms[i].perm() == -1) {
			all = true;
			break;
		}
	}


	var sp,up;
	if (!all) {
		for (var i in staff_perms) {
			if (perm_def.id() == staff_perms[i].perm() || staff_perms[i].perm() == -1) {
				sp = staff_perms[i];
				break;
			}
		}
	}

	for (var i in user_perms) {
		if (perm_def.id() == user_perms[i].perm() && user_perms[i].id() > 0)
			up = user_perms[i];
	}


	var dis = false;
	if (!sp || !sp.grantable()) dis = true; 
	if (all) dis = false; 

	var label_cell = findNodeByName(prow,'plabel');
	findNodeByName(label_cell,'p.code').appendChild(text(perm_def.code()));
	findNodeByName(label_cell,'p.code').setAttribute('title', perm_def.description());
	findNodeByName(label_cell,'p.code').setAttribute('permid', perm_def.id());

	var apply_cell = findNodeByName(prow,'papply');
	findNodeByName(apply_cell,'p.id').disabled = dis;
	findNodeByName(apply_cell,'p.id').checked = up ? true : false;

	var depth_cell = findNodeByName(prow,'pdepth');
	findNodeByName(depth_cell,'p.depth').disabled = dis;
	findNodeByName(depth_cell,'p.depth').id = 'perm-depth-' + perm_def.id();
	selectBuilder(
		'perm-depth-' + perm_def.id(),
		globalOrgTypes,
		(up ? up.depth() : findOrgDepth(user.home_ou())),
		{ label_field		: 'name',
		  value_field		: 'depth',
		  empty_label		: '-- Select One --',
		  empty_value		: '',
		  clear			: true }
	);
	
	var grant_cell = findNodeByName(prow,'pgrant');
	findNodeByName(grant_cell,'p.grantable').disabled = dis;
	findNodeByName(grant_cell,'p.grantable').checked = up ? (up.grantable() ? true : false) : false;

}

function display_all_addresses () {
	d = document.getElementById('addresses');
	while (d.firstChild)
		d.removeChild(d.lastChild);

	for (var i in user.addresses())
		display_address(document.getElementById('addresses'), user.addresses()[i]);
}

function new_addr () {
	var x = new aua();
	x.isnew(1);
	x.id(fakeid());

	user.addresses().push(x);
	display_address(document.getElementById('addresses'), x);
}

function display_survey (div, sid, uid) {

	var t = document.getElementById('survey-tmpl').firstChild.cloneNode(true);
	div.appendChild(t);
	
	init_survey(t,sid,uid);
}

function display_address (div, adr) {

	var dis = false;
	if (adr.isdeleted()) dis = true;

	var t = document.getElementById('addr-tmpl').getElementsByTagName('table')[0].cloneNode(true);
	div.appendChild(t);

	var x;

	x = findNodeByName(t, 'adr.address_type');
	x.disabled = dis;
	if (adr.address_type()) x.value = adr.address_type();
	x.setAttribute( 'onchange', 'findAddressById(' + adr.id() + ').address_type(this.value)');

	x = findNodeByName(t, 'adr.street1');
	x.disabled = dis;
	if (adr.street1()) x.value = adr.street1();
	x.setAttribute( 'onchange', 'findAddressById(' + adr.id() + ').street1(this.value)');

	x = findNodeByName(t, 'adr.street2');
	x.disabled = dis;
	if (adr.street2()) x.value = adr.street2();
	x.setAttribute( 'onchange', 'findAddressById(' + adr.id() + ').street2(this.value)');

	x = findNodeByName(t, 'adr.city');
	x.disabled = dis;
	if (adr.city()) x.value = adr.city();
	x.setAttribute( 'onchange', 'findAddressById(' + adr.id() + ').city(this.value)');

	x = findNodeByName(t, 'adr.state');
	x.disabled = dis;
	if (adr.state()) x.value = adr.state();
	x.setAttribute( 'onchange', 'findAddressById(' + adr.id() + ').state(this.value)');

	x = findNodeByName(t, 'adr.post_code');
	x.disabled = dis;
	if (adr.post_code()) x.value = adr.post_code();
	x.setAttribute( 'onchange', 'findAddressById(' + adr.id() + ').post_code(this.value)');

	x = findNodeByName(t, 'adr.county');
	x.disabled = dis;
	if (adr.county()) x.value = adr.county();
	x.setAttribute( 'onchange', 'findAddressById(' + adr.id() + ').county(this.value)');

	x = findNodeByName(t, 'adr.country');
	x.disabled = dis;
	if (adr.country()) x.value = adr.country();
	x.setAttribute( 'onchange', 'findAddressById(' + adr.id() + ').country(this.value)');

	x = findNodeByName(t, 'adr.valid');
	x.disabled = dis;
	if (adr.valid()) x.checked = true;
	x.setAttribute( 'onchange', 'findAddressById(' + adr.id() + ').valid(this.checked ? "t" : "f")');

	x = findNodeByName(t, 'is_mailing');
	x.disabled = dis;
	x.value = adr.id();
	x.setAttribute( 'onclick', 'user.mailing_address(findAddressById(' + adr.id() + '))');
	if (adr.id() == user.mailing_address().id()) {
		x.checked = true;
	}

	x = findNodeByName(t, 'is_billing');
	x.disabled = dis;
	x.value = adr.id();
	x.setAttribute( 'onclick', 'user.billing_address(findAddressById(' + adr.id() + '))');
	if (adr.id() == user.billing_address().id()) {
		x.checked = true;
	}

	x = findNodeByName(t, 'remove');
	if (dis) {
		x.setAttribute('onclick', 'unremove_adr(' + adr.id() + '); return false;');
		x.innerHTML = "Undelete this address";
	} else {
		x.setAttribute('onclick', 'remove_adr(' + adr.id() + '); return false;');
	}


	return true;
}

function unremove_adr (id) {
	findAddressById(id).isdeleted(0);
	display_all_addresses();
}	

function remove_adr (id) {
	findAddressById(id).isdeleted(1);
	display_all_addresses();
}	

function findAddressById (id) {
	for (var i in user.addresses())
		if (user.addresses()[i].id() == id) return user.addresses()[i];
}


function selectBuilder (id, objects, def, args) {
	var label_field = args['label_field'];
	var value_field = args['value_field'];
	var depth = args['depth'];

	if (!depth) depth = 0;

	args['depth'] = parseInt(depth) + 1;

	var child_field_name = args['child_field_name'];

	var sel = id;
	if (typeof sel != 'object')
		sel = document.getElementById(sel);

	if (args['clear']) {
		for (var o in sel.options) {
			sel.options[o] = null;
		}
		args['clear'] = false;
		if (args['empty_label']) {
			sel.options[0] = new Option( args['empty_label'], args['empty_value'] );
			sel.selectedIndex = 0;
		}
	}

	for (var i in objects) {
		var l = objects[i][label_field];
		var v = objects[i][value_field];

		if (typeof l == 'function')
			l = objects[i][label_field]();

		if (typeof v == 'function')
			v = objects[i][value_field]();

		var opt = new Option( l, v );

		if (depth) {
			var d = 10 * depth;
			opt.style.paddingLeft = '' + d + 'px';
		}

		sel.options[sel.options.length] = opt;


		if (typeof def == 'object') {
			for (var j in def) {
				if (v == def[j]) opt.selected = true;
			}
		} else {
			if (v == def) opt.selected = true;
		}

		if (child_field_name) {
			var c = objects[i][child_field_name];
			if (typeof c == 'function')
				c = objects[i][child_field_name]();

			selectBuilder(
				id,
				c,
				def,
				{ label_field		: args['label_field'],
				  value_field		: args['value_field'],
				  depth			: args['depth'],
				  child_field_name	: args['child_field_name'] }
			);
		}

	}
}	

function findNodesByClass(root, nodeClass, list) {
	if(!list) list = [];
        if( !root || !nodeClass) {
		return null;
	}
        
        if(root.nodeType != 1) {
		return null;
	}
        
        if(root.className.match(nodeClass)) list.push( root );

        var children = root.childNodes;
        
        for( var i = 0; i != children.length; i++ ) {
                findNodesByClass(children[i], nodeClass, list);
        }                       
                        
        return list;            
}                                       

