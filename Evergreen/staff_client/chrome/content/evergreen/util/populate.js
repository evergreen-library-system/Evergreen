sdump('D_TRACE','Loading populate.js\n');

function populate_listbox_with_local_stat_cats_myself(local_stat_cats,local_cat_entries,listbox,libs,app,method,editable) {
	sdump('D_TRACE','populate_local_stat_cats: pertinent libs = ' + js2JSON(libs) + '\n');

	local_stat_cats = user_request(
		app,
		method,
		[ mw.G.auth_ses[0], libs ]
	)[0];
	//sdump('D_POPULATE','local_stat_cats = ' + pretty_print( js2JSON( local_stat_cats ) ) + '\n');

	var list = listbox;
	if (typeof list != 'object') list = document.getElementById(list);

	for (var i in local_stat_cats) {

		var stat_cat = local_stat_cats[i];

		var listitem = document.createElement('listitem'); 
		list.appendChild(listitem);
		listitem.setAttribute('allowevents','true');
		sdump('D_POPULATE','listitem = ' + listitem + '\n');

			var label = document.createElement('listcell'); 
			listitem.appendChild(label);
			label.setAttribute('label',stat_cat.name() );
			sdump('D_POPULATE','\tlistcell = ' + label + '\n');

			var menucell = document.createElement('listcell'); 
			listitem.appendChild(menucell);
			sdump('D_POPULATE','\tlistcell = ' + menucell + '\n');

				var menulist = document.createElement('menulist');
				menucell.appendChild(menulist);
				if (editable) { menulist.setAttribute('editable','true'); }
				menulist.setAttribute('id','menulist_stat_cat_'+stat_cat.id());
				sdump('D_POPULATE','\tmenulist = ' + menulist + '\n');

					var menupopup = document.createElement('menupopup');
					menulist.appendChild(menupopup);
					menupopup.setAttribute('stat_cat',stat_cat.id());
					menupopup.setAttribute('oncommand','apply_attribute(event);');
					sdump('D_POPULATE','\t\tmenupopup = ' + menupopup + '\n');

		for (var j in stat_cat.entries() ) {

			var stat_entry = stat_cat.entries()[j];
			local_stat_cat_entries[stat_entry.id()] = stat_entry;

			var menuitem = document.createElement('menuitem');
			menupopup.appendChild(menuitem);
			menuitem.setAttribute('label',stat_entry.value());
			if (editable) {
				menuitem.setAttribute('value',stat_entry.value());
			} else {
				menuitem.setAttribute('value',stat_entry.id());
			}
			menuitem.setAttribute('stat_cat',stat_cat.id());
			menuitem.setAttribute('id','menuitem_stat_cat_entry_' + stat_entry.id());
			sdump('D_POPULATE','\t\t\tmenuitem = ' + menuitem + '\n');

		}

	}

	//sdump('D_POPULATE','local_stat_cat_entries = ' + pretty_print( js2JSON( local_stat_cat_entries ) ) + '\n');

}

function populate_rows_with_local_stat_cats(local_stat_cats,local_stat_cat_entries,rows,editable) {
	//sdump('D_TRACE','populate_local_stat_cats: pertinent libs = ' + js2JSON(libs) + '\n');

	/*local_stat_cats = user_request(
		app,
		method,
		[ mw.G.auth_ses[0], libs ]
	)[0];*/
	//sdump('D_POPULATE','local_stat_cats = ' + pretty_print( js2JSON( local_stat_cats ) ) + '\n');

	if (typeof rows != 'object') rows = document.getElementById(rows);

	for (var i in local_stat_cats) {

		var stat_cat = local_stat_cats[i];

		var row = document.createElement('row');
		rows.appendChild(row);

		var label = document.createElement('label');
		label.setAttribute('value',stat_cat.name());
		row.appendChild(label);

		var menulist = document.createElement('menulist');
		row.appendChild(menulist);
		if (editable) { menulist.setAttribute('editable','true'); }
		menulist.setAttribute('id','menulist_stat_cat_'+stat_cat.id());
		menulist.setAttribute('stat_cat_id',stat_cat.id());
		sdump('D_POPULATE','\tmenulist = ' + menulist + '\n');

			var menupopup = document.createElement('menupopup');
			menulist.appendChild(menupopup);
			menupopup.setAttribute('stat_cat',stat_cat.id());
			menupopup.setAttribute('command','cmd_apply');
			sdump('D_POPULATE','\t\tmenupopup = ' + menupopup + '\n');

		for (var j in stat_cat.entries() ) {

			var stat_entry = stat_cat.entries()[j];
			local_stat_cat_entries[stat_entry.id()] = stat_entry;

			var menuitem = document.createElement('menuitem');
			menupopup.appendChild(menuitem);
			menuitem.setAttribute('label',stat_entry.value());
			if (editable) {
				menuitem.setAttribute('value',stat_entry.value());
			} else {
				menuitem.setAttribute('value',stat_entry.id());
			}
			menuitem.setAttribute('stat_cat',stat_cat.id());
			menuitem.setAttribute('id','menuitem_stat_cat_entry_' + stat_entry.id());
			sdump('D_POPULATE','\t\t\tmenuitem = ' + menuitem + '\n');

		}

	}

	//sdump('D_POPULATE','local_stat_cat_entries = ' + pretty_print( js2JSON( local_stat_cat_entries ) ) + '\n');

}

function populate_copy_status_list(menulist,menupopup,defaultccs) {
	sdump('D_TRACE','populate_copy_status_list\n');
	var popup = document.getElementById(menupopup);

	if (popup) {
		empty_widget(popup);
		for (var i in mw.G.ccs_list) {
			var menuitem = document.createElement('menuitem');
			menuitem.setAttribute('label', mw.G.ccs_list[i].name()); 
			menuitem.setAttribute('value', mw.G.ccs_list[i].id()); 
			menuitem.setAttribute('id', 'ccsitem' + mw.G.ccs_list[i].id()); 
			//sdump('D_POPULATE','pop_ccs_list: i = ' + i + ' ccs = ' + mw.G.ccs_list[i] + ' = ' + js2JSON(mw.G.ccs_list[i]) + '\n');
			popup.appendChild(menuitem);
		}
		var list = document.getElementById(menulist);
		if (list && defaultccs) {
			if (typeof defaultccs == 'object') {
				defaultccs = defaultccs.id();	
			}
			var menuitem_id = 'ccsitem' + defaultccs;
			var menuitem = document.getElementById(
				menuitem_id
			);
			var  menulist_e = document.getElementById(menulist);
			if (menulist_e && menuitem) { 
				sdump('D_POPULATE','Setting default ccs\n');
				menulist_e.selectedItem = menuitem; 
			} else {
				sdump('D_POPULATE','Not Setting default ccs\n');
			}
		}
	} else {
			sdump('D_POPULATE','populate_copy_status_list: Could not find menupopup: ' + menupopup + '\n');
			throw('populate_copy_status_list: Could not find menupopup: ' + menupopup + '\n');
	}

}

function populate_copy_location_list(menulist,menupopup,defaultacpl) {
	sdump('D_TRACE','populate_copy_location_list\n');
	var popup = document.getElementById(menupopup);

	if (popup) {
		empty_widget(popup);
		for (var i in mw.G.acpl_my_orgs) {
			var menuitem = document.createElement('menuitem');
			menuitem.setAttribute('label', mw.G.acpl_my_orgs[i].name()); 
			menuitem.setAttribute('value', mw.G.acpl_my_orgs[i].id()); 
			menuitem.setAttribute('id', 'acplitem' + mw.G.acpl_my_orgs[i].id()); 
			//sdump('D_POPULATE','populate_copy_location_list: i = ' + i + ' acpl_my_orgs = ' + mw.G.acpl_my_orgs[i] + ' = ' + js2JSON(mw.G.acpl_my_orgs[i]) + '\n');
			popup.appendChild(menuitem);
		}
		var list = document.getElementById(menulist);
		if (list && defaultacpl) {
			if (typeof defaultacpl == 'object') {
				defaultacpl = defaultacpl.id();	
			}
			var menuitem_id = 'acplitem' + defaultacpl;
			var menuitem = document.getElementById(
				menuitem_id
			);
			var menulist_e = document.getElementById(menulist);
			if (menulist_e && menuitem) { menulist_e.selectedItem = menuitem; }
		}
	} else {
			sdump('D_POPULATE','populate_copy_location_list: Could not find menupopup: ' + menupopup + '\n');
			throw('populate_copy_location_list: Could not find menupopup: ' + menupopup + '\n');
	}

}

function populate_lib_list(menulist,menupopup,defaultlib,id_flag) {
	sdump('D_TRACE','populate_lib_list\n');
	var default_menuitem;
	if (typeof defaultlib == 'object') {
		defaultlib = defaultlib.id();	
	}
	var popup = menupopup;
	if (typeof(popup)!='object') { popup = document.getElementById(menupopup); }
	if (popup) {
		//sdump('D_POPULATE','found popup\n');
		empty_widget(popup);
		var padding_flag = false;
		for (var ou in mw.G.my_orgs) {
			//sdump('D_POPULATE','\tlooping on my_orgs:  ' + js2JSON(mw.G.my_orgs[ou]) + '\n');
			//sdump('D_POPULATE','\tlooping on my_orgs:  ou = ' + ou + '\n');
			var menuitem = document.createElement('menuitem');
			popup.appendChild(menuitem);
			//sdump('D_POPULATE','\t\tmenuitem = ' + menuitem + '\n');
			var padding = '';
			//var depth = find_id_object_in_list( mw.G.aout_list, mw.G.my_orgs[ou].ou_type() ).depth();
			var depth = mw.G.aout_hash[ mw.G.my_orgs[ou].ou_type() ].depth();
			if (depth == '0') { padding_flag = true; }
			if (padding_flag) {
				for (var i = 0; i < depth; i++) { 
					padding = padding + '  '; 
				}
			}
			menuitem.setAttribute('label', padding + mw.G.my_orgs[ou].name() );
			menuitem.setAttribute('value', mw.G.my_orgs[ou].id() );
			if (id_flag) menuitem.setAttribute('id', 'libitem' + mw.G.my_orgs[ou].id() );
			//sdump('D_POPULATE','\tname = ' + mw.G.my_orgs[ou].name() + '  id = ' + mw.G.my_orgs[ou].id() + '\n');
			if (defaultlib == mw.G.my_orgs[ou].id()) {
				default_menuitem = menuitem;
				sdump('D_POPULATE','Setting defaultlib = ' + defaultlib + '\n');
			}
		}
		var list = menulist;
		if (typeof(list)!='object') { list = document.getElementById(menulist); }
		if (list && defaultlib && default_menuitem) {
			//sdump('D_POPULATE','default_menuitem = ' + default_menuitem + '\n');
			if (list) { list.selectedItem = default_menuitem; }
		}
	} else {
			sdump('D_POPULATE','populate_lib_list: Could not find ' + menupopup + '\n');
			throw('populate_lib_list: Could not find ' + menupopup + '\n');
	}
}

function populate_lib_list_with_branch(menulist,menupopup,defaultlib,branch,id_flag) {
	sdump('D_TRACE','populate_lib_list_with_branch\n');
	var default_menuitem;
	if (typeof defaultlib == 'object') {
		defaultlib = defaultlib.id();	
	}
	var popup = menupopup;
	if (typeof(popup)!='object') popup = document.getElementById(menupopup);
	if (popup) {
		empty_widget(popup);
		var padding_flag = true;
		var flat_branch = flatten_ou_branch( branch );
		//sdump('D_POPULATE','\n\nflat_branch = ' + js2JSON(flat_branch) + '\n');
		for (var i in flat_branch) {
			//sdump('D_POPULATE','i = ' + js2JSON(i) + ' flat_branch[i] = ' + js2JSON(flat_branch[i]) + '\n');
			var menuitem = document.createElement('menuitem');
			var padding = '';
			//if (flat_branch[i].ou_type().depth() == '0') { padding_flag = true; }
			var depth = mw.G.aout_hash[ flat_branch[i].ou_type() ].depth();
			if (padding_flag) {
				for (var j = 0; j < depth; j++) { 
					padding = padding + '  '; 
				}
			}
			menuitem.setAttribute('label', padding + flat_branch[i].name() );
			menuitem.setAttribute('value', flat_branch[i].id() );
			if (id_flag) menuitem.setAttribute('id', 'libitem' + flat_branch[i].id() );
			if (defaultlib == flat_branch[i].id()) {
				default_menuitem = menuitem;
				sdump('D_POPULATE','i = ' + i + ' Setting defaultlib = ' + defaultlib + '   menuitem = ' + default_menuitem + '  value = ' + default_menuitem.getAttribute('value') + '\n');
			}
			popup.appendChild(menuitem);
		}
		var list = menulist;
		if (typeof(list)!='object') { list = document.getElementById(menulist); }
		if (list && defaultlib && default_menuitem) {
			//sdump('D_POPULATE','default_menuitem = ' + default_menuitem + ' value = ' + default_menuitem.getAttribute('value') + '\n');
			if (list) { list.selectedItem = default_menuitem; }
		}
	} else {
			sdump('D_POPULATE','populate_lib_list_with_branch: Could not find ' + menupopup + '\n');
			throw('populate_lib_list_with_branch: Could not find ' + menupopup + '\n');
	}
	sdump('D_POPULATE','\tleaving populate_lib_list_with_branch\n');
}

function populate_user_profile(menulist,menupopup,defaultap) {
	sdump('D_TRACE','Entering populate_user_profile\n');
	var popup = document.getElementById(menupopup);
	if (popup) {
		empty_widget(popup);
		for (var i in mw.G.ap_list) {
			var menuitem = document.createElement('menuitem');
			menuitem.setAttribute('label', mw.G.ap_list[i].name()); 
			menuitem.setAttribute('value', mw.G.ap_list[i].id()); 
			menuitem.setAttribute('id', 'apitem' + mw.G.ap_list[i].id()); 
			//sdump('D_POPULATE','pop_ap_list: i = ' + i + ' ap = ' + mw.G.ap_list[i] + ' = ' + js2JSON(mw.G.ap_list[i]) + '\n');
			popup.appendChild(menuitem);
		}
		var list = document.getElementById(menulist);
		if (list && defaultap) {
			if (typeof defaultap == 'object') {
				defaultap = defaultap.id();	
			}
			var menuitem_id = 'apitem' + defaultap;
			var menuitem = document.getElementById(
				menuitem_id
			);
			var  menulist_e = document.getElementById(menulist);
			if (menulist_e) { menulist_e.selectedItem = menuitem; }
		}
	} else {
			sdump('D_POPULATE','populate_user_profile: Could not find menupopup: ' + menupopup + '\n');
			throw('populate_user_profile: Could not find menupopup: ' + menupopup + '\n');
	}
}

function populate_ident_types(menulist,menupopup,repeatid,defaultcit) {
	sdump('D_TRACE','Entering populate_ident_types\n');
	var popup = document.getElementById(menupopup);
	if (popup) {
		empty_widget(popup);
		for (var i in mw.G.cit_list) {
			var menuitem = document.createElement('menuitem');
			menuitem.setAttribute('label', mw.G.cit_list[i].name()); 
			menuitem.setAttribute('value', mw.G.cit_list[i].id()); 
			menuitem.setAttribute('id', 'cit' + repeatid + 'item' + mw.G.cit_list[i].id()); 
			//sdump('D_POPULATE','pop_cit_list: i = ' + i + ' cit = ' + mw.G.cit_list[i] + ' = ' + js2JSON(mw.G.cit_list[i]) + '\n');
			popup.appendChild(menuitem);
		}
		if (list && defaultcit) {
			if (typeof defaultcit == 'object') {
				defaultcit = defaultcit.id();	
			}
			var menuitem_id = 'cit' + repeatid + 'item' + defaultcit;
			var menuitem = document.getElementById(
				menuitem_id
			);
			var  menulist_e = document.getElementById(menulist);
			if (menulist_e) { menulist_e.selectedItem = menuitem; }
		}
	} else {
			sdump('D_POPULATE','populate_ident_types: Could not find menupopup: ' + menupopup + '\n');
			throw('populate_ident_types: Could not find menupopup: ' + menupopup + '\n');
	}
}



function populate_name_prefix(menulist,menupopup,defaultvalue) {
	var popup = document.getElementById(menupopup);
	if (popup) {
		empty_widget(popup);
		var prefix_list = [
			'Mr','Mrs','Ms','Miss', 'Dr',
			'',
			'Advisor',
			'Airman',
			'Admiral',
			'Agent',
			'Ambassador',
			'Baron',
			'Baroness',
			'Bishop',
			'Brother',
			'Cadet',
			'Captain',
			'Cardinal',
			'Chairperson',
			'Chancellor',
			'Chief',
			'Colonel', 
			'Commander',
			'Commodore',
			'Congressman',
			'Congresswoman',
			'Constable',
			'Consul',
			'Corporal',
			'Councilperson',
			'Counselor',
			'Dean',
			'Duchess',
			'Duke',
			'Elder',
			'Ensign',
			'Father',
			'General',
			'Governor',
			'Judge',
			'Justice',
			'King',
			'Lady',
			'Lieutenant',
			'Lord',
			'Major',
			'Marshal',
			'Mayor',
			'Midshipman',
			'Minister',
			'Monsignor',
			'Officer',
			'Pastor',
			'Petty Officer',
			'Pope',
			'Prince',
			'Princess',
			'President',
			'Private',
			'Prof',
			'Queen',
			'Rabbi',
			'Representative',
			'Reverend',
			'Seaman',
			'Secretary',
			'Senator',
			'Sergeant',
			'Sheriff',
			'Sir',
			'Sister',
			'Speaker',
			'Specialist',
			'Treasurer',
			'Vice President',
			'Warrant Officer'
		];
		for (var i in prefix_list) {
			var menuitem = document.createElement('menuitem');
			menuitem.setAttribute('label', prefix_list[i]); 
			menuitem.setAttribute('value', prefix_list[i]); 
			popup.appendChild(menuitem);
		}
		var list = document.getElementById(menulist);
		if (list) {
			if (defaultvalue) { 
				list.value = defaultvalue;
			}
		} else {
			sdump('D_POPULATE','populate_name_prefix: Could not find menulist: ' + menulist + '\n');
			throw('populate_name_prefix: Could not find menulist: ' + menulist + '\n');
		}
	} else {
			sdump('D_POPULATE','populate_name_prefix: Could not find menupopup: ' + menupopup + '\n');
			throw('populate_name_prefix: Could not find menupopup: ' + menupopup + '\n');
	}

}

function populate_name_suffix(menulist,menupopup,defaultvalue) {
	var popup = document.getElementById(menupopup);
	if (popup) {
		empty_widget(popup);
		var suffix_list = [
			'Jr','Sr','II','III',
			'',
			'AA',
			'AS',
			'AAS',
			'BA',
			'BS',
			'CFPIM',
			'CPA',
			'CPIM',
			'CPM',
			'CXE',
			'DC',
			'DDS',
			'DO', 
			'DPM',
			'DVM',
			'Esq',
			'FACAAI',
			'FACP',
			'FACS',
			'FACEP',
			'FCP',
			'FICS',
			'GYN',
			'JD',
			'LPN',
			'MA',
			'MCSE',
			'MD', 
			'MS',
			'NMD',
			'OB',
			'PhD',
			'RN'
		];
		for (var i in suffix_list) {
			var menuitem = document.createElement('menuitem');
			menuitem.setAttribute('label', suffix_list[i]); 
			menuitem.setAttribute('value', suffix_list[i]); 
			popup.appendChild(menuitem);
		}
		var list = document.getElementById(menulist);
		if (list) { 
			if (defaultvalue) { 
				list.value = defaultvalue;
			}
		} else {
			sdump('D_POPULATE','populate_name_suffix: Could not find ' + menulist + '\n');
			throw('populate_name_suffix: Could not find ' + menulist + '\n');
		}
	} else {
			sdump('D_POPULATE','populate_name_suffix: Could not find ' + menupopup + '\n');
			throw('populate_name_suffix: Could not find ' + menupopup + '\n');
	}

}

