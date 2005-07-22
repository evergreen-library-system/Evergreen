var local_copy_stat_cats = [];
var local_copy_stat_cats_hash = {};
var local_copy_stat_cat_entries = {};
var local_patron_stat_cats = [];
var local_patron_stat_cats_hash = {};
var local_patron_stat_cat_entries = {};
var local_generic_stat_cats = [];
var local_generic_stat_cats_hash = {};
var local_generic_stat_cat_entries = {};
var new_id = -1;

function copy_stat_cat_editor_init() {
	sdump('D_LEGACY','entering copy_stat_cat_editor_init for copy_stat_cat.js\n');
	sdump('D_LEGACY','TESTING: stat_cat.js: ' + mw.G['main_test_variable'] + '\n');
	populate_local_copy_stat_cats(
		'copy_stat_cat_grid',
		map_list(mw.G.my_orgs, function (obj) { return obj.id(); })
	);
}

function patron_stat_cat_editor_init() {
	sdump('D_LEGACY','entering patron_stat_cat_editor_init for patron_stat_cat.js\n');
	sdump('D_LEGACY','TESTING: stat_cat.js: ' + mw.G['main_test_variable'] + '\n');
	populate_local_patron_stat_cats(
		'patron_stat_cat_grid',
		map_list(mw.G.my_orgs, function (obj) { return obj.id(); })
	);
}

function new_entry_listener(ev) {
	if (ev.target.tagName != 'textbox') return;
	var row = ev.target.parentNode;
	var rows = row.parentNode;
	var clone = row.cloneNode(true);
	if (row.nextSibling) {
		rows.insertBefore(clone,row.nextSibling);
	} else {
		rows.appendChild(clone);
	}
	clone.getElementsByTagName('textbox')[0].addEventListener('change',new_entry_listener,false);
	ev.target.removeEventListener('change',new_entry_listener,false);
} 


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// COPY

function populate_local_copy_stat_cats(grid,libs) {
	sdump('D_LEGACY','populate_local_copy_stat_cats: pertinent libs = ' + js2JSON(libs) + '\n');
	sdump('D_LEGACY','populate_local_copy_stat_cats: pertinent libs = ' + mw.js2JSON(libs) + '\n');
	sdump('D_LEGACY','libs.constructor = ' + libs.constructor + '\n');

	try {
		local_copy_stat_cats = user_request(
			'open-ils.circ',
			'open-ils.circ.stat_cat.asset.multirange.union.retrieve',
			[ mw.G.auth_ses[0], libs ]
		);
		//sdump('D_LEGACY','1: local_copy_stat_cats = ' + js2JSON(local_copy_stat_cats) + '\n');
		local_copy_stat_cats = local_copy_stat_cats[0];
		//sdump('D_LEGACY','2: local_copy_stat_cats = ' + js2JSON(local_copy_stat_cats) + '\n');
		local_copy_stat_cats_hash = convert_object_list_to_hash( local_copy_stat_cats );
	} catch(E) {
		mw.handle_error(E);
	}
	populate_local_copy_stat_cats_grid(grid);
}

function populate_local_copy_stat_cats_grid(grid) {

	sdump('D_LEGACY','local_copy_stat_cats = ' + pretty_print( js2JSON( local_copy_stat_cats ) ) + '\n');

	if (typeof(grid) != 'object') { grid = document.getElementById(grid); }
	var rows = grid.getElementsByTagName('rows')[0];
	empty_widget(rows);

	var row0 = document.createElement('row');
	rows.appendChild(row0);
	row0.appendChild( document.createElement('label') );
	row0.appendChild( document.createElement('label') );
	var delete_label = document.createElement('label');
	row0.appendChild( delete_label );
		delete_label.setAttribute('value','Delete');
	var owner_label = document.createElement('label');
	row0.appendChild( owner_label );
		owner_label.setAttribute('value','Owner');

	for (var i in local_copy_stat_cats) {

		var copy_stat_cat = local_copy_stat_cats[i];

		var row1 = document.createElement('row'); 
		rows.appendChild(row1);
		row1.setAttribute('asc_id',copy_stat_cat.id());
		row1.setAttribute('object_type','asc');
		add_css_class(row1,'row' + i % 2);

			var label1 = document.createElement('label'); 
			row1.appendChild(label1);
			label1.setAttribute('value','Statistical Category:');

			if ( find_ou( mw.G.user_ou,copy_stat_cat.owner() ) ) {
				var textbox1 = document.createElement('textbox');
				row1.appendChild(textbox1);
				textbox1.value = copy_stat_cat.name();
				textbox1.setAttribute('original',textbox1.value);
	
				var checkbox1 = document.createElement('checkbox');
				row1.appendChild(checkbox1);
				checkbox1.setAttribute('delete','true');

				var menulist1 = document.createElement('menulist');
				row1.appendChild(menulist1);
				menulist1.setAttribute('original',copy_stat_cat.owner());
	
					var menupopup1 = document.createElement('menupopup');
					menulist1.appendChild(menupopup1);
					//sdump('D_LEGACY','About to populate with copy_stat_cat.owner() = ' + copy_stat_cat.owner() + '\n');
					populate_lib_list_with_branch(menulist1,menupopup1,copy_stat_cat.owner(),mw.G.user_ou);
			} else {

				var label1a = document.createElement('label');
				row1.appendChild(label1a);
				label1a.setAttribute('value',copy_stat_cat.name() );

				row1.appendChild( document.createElement('label') );

				var label1c = document.createElement('label');
				row1.appendChild(label1c);
				label1c.setAttribute( 'value',mw.G.org_tree_hash[copy_stat_cat.owner()].name() );
			}

		var row2 = document.createElement('row'); 
		rows.appendChild(row2);
		row2.setAttribute('asc_id',copy_stat_cat.id());
		row2.setAttribute('object_type','asc');
		add_css_class(row2,'row' + i % 2);

			var label2 = document.createElement('label');
			row2.appendChild(label2);
			label2.setAttribute('value','OPAC Visible');

			if ( find_ou( mw.G.user_ou,copy_stat_cat.owner() ) ) {
				var checkbox2 = document.createElement('checkbox');
				row2.appendChild(checkbox2);
				checkbox2.checked = (copy_stat_cat.opac_visible() == '1')
				checkbox2.setAttribute('original',checkbox2.checked);
			} else {
				var label2a = document.createElement('label');
				row2.appendChild(label2a);
				label2a.setAttribute('value',yesno( copy_stat_cat.opac_visible() ));
			}

		for (var j in copy_stat_cat.entries() ) {

			var stat_entry = copy_stat_cat.entries()[j];
			local_copy_stat_cat_entries[stat_entry.id()] = stat_entry;

			var row = document.createElement('row');
			rows.appendChild(row);
			row.setAttribute('asc_id',copy_stat_cat.id());
			row.setAttribute('asce_id',stat_entry.id());
			row.setAttribute('object_type','asce');
			add_css_class(row,'row' + i % 2);

				var label = document.createElement('label');
				row.appendChild(label);
				label.setAttribute('value','Entry:');

				if ( find_ou( mw.G.user_ou,stat_entry.owner() ) ) {
					var textbox = document.createElement('textbox');
					row.appendChild(textbox);
					textbox.value = stat_entry.value();
					textbox.setAttribute('original',textbox.value);

					var checkbox = document.createElement('checkbox');
					row.appendChild(checkbox);
					checkbox.setAttribute('delete','true');

					var menulist = document.createElement('menulist');
					row.appendChild(menulist);
					menulist.setAttribute('original',stat_entry.owner());

						var menupopup = document.createElement('menupopup');
						menulist.appendChild(menupopup);
						//sdump('D_LEGACY','About to populate with stat_entry.owner() = ' + stat_entry.owner() + '\n');
						populate_lib_list_with_branch(menulist,menupopup,stat_entry.owner(),mw.G.user_ou);
				} else {

					var labela = document.createElement('label');
					row.appendChild(labela);
					labela.setAttribute('value',stat_entry.value());

					row.appendChild( document.createElement('label') );

					var labelc = document.createElement('label');
					row.appendChild(labelc);
					labelc.setAttribute( 'value',mw.G.org_tree_hash[stat_entry.owner()].name() );
				}
		}

		var row3 = document.createElement('row');
		rows.appendChild(row3);
		row3.setAttribute('asc_id',copy_stat_cat.id());
		row3.setAttribute('object_type','asce');
		row3.setAttribute('new','true');
		add_css_class(row3,'row' + i % 2);

			var label3 = document.createElement('label');
			row3.appendChild(label3);
			label3.setAttribute('value','New Entry:');

			var textbox3 = document.createElement('textbox');
			row3.appendChild(textbox3);
			textbox3.setAttribute('original','');
			textbox3.addEventListener(
				'change',
				new_entry_listener,
				false
			);

			var checkbox3 = document.createElement('checkbox');
			row3.appendChild(checkbox3);
			checkbox3.setAttribute('delete','true');

			var menulist3 = document.createElement('menulist');
			row3.appendChild(menulist3);
			menulist3.setAttribute('original',mw.G.user_ou.id());

				var menupopup3 = document.createElement('menupopup');
				menulist3.appendChild(menupopup3);
				//sdump('D_LEGACY','About to populate with mw.G.user_ou\n');
				populate_lib_list_with_branch(menulist3,menupopup3,mw.G.user_ou,mw.G.user_ou);

		var row4 = document.createElement('row');
		rows.appendChild(row4);
		add_css_class(row4,'row' + i % 2);

			var label4 = document.createElement('label');
			row4.appendChild(label4);
			label4.setAttribute('value',' ');
			
		var row5 = document.createElement('row');
		rows.appendChild(row5);

			var label5 = document.createElement('label');
			row5.appendChild(label5);
			label5.setAttribute('value',' ');

	}

	var row6 = document.createElement('row');
	rows.appendChild(row6);

		var label6 = document.createElement('label');
		row6.appendChild(label6);
		label6.setAttribute('value',' ');
	
	sdump('D_LEGACY','local_copy_stat_cat_entries = ' + pretty_print( js2JSON( local_copy_stat_cat_entries ) ) + '\n');
}
function save_copy_changes() {

	// XUL

	var nl = document.getElementsByTagName('textbox');
	for (var i = 0; i < nl.length; i++) {
		var t = nl[i];
		var row = t.parentNode;
		var object_type = row.getAttribute('object_type');
		var asc_id = row.getAttribute('asc_id');
		var asce_id = row.getAttribute('asce_id');
		var new_flag = row.getAttribute('new');
		var original = t.getAttribute('original');
		sdump('D_LEGACY','Considering textbox: object_type = ' + object_type + ' asc_id = ' + asc_id + ' asce_id = ' + asce_id + ' original = ' + original + ' value = ' + t.value + '\n');

		if ( (original != t.value) && (t.value != null) && (t.value != undefined) ) {
			sdump('D_LEGACY',"\tWe're in...\n");
			switch(object_type) {
				case 'asc': 
					local_copy_stat_cats_hash[asc_id].ischanged('1');
					local_copy_stat_cats_hash[asc_id].name( t.value );
				break;
				case 'asce': 
					if (!asce_id) { 
						asce_id = new_id--;
						row.setAttribute('asce_id', asce_id);
						local_copy_stat_cats_hash[ asc_id ].entries().push( new asce() );
						local_copy_stat_cat_entries[asce_id] = 
							local_copy_stat_cats_hash[ asc_id].entries()[ local_copy_stat_cats_hash[ asc_id].entries().length -1 ];
						local_copy_stat_cat_entries[asce_id].id( asce_id );
						local_copy_stat_cat_entries[asce_id].isnew('1');
						local_copy_stat_cat_entries[asce_id].stat_cat( asc_id );
						local_copy_stat_cat_entries[asce_id].owner(
							mw.G.user_ou.id()
						);
						local_copy_stat_cats_hash = convert_object_list_to_hash( local_copy_stat_cats );
					}
					local_copy_stat_cat_entries[asce_id].ischanged('1');
					local_copy_stat_cat_entries[asce_id].value( t.value );
				break;
			}
		}
	}
	var nl = document.getElementsByTagName('menulist');
	for (var i = 0; i < nl.length; i++) {
		var m = nl[i];
		var row = m.parentNode;
		var object_type = row.getAttribute('object_type');
		var asc_id = row.getAttribute('asc_id');
		var asce_id = row.getAttribute('asce_id');
		var new_flag = row.getAttribute('new');
		var original = m.getAttribute('original');

		sdump('D_LEGACY','Considering menulist: object_type = ' + object_type + ' asc_id = ' + asc_id + ' asce_id = ' + asce_id + ' original = ' + original + ' value = ' + m.value + '\n');

		if ( (original != m.value) && (m.value != null) && (m.value != undefined) ) {
			sdump('D_LEGACY',"\tWe're in...\n");
			switch(object_type) {
				case 'asc': 
					local_copy_stat_cats_hash[asc_id].ischanged('1');
					local_copy_stat_cats_hash[asc_id].owner( m.value );
				break;
				case 'asce': 
					if (asce_id) { 
						local_copy_stat_cat_entries[asce_id].ischanged('1');
						local_copy_stat_cat_entries[asce_id].owner( m.value );
					} else {
						sdump('D_LEGACY','\tbut nothing to do.\n');
					}
				break;
			}
		}
	}

	var nl = document.getElementsByTagName('checkbox');
	for (var i = 0; i < nl.length; i++) {
		var c = nl[i];
		var row = c.parentNode;
		var object_type = row.getAttribute('object_type');
		var asc_id = row.getAttribute('asc_id');
		var asce_id = row.getAttribute('asce_id');
		var new_flag = row.getAttribute('new');
		var delete_flag = c.getAttribute('delete');
		if (delete_flag == 'true') { delete_flag = true; }
		else if (delete_flag == 'false') { delete_flag = false; }
		var original = c.getAttribute('original');
		if (original == 'true') { original = true; }
		else if (original == 'false' ) { original = false; }

		sdump('D_LEGACY','Considering checkbox: object_type = ' + object_type + ' asc_id = ' + asc_id + ' asce_id = ' + asce_id + ' original = ' + original + ' checked = ' + m.checked + ' delete_flag = ' + delete_flag + '\n');

		if ( (original != c.checked) && (c.checked != null) && (c.checked != undefined) ) {
			sdump('D_LEGACY',"\tWe're in...\n");
			switch(object_type) {
				case 'asc': 
					local_copy_stat_cats_hash[asc_id].ischanged('1');
					if (delete_flag) {
						local_copy_stat_cats_hash[asc_id].isdeleted('1');
					} else {
						local_copy_stat_cats_hash[asc_id].opac_visible( c.checked );
					}
				break;
				case 'asce': 
					if (asce_id) {
						local_copy_stat_cat_entries[asce_id].ischanged('1');
						if (delete_flag) {
							local_copy_stat_cat_entries[asce_id].isdeleted('1');
						} else {
							// This actually doesn't exist on the asce object
							//local_copy_stat_cat_entries[asce_id].opac_visible( c.checked );
						}
					} else {
						sdump('D_LEGACY',"\tBut nothing to do.\n");
					}
				break;
			}
		}
	}

	sdump('D_LEGACY','local_copy_stat_cats = ' + js2JSON(local_copy_stat_cats) + '\n');

	// fieldmapper
	sdump('D_LEGACY','Creating, Updating, Deleting, Oh My...\n');
	for (var i = 0; i < local_copy_stat_cats.length; i++) {
		var copy_stat_cat = local_copy_stat_cats[i];
		sdump('D_LEGACY','Considering copy_stat_cat = ' + js2JSON(copy_stat_cat) + '\n');

		if ( (copy_stat_cat.name() == undefined) || (copy_stat_cat.name() == null) 
			|| (copy_stat_cat.name() == '') ) continue; 
		if ( copy_stat_cat.isnew() == '1' ) {
		// This will handle copy_stat_cat and and it's entries
			try {
				if ( copy_stat_cat.isdeleted() != '1') {
					var r1 = mw.user_request(
						'open-ils.circ',
						'open-ils.circ.stat_cat.asset.create',
						[ mw.G.auth_ses[0], copy_stat_cat ]
					)[0];
					sdump('D_LEGACY','r1 = ' + js2JSON(r1) + '\n');
				}
			} catch(E) {
				mw.handle_error(E);
			}

		} else {
		// We will also need to loop through the entries

			if ( (copy_stat_cat.ischanged() == '1') || (copy_stat_cat.isdeleted() == '1') ) {
				try {
					if (copy_stat_cat.isdeleted() == '1') {
						var r2 = mw.user_request(
							'open-ils.circ',
							'open-ils.circ.stat_cat.asset.delete',
							[ mw.G.auth_ses[0], copy_stat_cat ]
						)[0];
						sdump('D_LEGACY','r2 = ' + js2JSON(r2) + '\n');
					} else {
						var r2 = mw.user_request(
							'open-ils.circ',
							'open-ils.circ.stat_cat.asset.update',
							[ mw.G.auth_ses[0], copy_stat_cat ]
						)[0];
						sdump('D_LEGACY','r2 = ' + js2JSON(r2) + '\n');
					}
				} catch(E) {
					mw.handle_error(E);
				}
			}
			if (copy_stat_cat.isdeleted() != '1')
			for (var j = 0; j < copy_stat_cat.entries().length; j++) {
				var stat_entry = copy_stat_cat.entries()[j];
				sdump('D_LEGACY','\tConsidering stat_entry = ' + js2JSON(stat_entry) + '\n');

				if (stat_entry.isnew() == '1') {
					if (stat_entry.isdeleted() != '1') {			
						var r3 = mw.user_request(
							'open-ils.circ',
							'open-ils.circ.stat_cat.asset.entry.create',
							[ mw.G.auth_ses[0], stat_entry ]
						);
						sdump('D_LEGACY','r3 = ' + js2JSON(r3) + '\n');
					}
				} else if (stat_entry.isdeleted() == '1') {

					var r3 = mw.user_request(
						'open-ils.circ',
						'open-ils.circ.stat_cat.asset.entry.delete',
						[ mw.G.auth_ses[0], stat_entry ]
					);
					sdump('D_LEGACY','r3 = ' + js2JSON(r3) + '\n');

				} else {

					var r3 = mw.user_request(
						'open-ils.circ',
						'open-ils.circ.stat_cat.asset.entry.update',
						[ mw.G.auth_ses[0], stat_entry ]
					);
					sdump('D_LEGACY','r3 = ' + js2JSON(r3) + '\n');

				}

			}

		}
	}

	sdump('D_LEGACY','\n\n\n=-=-=-=-=-=-=-=-=\n\n\n');

	local_copy_stat_cat_entries = {};
	local_copy_stat_cats = [];
	local_copy_stat_cats_hash = {};
	sdump('D_LEGACY','Successfully updated the Stat Cats\n');
	alert('Successfully updated the Stat Cats\n');
	populate_local_copy_stat_cats(
		'copy_stat_cat_grid',
		map_list(mw.G.my_orgs, function (obj) { return obj.id(); })
	);
	document.getElementById('copy_stat_cat_new').disabled = false;
}

function new_copy_stat_cat(ev) {
	ev.target.disabled = true;
	var n_asc = new asc();
	n_asc.isnew( '1' );
	n_asc.id( new_id-- );
	n_asc.owner( mw.G.user_ou.id() );
	n_asc.entries( [] );
	local_copy_stat_cats.push( n_asc );
	local_copy_stat_cats_hash = convert_object_list_to_hash( local_copy_stat_cats );
	populate_local_copy_stat_cats_grid('copy_stat_cat_grid');
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// PATRON

function populate_local_patron_stat_cats(grid,libs) {
	sdump('D_LEGACY','populate_local_patron_stat_cats: pertinent libs = ' + js2JSON(libs) + '\n');

	try {
		local_patron_stat_cats = mw.user_request(
			'open-ils.circ',
			'open-ils.circ.stat_cat.actor.retrieve.all',
			[ mw.G.auth_ses[0] ]
		);
		//sdump('D_LEGACY','1: local_patron_stat_cats = ' + js2JSON(local_patron_stat_cats) + '\n');
		local_patron_stat_cats = local_patron_stat_cats[0];
		//sdump('D_LEGACY','2: local_patron_stat_cats = ' + js2JSON(local_patron_stat_cats) + '\n');
		local_patron_stat_cats_hash = convert_object_list_to_hash( local_patron_stat_cats );
	} catch(E) {
		mw.handle_error(E);
	}
	populate_local_patron_stat_cats_grid(grid);
}

function populate_local_patron_stat_cats_grid(grid) {

	sdump('D_LEGACY','local_patron_stat_cats = ' + pretty_print( js2JSON( local_patron_stat_cats ) ) + '\n');

	if (typeof(grid) != 'object') { grid = document.getElementById(grid); }
	var rows = grid.getElementsByTagName('rows')[0];
	empty_widget(rows);

	var row0 = document.createElement('row');
	rows.appendChild(row0);
	row0.appendChild( document.createElement('label') );
	row0.appendChild( document.createElement('label') );
	var delete_label = document.createElement('label');
	row0.appendChild( delete_label );
		delete_label.setAttribute('value','Delete');
	var owner_label = document.createElement('label');
	row0.appendChild( owner_label );
		owner_label.setAttribute('value','Owner');

	for (var i in local_patron_stat_cats) {
		//sdump('D_LEGACY','local_patron_stat_cats['+i+'] = '+local_patron_stat_cats[i]+' ; typeof = '+typeof(local_patron_stat_cats[i]) + '\n');

		var patron_stat_cat = local_patron_stat_cats[i];

		var row1 = document.createElement('row'); 
		rows.appendChild(row1);
		row1.setAttribute('actsc_id',patron_stat_cat.id());
		row1.setAttribute('object_type','actsc');
		add_css_class(row1,'row' + i % 2);

			var label1 = document.createElement('label'); 
			row1.appendChild(label1);
			label1.setAttribute('value','Statistical Category:');

			if ( find_ou( mw.G.user_ou,patron_stat_cat.owner() ) ) {
				var textbox1 = document.createElement('textbox');
				row1.appendChild(textbox1);
				textbox1.value = patron_stat_cat.name();
				textbox1.setAttribute('original',textbox1.value);
	
				var checkbox1 = document.createElement('checkbox');
				row1.appendChild(checkbox1);
				checkbox1.setAttribute('delete','true');

				var menulist1 = document.createElement('menulist');
				row1.appendChild(menulist1);
				menulist1.setAttribute('original',patron_stat_cat.owner());
	
					var menupopup1 = document.createElement('menupopup');
					menulist1.appendChild(menupopup1);
					//sdump('D_LEGACY','About to populate with patron_stat_cat.owner() = ' + patron_stat_cat.owner() + '\n');
					populate_lib_list_with_branch(menulist1,menupopup1,patron_stat_cat.owner(),mw.G.user_ou);
			} else {

				var label1a = document.createElement('label');
				row1.appendChild(label1a);
				label1a.setAttribute('value',patron_stat_cat.name() );

				row1.appendChild( document.createElement('label') );

				var label1c = document.createElement('label');
				row1.appendChild(label1c);
				label1c.setAttribute( 'value',mw.G.org_tree_hash[patron_stat_cat.owner()].name() );
			}

		var row2 = document.createElement('row'); 
		rows.appendChild(row2);
		row2.setAttribute('actsc_id',patron_stat_cat.id());
		row2.setAttribute('object_type','actsc');
		add_css_class(row2,'row' + i % 2);

			var label2 = document.createElement('label');
			row2.appendChild(label2);
			label2.setAttribute('value','OPAC Visible');

			if ( find_ou( mw.G.user_ou,patron_stat_cat.owner() ) ) {
				var checkbox2 = document.createElement('checkbox');
				row2.appendChild(checkbox2);
				checkbox2.checked = (patron_stat_cat.opac_visible() == '1')
				checkbox2.setAttribute('original',checkbox2.checked);
			} else {
				var label2a = document.createElement('label');
				row2.appendChild(label2a);
				label2a.setAttribute('value',yesno( patron_stat_cat.opac_visible() ));
			}

		for (var j in patron_stat_cat.entries() ) {

			var stat_entry = patron_stat_cat.entries()[j];
			local_patron_stat_cat_entries[stat_entry.id()] = stat_entry;

			var row = document.createElement('row');
			rows.appendChild(row);
			row.setAttribute('actsc_id',patron_stat_cat.id());
			row.setAttribute('actsce_id',stat_entry.id());
			row.setAttribute('object_type','actsce');
			add_css_class(row,'row' + i % 2);

				var label = document.createElement('label');
				row.appendChild(label);
				label.setAttribute('value','Entry:');

				if ( find_ou( mw.G.user_ou,stat_entry.owner() ) ) {
					var textbox = document.createElement('textbox');
					row.appendChild(textbox);
					textbox.value = stat_entry.value();
					textbox.setAttribute('original',textbox.value);

					var checkbox = document.createElement('checkbox');
					row.appendChild(checkbox);
					checkbox.setAttribute('delete','true');

					var menulist = document.createElement('menulist');
					row.appendChild(menulist);
					menulist.setAttribute('original',stat_entry.owner());

						var menupopup = document.createElement('menupopup');
						menulist.appendChild(menupopup);
						//sdump('D_LEGACY','About to populate with stat_entry.owner() = ' + stat_entry.owner() + '\n');
						populate_lib_list_with_branch(menulist,menupopup,stat_entry.owner(),mw.G.user_ou);
				} else {

					var labela = document.createElement('label');
					row.appendChild(labela);
					labela.setAttribute('value',stat_entry.value());

					row.appendChild( document.createElement('label') );

					var labelc = document.createElement('label');
					row.appendChild(labelc);
					labelc.setAttribute( 'value',mw.G.org_tree_hash[stat_entry.owner()].name() );
				}
		}

		var row3 = document.createElement('row');
		rows.appendChild(row3);
		row3.setAttribute('actsc_id',patron_stat_cat.id());
		row3.setAttribute('object_type','actsce');
		row3.setAttribute('new','true');
		add_css_class(row3,'row' + i % 2);

			var label3 = document.createElement('label');
			row3.appendChild(label3);
			label3.setAttribute('value','New Entry:');

			var textbox3 = document.createElement('textbox');
			row3.appendChild(textbox3);
			textbox3.setAttribute('original','');
			textbox3.addEventListener(
				'change',
				new_entry_listener,
				false
			);

			var checkbox3 = document.createElement('checkbox');
			row3.appendChild(checkbox3);
			checkbox3.setAttribute('delete','true');

			var menulist3 = document.createElement('menulist');
			row3.appendChild(menulist3);
			menulist3.setAttribute('original',mw.G.user_ou.id());

				var menupopup3 = document.createElement('menupopup');
				menulist3.appendChild(menupopup3);
				//sdump('D_LEGACY','About to populate with mw.G.user_ou\n');
				populate_lib_list_with_branch(menulist3,menupopup3,mw.G.user_ou,mw.G.user_ou);

		var row4 = document.createElement('row');
		rows.appendChild(row4);
		add_css_class(row4,'row' + i % 2);

			var label4 = document.createElement('label');
			row4.appendChild(label4);
			label4.setAttribute('value',' ');
			
		var row5 = document.createElement('row');
		rows.appendChild(row5);

			var label5 = document.createElement('label');
			row5.appendChild(label5);
			label5.setAttribute('value',' ');

	}

	var row6 = document.createElement('row');
	rows.appendChild(row6);

		var label6 = document.createElement('label');
		row6.appendChild(label6);
		label6.setAttribute('value',' ');
	
	sdump('D_LEGACY','local_patron_stat_cat_entries = ' + pretty_print( js2JSON( local_patron_stat_cat_entries ) ) + '\n');
}

function save_patron_changes() {

	// XUL

	var nl = document.getElementsByTagName('textbox');
	for (var i = 0; i < nl.length; i++) {
		var t = nl[i];
		var row = t.parentNode;
		var object_type = row.getAttribute('object_type');
		var actsc_id = row.getAttribute('actsc_id');
		var actsce_id = row.getAttribute('actsce_id');
		var new_flag = row.getAttribute('new');
		var original = t.getAttribute('original');
		sdump('D_LEGACY','Considering textbox: object_type = ' + object_type + ' actsc_id = ' + actsc_id + ' actsce_id = ' + actsce_id + ' original = ' + original + ' value = ' + t.value + '\n');

		if ( (original != t.value) && (t.value != null) && (t.value != undefined) ) {
			sdump('D_LEGACY',"\tWe're in...\n");
			switch(object_type) {
				case 'actsc': 
					local_patron_stat_cats_hash[actsc_id].ischanged('1');
					local_patron_stat_cats_hash[actsc_id].name( t.value );
				break;
				case 'actsce': 
					if (!actsce_id) { 
						actsce_id = new_id--;
						row.setAttribute('actsce_id', actsce_id);
						local_patron_stat_cats_hash[ actsc_id ].entries().push( new actsce() );
						local_patron_stat_cat_entries[actsce_id] = 
							local_patron_stat_cats_hash[ actsc_id].entries()[ local_patron_stat_cats_hash[ actsc_id].entries().length -1 ];
						local_patron_stat_cat_entries[actsce_id].id( actsce_id );
						local_patron_stat_cat_entries[actsce_id].isnew('1');
						local_patron_stat_cat_entries[actsce_id].stat_cat( actsc_id );
						local_patron_stat_cat_entries[actsce_id].owner(
							mw.G.user_ou.id()
						);
						local_patron_stat_cats_hash = convert_object_list_to_hash( local_patron_stat_cats );
					}
					local_patron_stat_cat_entries[actsce_id].ischanged('1');
					local_patron_stat_cat_entries[actsce_id].value( t.value );
				break;
			}
		}
	}
	var nl = document.getElementsByTagName('menulist');
	for (var i = 0; i < nl.length; i++) {
		var m = nl[i];
		var row = m.parentNode;
		var object_type = row.getAttribute('object_type');
		var actsc_id = row.getAttribute('actsc_id');
		var actsce_id = row.getAttribute('actsce_id');
		var new_flag = row.getAttribute('new');
		var original = m.getAttribute('original');

		sdump('D_LEGACY','Considering menulist: object_type = ' + object_type + ' actsc_id = ' + actsc_id + ' actsce_id = ' + actsce_id + ' original = ' + original + ' value = ' + m.value + '\n');

		if ( (original != m.value) && (m.value != null) && (m.value != undefined) ) {
			sdump('D_LEGACY',"\tWe're in...\n");
			switch(object_type) {
				case 'actsc': 
					local_patron_stat_cats_hash[actsc_id].ischanged('1');
					local_patron_stat_cats_hash[actsc_id].owner( m.value );
				break;
				case 'actsce': 
					if (actsce_id) { 
						local_patron_stat_cat_entries[actsce_id].ischanged('1');
						local_patron_stat_cat_entries[actsce_id].owner( m.value );
					} else {
						sdump('D_LEGACY','\tbut nothing to do.\n');
					}
				break;
			}
		}
	}

	var nl = document.getElementsByTagName('checkbox');
	for (var i = 0; i < nl.length; i++) {
		var c = nl[i];
		var row = c.parentNode;
		var object_type = row.getAttribute('object_type');
		var actsc_id = row.getAttribute('actsc_id');
		var actsce_id = row.getAttribute('actsce_id');
		var new_flag = row.getAttribute('new');
		var delete_flag = c.getAttribute('delete');
		if (delete_flag == 'true') { delete_flag = true; }
		else if (delete_flag == 'false') { delete_flag = false; }
		var original = c.getAttribute('original');
		if (original == 'true') { original = true; }
		else if (original == 'false' ) { original = false; }

		sdump('D_LEGACY','Considering checkbox: object_type = ' + object_type + ' actsc_id = ' + actsc_id + ' actsce_id = ' + actsce_id + ' original = ' + original + ' checked = ' + m.checked + ' delete_flag = ' + delete_flag + '\n');

		if ( (original != c.checked) && (c.checked != null) && (c.checked != undefined) ) {
			sdump('D_LEGACY',"\tWe're in...\n");
			switch(object_type) {
				case 'actsc': 
					local_patron_stat_cats_hash[actsc_id].ischanged('1');
					if (delete_flag) {
						local_patron_stat_cats_hash[actsc_id].isdeleted('1');
					} else {
						local_patron_stat_cats_hash[actsc_id].opac_visible( c.checked );
					}
				break;
				case 'actsce': 
					if (actsce_id) {
						local_patron_stat_cat_entries[actsce_id].ischanged('1');
						if (delete_flag) {
							local_patron_stat_cat_entries[actsce_id].isdeleted('1');
						} else {
							// This actually doesn't exist on the actsce object
							//local_patron_stat_cat_entries[actsce_id].opac_visible( c.checked );
						}
					} else {
						sdump('D_LEGACY',"\tBut nothing to do.\n");
					}
				break;
			}
		}
	}

	sdump('D_LEGACY','local_patron_stat_cats = ' + js2JSON(local_patron_stat_cats) + '\n');

	// fieldmapper
	sdump('D_LEGACY','Creating, Updating, Deleting, Oh My...\n');
	for (var i = 0; i < local_patron_stat_cats.length; i++) {
		var patron_stat_cat = local_patron_stat_cats[i];
		sdump('D_LEGACY','Considering patron_stat_cat = ' + js2JSON(patron_stat_cat) + '\n');

		if ( (patron_stat_cat.name() == undefined) || (patron_stat_cat.name() == null) 
			|| (patron_stat_cat.name() == '') ) continue; 
		if ( patron_stat_cat.isnew() == '1' ) {
		// This will handle patron_stat_cat and and it's entries
			try {
				if ( patron_stat_cat.isdeleted() != '1' ) {
					var r1 = mw.user_request(
						'open-ils.circ',
						'open-ils.circ.stat_cat.actor.create',
						[ mw.G.auth_ses[0], patron_stat_cat ]
					)[0];
					sdump('D_LEGACY','r1 = ' + js2JSON(r1) + '\n');
				}
			} catch(E) {
				mw.handle_error(E);
			}

		} else {
		// We will also need to loop through the entries

			if ( (patron_stat_cat.ischanged() == '1') || (patron_stat_cat.isdeleted() == '1') ) {
				try {
					if (patron_stat_cat.isdeleted() == '1') {
						var r2 = mw.user_request(
							'open-ils.circ',
							'open-ils.circ.stat_cat.actor.delete',
							[ mw.G.auth_ses[0], patron_stat_cat ]
						)[0];
						sdump('D_LEGACY','r2 = ' + js2JSON(r2) + '\n');
					} else {
						var r2 = mw.user_request(
							'open-ils.circ',
							'open-ils.circ.stat_cat.actor.update',
							[ mw.G.auth_ses[0], patron_stat_cat ]
						)[0];
						sdump('D_LEGACY','r2 = ' + js2JSON(r2) + '\n');

					}
				} catch(E) {
					mw.handle_error(E);
				}
			}
			if (patron_stat_cat.isdeleted() != '1')
			for (var j = 0; j < patron_stat_cat.entries().length; j++) {
				var stat_entry = patron_stat_cat.entries()[j];
				sdump('D_LEGACY','\tConsidering stat_entry = ' + js2JSON(stat_entry) + '\n');

				if (stat_entry.isnew() == '1') {
					if (stat_entry.isdeleted() != '1') {			
						var r3 = mw.user_request(
							'open-ils.circ',
							'open-ils.circ.stat_cat.actor.entry.create',
							[ mw.G.auth_ses[0], stat_entry ]
						);
						sdump('D_LEGACY','r3 = ' + js2JSON(r3) + '\n');
					}
				} else if (stat_entry.isdeleted() == '1') {

					var r3 = mw.user_request(
						'open-ils.circ',
						'open-ils.circ.stat_cat.actor.entry.delete',
						[ mw.G.auth_ses[0], stat_entry ]
					);
					sdump('D_LEGACY','r3 = ' + js2JSON(r3) + '\n');
			
				} else {

					var r3 = mw.user_request(
						'open-ils.circ',
						'open-ils.circ.stat_cat.actor.entry.update',
						[ mw.G.auth_ses[0], stat_entry ]
					);
					sdump('D_LEGACY','r3 = ' + js2JSON(r3) + '\n');

				}

			}

		}
	}

	sdump('D_LEGACY','\n\n\n=-=-=-=-=-=-=-=-=\n\n\n');

	local_patron_stat_cat_entries = {};
	local_patron_stat_cats = [];
	local_patron_stat_cats_hash = {};
	sdump('D_LEGACY','Successfully updated the Stat Cats\n');
	alert('Successfully updated the Stat Cats\n');
	populate_local_patron_stat_cats(
		'patron_stat_cat_grid',
		map_list(mw.G.my_orgs, function (obj) { return obj.id(); })
	);
	document.getElementById('patron_stat_cat_new').disabled = false;
}

function new_patron_stat_cat(ev) {
	ev.target.disabled = true;
	var n_actsc = new actsc();
	n_actsc.isnew( '1' );
	n_actsc.id( new_id-- );
	n_actsc.owner( mw.G.user_ou.id() );
	n_actsc.entries( [] );
	local_patron_stat_cats.push( n_actsc );
	local_patron_stat_cats_hash = convert_object_list_to_hash( local_patron_stat_cats );
	populate_local_patron_stat_cats_grid('patron_stat_cat_grid');
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// GENERIC
