var data = {}; var data_backup; var cn_list = [];
var new_id = -1;

function my_init() {
	mw.sdump('D_CAT','entering my_init for volume.js\n');
	mw.sdump('D_CAT','TESTING: volume.js: ' + mw.G['main_test_variable'] + '\n');
	mw.sdump('D_CAT','record_id = ' + record_id + '\n');
	mw.sdump('D_CAT','tree_items: ' + tree_items + '\n');
	if (params.shortcut == 'volume_add') {
		build_page_one();
	} else if (params.shortcut == 'copy_add') {
		build_page_two();
	} else {
		mw.sdump('D_CAT','broken\n');
	}
	listen_for_enter('volume_add');
	mw.sdump('D_CAT','exiting my_init for volume.js\n');
}

function listen_for_enter(w) {
	if (typeof(w) != 'object') {
		w = document.getElementById(w);
	}
	w.addEventListener('keypress',
		function (ev) {
			mw.sdump('D_CAT','wizard: ev.target.tagName = ' + ev.target.tagName + '\n');
			mw.sdump('D_CAT','\tev.keyCode = ' + ev.keyCode + '\n');
			mw.sdump('D_CAT','\tev.charCode = ' + ev.charCode + '\n');
			if ((ev.target.tagName == 'textbox') && (ev.keyCode == 13)) {
				ev.preventDefault();
				ev.stopPropagation(); // XBL bindings? bleh
				fake_tab_for_textboxes(w,ev.target);
				return true;
			}
		},
		true
	);
}

function page1_add_volume_row(ou) {
	var row = document.createElement('row');
		row.setAttribute('id','p1_' + ou.id());
	document.getElementById('page1_rows').appendChild(row);
	var label = document.createElement('label');
		label.setAttribute('value',ou.name());
	row.appendChild(label);
	var textbox = document.createElement('textbox');
		textbox.setAttribute('size','1');
		textbox.setAttribute('value','0');
	row.appendChild(textbox);
}

function page2_add_volume_row(ou,ti) {
	mw.sdump('D_CAT','page2_add_volume_row...\n');
	var desired_volumes = 
		document.getElementById('p1_' + ou.id()).lastChild.value;
	mw.sdump('D_CAT','ou = ' + ou.name() + '  desired = ' + desired_volumes + '\n');
	if (desired_volumes > 0) { } else { return; }
	var rows = document.getElementById('page2_rows');
	var row = document.createElement('row');
	rows.appendChild(row);
	var label = document.createElement('label');
		label.setAttribute('value',ou.name());
	row.appendChild(label);
	for (var i = 0; i < desired_volumes; i++) {
		var cn_row = document.createElement('row');
			//cn_row.setAttribute('id','p2_'+ou.id());
			cn_row.setAttribute('ou_name',ou.name());
			cn_row.setAttribute('ou_id',ou.id());
		rows.appendChild(cn_row);
		cn_row.appendChild( document.createElement('label') );
		var cn_text1 = document.createElement('textbox');
			cn_text1.setAttribute('size','20');
			cn_text1.setAttribute('value','A Call Number');
		cn_row.appendChild( cn_text1 );
		var cn_text2 = document.createElement('textbox');
			cn_text2.setAttribute('size','4');
			cn_text2.setAttribute('value','0');
		cn_row.appendChild( cn_text2 );
	}
}

function copy_add_page2_add_volume_row(ou,ti) {
	mw.sdump('D_CAT','copy_add_page2_add_volume_row...\n');
	var rows = document.getElementById('page2_rows');
	var row = document.getElementById('page2_row_cn_' + ou.id() );
	if (!row) {
		row = document.createElement('row');
		row.setAttribute('id','page2_row_cn' + ou.id() );
		rows.appendChild(row);
	}
	var label = document.createElement('label');
		label.setAttribute('value',ou.name());
	row.appendChild(label);
		var cn_row = document.createElement('row');
			//cn_row.setAttribute('id','p2_'+ou.id());
			cn_row.setAttribute('ou_name',ou.name());
			cn_row.setAttribute('ou_id',ou.id());
			cn_row.setAttribute('volume_id',ti.getAttribute('volume_id'));
		rows.appendChild(cn_row);
		cn_row.appendChild( document.createElement('label') );
		var cn_text1 = document.createElement('textbox');
			cn_text1.setAttribute('size','20');
			cn_text1.setAttribute('volume_id',ti.getAttribute('volume_id'));
			cn_text1.setAttribute('value',ti.getAttribute('callnumber'));
		cn_row.appendChild( cn_text1 );
		cn_text1.disabled = true;
		var cn_text2 = document.createElement('textbox');
			cn_text2.setAttribute('size','4');
			cn_text2.setAttribute('value','0');
		cn_row.appendChild( cn_text2 );
}

function page3_add_volume_row(id,data) {
	if (data.length>0) { } else { return; }
	var rows = document.getElementById('page3_rows');
	var org_row = document.createElement('row');
	rows.appendChild(org_row);
		var org_label = document.createElement('label');
			org_label.setAttribute('value',data[0].name);
		org_row.appendChild(org_label);
	for (var i in data) {
		var callnumber = data[i].callnumber;
		var desired_copies = data[i].copies;
		var cn_row = document.createElement('row');
		rows.appendChild(cn_row);
		var cn_box = document.createElement('hbox');
		cn_row.appendChild(cn_box);
		cn_box.appendChild( document.createElement('spacer') );
		var cn_label = document.createElement('label');
			cn_label.setAttribute('value',callnumber);
		cn_box.appendChild(cn_label);
		for (var c = 0; c < desired_copies; c++) {
			var bc_row = document.createElement('row');
			rows.appendChild(bc_row);
			bc_row.appendChild( document.createElement('label') );
			var bc_text = document.createElement('textbox');
				bc_text.setAttribute('size','15');
				bc_text.setAttribute('ou_name',data[i].name);
				bc_text.setAttribute('ou_id',id);
				bc_text.setAttribute('volume_id',data[i].volume_id);
				bc_text.setAttribute('callnumber',callnumber);
			bc_row.appendChild(bc_text);
		}
	}
}

function page_four_add_volume_row(name,callnumber,barcode) {
	mw.sdump('D_CAT','xul: name = ' + name + ' cn = ' + callnumber + ' bc = ' + barcode + '\n');
	var listbox = document.getElementById('ephemeral_listbox');
	var listitem = document.createElement('listitem');
	listbox.appendChild(listitem);
	var listcell1 = document.createElement('listcell');
		listcell1.setAttribute('label',name);
	listitem.appendChild(listcell1);
	var listcell2 = document.createElement('listcell');
		listcell2.setAttribute('label',callnumber);
	listitem.appendChild(listcell2);
	var listcell3 = document.createElement('listcell');
		listcell3.setAttribute('label',barcode);
	listitem.appendChild(listcell3);

}

function build_page_one() {
	mw.sdump('D_CAT','build_page_one\n');
	for (var i in tree_items) {
		var ti = tree_items[i];
		switch( ti.getAttribute('object_type') ) {
			case 'org_unit' :
				if (params.shortcut == 'volume_add') {
					var shortname = ti.getAttribute('id').split('_')[2];
					var ou = find_ou_by_shortname(mw.G['org_tree'],shortname);
					var check_ou = check_volume_ou_perm( shortname );
					if ( check_ou ) {
						page1_add_volume_row( check_ou );
					}
				}
			break;
		}
	}
}

function build_page_two() {
	mw.sdump('D_CAT','build_page_two\n');
	for (var i in tree_items) {
		var ti = tree_items[i];
		mw.sdump('D_CAT','Considering item with object_type = ' + ti.getAttribute('object_type') + '\n');
		switch( ti.getAttribute('object_type') ) {
			case 'org_unit' :
				var shortname = ti.getAttribute('id').split('_')[2];
				var ou = find_ou_by_shortname(mw.G['org_tree'],shortname);
				var check_ou = check_volume_ou_perm( shortname );
				if ( check_ou ) {
					page2_add_volume_row( check_ou, ti );
				}
			break;
			case 'volume' :
				if (params.shortcut == 'copy_add') {
					var check_ou = find_ou( mw.G.user_ou , ti.getAttribute('ou_id') );
					if (check_ou) {
						copy_add_page2_add_volume_row( check_ou, ti );	
					}
				}
			break;
		}
	}
}

function build_page_three() {
	mw.sdump('D_CAT','build_page_three\n');
	var rows = document.getElementById('page2_rows');
	for (var i = 0; i < rows.childNodes.length; i++) {
		var row = rows.childNodes[i];
		mw.sdump('D_CAT',row + '\n');
		var ou_id = row.getAttribute('ou_id');
		var ou_name = row.getAttribute('ou_name');
		var volume_id = row.getAttribute('volume_id');
		if (ou_id) {
			var call_number = row.childNodes[1].value;
			if (!call_number) { continue; }
			var desired_copies = row.childNodes[2].value;
			if (!data[ou_id]) { data[ou_id] = []; }
			data[ou_id].push( 
				{ 
					'callnumber' : call_number, 
					'copies' : desired_copies,
					'name' : ou_name,
					'volume_id' : volume_id
				} 
			);
		}
	}
	for (var i in data) {
		mw.sdump('D_CAT','i: ' + i + ' data[i]: ' + js2JSON(data[i]) + '\n');
		page3_add_volume_row( i, data[i]);
	}
}

function build_page_four() {
	mw.sdump('D_CAT','build page four\n');
	document.getElementById('volume_add').canAdvance = false;
	var new_data = [];
	var rows = document.getElementById('page3_rows');
	var nl = rows.getElementsByTagName('textbox');
        for (var i in nl) {
                if (typeof(nl[i])=='object') {
                        var t = nl[i];
                        var ou_id = t.getAttribute('ou_id');
                        var ou_name = t.getAttribute('ou_name');
                        var callnumber = t.getAttribute('callnumber');
			var volume_id = t.getAttribute('volume_id');
                        var barcode = t.value;
			//page_four_add_volume_row(ou_name,callnumber,barcode);
			mw.sdump('D_CAT','t.tagName = ' + t.tagName + ' ou_id = ' + ou_id + ' cn = ' + callnumber + ' volume_id = ' + volume_id + ' bc = ' + barcode + '\n');
			if (! new_data[ou_id] ) { new_data[ou_id] = {}; }
			if (! new_data[ou_id][callnumber] ) {
				new_data[ou_id][callnumber] = [];
			}
			if (! new_data[ou_id][callnumber]['barcode'] ) {
				new_data[ou_id][callnumber]['barcode'] = [];
			}
			new_data[ou_id][callnumber].barcode.push(barcode);
			if (params.shortcut == 'copy_add') {
				new_data[ou_id][callnumber].volume_id = volume_id;
			}
                }
        }
	cn_list = [];
	for (var ou_id in new_data) {
		for (var cnum in new_data[ou_id]) {
			//var ou_shortname = find_ou(mw.G['org_tree'],ou_id).shortname();
			var ou_shortname = mw.G.org_tree_hash[ou_id].shortname();
			var cn = new acn();
			cn.label(cnum);
			cn.owning_lib(ou_id);
			cn.record(record_id);
			if (params.shortcut == 'volume_add') {
				cn.isnew(1);
				cn.id(new_id--);
			} else if (params.shortcut == 'copy_add') {
				cn.id( new_data[ou_id][cnum].volume_id );
			}
			cn.copies([]);
	
			for (var c in new_data[ou_id][cnum].barcode) {
				var cp = new acp();
				cp.id(new_id--);
				cp.isnew(1);
				cp.barcode(new_data[ou_id][cnum].barcode[c]);
				cp.circ_lib(	mw.G.org_tree_hash[ ou_id ]);
				cn.copies().push(cp);
				cp.stat_cat_entries( [] );
			}

			cn_list.push(cn);
		}
	}
	mw.sdump('D_CAT','Final data object: ' + js2JSON(cn_list) + '\n');
	mw.sdump('D_CAT','Final data object: ' + cn_list + '\n');
	spawn_local_legacy_copy_editor();
}

function send_to_bill() {
	try {
		var result = user_request(
				'open-ils.cat',
				'open-ils.cat.asset.volume_tree.fleshed.batch.update',
				[ mw.G['auth_ses'][0], cn_list]
		);
		mw.sdump('D_CAT','volume_tree.fleshed.batch.update result: ' + js2JSON(result) + '\n');
	} catch(E) {
		handle_error(E);
	}
	refresh_spawning_browse_list();
}

function refresh_spawning_browse_list() {
	try {
		params.refresh_func();
	} catch(E) {
		mw.sdump('D_CAT','refresh_spawning_browse_list error: ' + js2JSON(E) + '\n');
	}
}

function spawn_local_legacy_copy_editor(tab) {
	mw.sdump('D_CAT','trying to spawn_copy_editor()\n');
	var params = { 'select_all' : true };
	var chrome = 'chrome://evergreen/content/cat/copy.xul';
	var frame = document.getElementById('page4_iframe');
	frame.setAttribute('src',chrome);
	frame.setAttribute('flex','1');
	frame.contentWindow.cn_list = cn_list;
	frame.contentWindow.mw = mw;
	frame.contentWindow.real_parentWindow = this;
	frame.contentWindow.parentWindow = window.app_shell;
	frame.contentWindow.params = params;
}

function backup_data() {
	data_backup = data;
}

function restore_data() {
	data = data_backup;
}

function check_volume_ou_perm(shortname) {
	var top_ou = find_ou(mw.G['org_tree'],mw.G.user_ou.id());
	var check_ou = find_ou_by_shortname(top_ou, shortname);
	return check_ou;
}

// ***************************************************** Batch Volume Edit

function volume_edit_init() {
	mw.sdump('D_CAT','TESTING: volume.js: ' + mw.G['main_test_variable'] + '\n');
	build_batch_edit_page1();
	listen_for_enter('volume_edit');
}

function build_batch_edit_page1() {
	var rows = document.getElementById('page1_rows');

	var org = {};

	for (var i = 0; i < tree_items.length; i++) {
		var volume = tree_items[i];
		if (!  org[ volume.getAttribute('ou_id') ] ) {
			org[ volume.getAttribute('ou_id') ] = new Array();
		}
		org[ volume.getAttribute('ou_id') ].push( volume );
	}

	for (var i in org) {
		var row = document.createElement('row');
		rows.appendChild(row);
		var lib = document.createElement('label');
		row.appendChild(lib);
			lib.setAttribute( 'value', mw.G.org_tree_hash[i].shortname() );

		for (var j = 0; j < org[i].length; j++) {
			var volume = org[i][j];

			var vrow = document.createElement('row');
			rows.appendChild(vrow);
			vrow.appendChild( document.createElement('label') );

			var t = document.createElement('textbox');
			vrow.appendChild( t );
			t.value = volume.getAttribute('callnumber');
			t.setAttribute( 'original', volume.getAttribute('callnumber') );
			t.setAttribute( 'volume_id', volume.getAttribute('volume_id') );
		}
	}
}

function submit_edited_volumes() {
	var nl = document.getElementsByTagName('textbox');
	for (var i = 0; i < nl.length; i++) {
		var t = nl[i];
		if (t.getAttribute('original') == t.value) continue;
		var cn = new acn();
		cn.id( t.getAttribute('volume_id') );
		cn.label( t.value );
		cn.ischanged('1');
		cn_list.push( cn );
	}
	send_to_bill();
}
