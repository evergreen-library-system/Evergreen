// find_this_id = document id

var org_shortname2id = {};
var my_treerow;
var browse_meter_per = 0;
var orgs_with_copies = [];
var orgs_with_copies_hash = {};

function my_init() {
	timer_init('cat');
	mw.sdump('D_CAT','TESTING: browse_list.js: ' + mw.G['main_test_variable'] + '\n');
	var tc = document.getElementById('browse_list_tree_children');
	build_tree_branch(tc,mw.G['org_tree'],true);
	my_treerow = document.getElementById( 'org_unit_' + mw.G.user_ou.shortname() ).firstChild;
	document.getElementById('browse_meter').value = 0;
	document.getElementById('browse_meter').setAttribute('real', '0.0');
	gather_copies();
	//populate_tree();
}

function refresh_browse_list() {
	mw.sdump('D_CAT','=-=-=-=-=-=-=-=-=\n\n\nrefresh_browse_list()\n');
	// Prune tree
	var nl = document.getElementsByTagName('treeitem');
	for (var i = 0; i < nl.length; i++) {
		var v_treeitem = nl[i];
		if (v_treeitem.getAttribute('object_type') == 'volume') {
			var org_treechildren = v_treeitem.parentNode;
			var org_treeitem = org_treechildren.parentNode;
			org_treeitem.removeChild(org_treechildren);
			var org_treerow = org_treeitem.firstChild;
			org_treerow.childNodes[1].setAttribute('label','0');
			org_treerow.childNodes[2].setAttribute('label','0');
		}
	}
	document.getElementById('browse_meter').value = 0;
	document.getElementById('browse_meter').setAttribute('real', '0.0');
	gather_copies();
}

function button_toggle_my_libraries(ev) {
	// label = Hide My Libraries
	// alt_label = Show My Libraries
	var target = document.getElementById('browse_list_button1');
	if (!target) { mw.sdump('D_CAT','eh?\n'); return; }
	swap_attributes('browse_list_button1','label','alt_label');
	var toggle = cycle_attribute( target,'toggle', [ '1', '2' ] );
	for (var i in mw.G.my_orgs) {
		var lib = mw.G.my_orgs[i];
		var item = document.getElementById('org_unit_'+lib.shortname());
		if (item) {
			if (toggle == '2') {
				hide_branch(item);
			} else {
				unhide_branch(item);
			}
		}
	}
}

function button_toggle_libraries(ev) {
	// label = Show Other Libraries With Copies
	// alt_label = Show Just My Libraries
	var target = document.getElementById('browse_list_button2');
	if (!target) { mw.sdump('D_CAT','eh?\n'); return; }
	swap_attributes('browse_list_button2','label','alt_label');
	var toggle = cycle_attribute( target,'toggle',['1','2'] );
	if (toggle == '1') {
		mw.sdump('D_CAT','Showing just my libraries...\n');
		/*hide_branch( document.getElementById('org_unit_PINES') );
		for (var i = 0; i < mw.G.my_orgs.length; i++) {
			unhide_branch(
				document.getElementById( 'org_unit_' + mw.G.my_orgs[i].shortname() )
			);
		}*/
		var nl = document.getElementsByTagName('treeitem');
		for (var i = 0; i < nl.length; i++) {
			var item = nl[i];
			if (item.getAttribute('id').substr(0,9) != 'org_unit_') continue;
			if (mw.G.my_orgs_hash[ item.getAttribute('myid') ]) {
				//item.setAttribute('hidden','false');
				unhide_branch(item);
			} else {
				//item.setAttribute('hidden','true');
				hide_branch(item);
			}
		}
	} else {
		mw.sdump('D_CAT','Showing other libraries with copies...\n');
		var nl = document.getElementsByTagName('treeitem');
		for (var i = 0; i < nl.length; i++) {
			var item = nl[i];
			if (item.getAttribute('copies') == 'true') {
				//item.setAttribute('hidden','false');
				//mw.sdump('D_CAT','\tunhiding ' + item.getAttribute('id') + '\n');
				unhide_branch(item);
			} else {
				//item.setAttribute('hidden','true');
				//mw.sdump('D_CAT','\thiding ' + item.getAttribute('id') + '\n');
				//hide_branch(item);
			}
		}

	}
}

function unhide_branch(item,do_open,do_copies) {
	if (item.getAttribute('id') == 'org_unit_PINES') { return; }
	//mw.sdump('D_CAT','Unhiding ' + item.getAttribute('id') + '\n');
	item.setAttribute('hidden','false');
	if (do_open) {
		item.setAttribute('open','true');
	}
	if (do_copies) {
		item.setAttribute('copies','true');
	}
	if (item.parentNode && item.parentNode.setAttribute) {
		var id = item.parentNode.getAttribute('id');
		if (id.substr(0,7) != 'browse_' && id != 'org_unit_PINES') {
			unhide_branch(item.parentNode,do_open,do_copies);
		}
	}
}

function hide_branch(item,do_open,do_copies) {
	if (item.getAttribute('id') == 'org_unit_PINES') { return; }
	//mw.sdump('D_CAT','Hiding ' + item.getAttribute('id') + '\n');
	item.setAttribute('hidden','true');
	if (do_open) {
		item.setAttribute('open','false');
	}
	if (do_copies) {
		item.setAttribute('copies','true');
	}
	if (item.parentNode && item.parentNode.setAttribute) {
		var id = item.parentNode.getAttribute('id');
		if (id.substr(0,7) != 'browse_' && id != 'org_unit_PINES') {
			hide_branch(item.parentNode,do_open,do_copies);
		}
	}
}

function gather_copies() {
	// loop the libs
	mw.sdump('D_CAT','Hello : ' + timer_elapsed('world') + '\n');
/*	user_async_request(
			'open-ils.cat',
			'open-ils.cat.asset.copy_tree.global.retrieve',
			[ mw.G['auth_ses'][0], find_this_id  ],
			gather_copies_callback
		);
*/
	var orgs_with_copies = user_request(
		'open-ils.cat',
		'open-ils.cat.actor.org_unit.retrieve_by_title',
		[ find_this_id ]
	)[0];
	for (var i = 0; i < orgs_with_copies.length; i++) {
		orgs_with_copies_hash[ orgs_with_copies[i] ] = true;
	}
	var bucket = new Array();
	for (var i = 0; i < mw.G.my_orgs.length; i++ ) {
		//if (find_id_object_in_list( mw.G.aout_list, mw.G.my_orgs[i].ou_type() ).can_have_vols() == '0')
		if ( mw.G.aout_list[ mw.G.my_orgs[i].ou_type() ].can_have_vols() == '0')
			continue;
		if ( ! orgs_with_copies_hash[ mw.G.my_orgs[i].id() ] ) continue;
		bucket.push( mw.G.my_orgs[i].id() );
	}
	document.getElementById('browse_libs').setAttribute('value','Retrieving my copies...');
	user_async_request(
		'open-ils.cat',
		'open-ils.cat.asset.copy_tree.retrieve',
		[ mw.G['auth_ses'][0], find_this_id, bucket ],
		function (request) {
			gather_copies_callback(request);
			document.getElementById('browse_libs').setAttribute('value','Retrieving copies from other libraries...');
			gather_other_copies();
		}
	);
	mw.sdump('D_CAT','((((((((((((((((( Count = ' + counter_incr('world') + '\n');
}

function gather_other_copies() {
	var w_s = 10; var c_s = 0;
	var bucket = new Array();

	var nl = document.getElementsByTagName('treeitem');
	for (var i = 0; i < nl.length; i++) {
		var item = nl[i];
		if (item.getAttribute('can_have_vols') == '0') continue;
		//if ( find_id_object_in_list( mw.G.my_orgs, item.getAttribute('myid') ) ) { continue; }
		if ( mw.G.my_orgs_hash[ item.getAttribute('myid') ] ) { continue; }
		if ( ! orgs_with_copies_hash[ item.getAttribute('myid') ] ) continue;
		bucket.push( item.getAttribute('myid') );
		if (++c_s >= w_s) {
			user_async_request(
				'open-ils.cat',
				'open-ils.cat.asset.copy_tree.retrieve',
				[ mw.G['auth_ses'][0], find_this_id, bucket ],
				gather_copies_callback
			);
			mw.sdump('D_CAT','((((((((((((((((( Count = ' + counter_incr('world') + '\n');
			bucket = new Array();
			c_s = 0;
		}
	}
	if (bucket.length > 0) {
		user_async_request(
			'open-ils.cat',
			'open-ils.cat.asset.copy_tree.retrieve',
			[ mw.G['auth_ses'][0], find_this_id, bucket ],
			gather_copies_callback
		);
		mw.sdump('D_CAT','((((((((((((((((( Count = ' + counter_incr('world') + '\n');
	}
	browse_meter_per = 100 / counter_peek('world');
	mw.sdump('D_CAT',timer_elapsed('world') + ' : World : ' + timer_elapsed('gather') + '\n');
}

function find_my_treerow_index() {
	var nl = document.getElementById('browse_list_tree').getElementsByTagName('treerow');
	var count = 0;
	//mw.sdump('D_CAT','find_my_treerow:  count = ' + count + '  nl.length = ' + nl.length + '\n');
	for (var i = 0; i < nl.length; i++) {
		var row = nl[i];
		var item = row.parentNode;
		if (item.getAttribute('id') == 'org_unit_' + mw.G.user_ou.shortname() ) {
			return count;
		}
		var open_attr = item.getAttribute('open');
		var hidden_prop = item.hidden;
		//mw.sdump('D_CAT','id = ' + item.getAttribute('id') + '   hidden_attr = ' + hidden_attr + '   hidden_prop = ' + hidden_prop + '\n');
		if (hidden_prop.toString() == 'false' && open_attr.toString() == 'true') {
			count++;
		}
	}
	return 0;
}

function gather_copies_callback(request) {
	mw.sdump('D_CAT','gather_copies_callback : ' + timer_elapsed('gather') + ' : ' + ' count = ' + counter_incr('gather') + '\n');
	var result = request.getResultObject();
	var n_volumes = 0; var n_copies = 0; var flag = false;
	//mw.sdump('D_CAT','copybrowser result = ' + js2JSON(result) + '\n=-=-=\n');
	for (var y in result) {
		if (result[y] && (typeof(result[y])=='object')) {
			var volume = result[y]; n_volumes++;
			//mw.sdump('D_CAT','\nvolume = ' + js2JSON(volume) + '\n');
			mw.sdump('D_CAT',' volume id = ' + volume.id() + '\n');
			var lib = find_ou( mw.G.org_tree, volume.owning_lib() );
			//mw.sdump('D_CAT','lib = ' + js2JSON(lib) + '\n');
			if ( lib.shortname() == mw.G.user_ou.shortname() ) { flag = true; }
			var callnumber = volume.label();
			var copies = volume.copies();
			//mw.sdump('D_CAT','\tcopies = ' + js2JSON(copies) + '\n');
			var item = document.getElementById('org_unit_'+lib.shortname());
			if (!item) { mw.sdump('D_CAT','skipping\n'); continue; }

			var item_row = item.firstChild;
			var volumes_treecell;
			if (item_row.childNodes.length == 1) {
				volumes_treecell = document.createElement('treecell');
				volumes_treecell.setAttribute('label','0');
				item_row.appendChild(volumes_treecell);
			} else {
				volumes_treecell = item_row.childNodes[1];
			}
			volumes_treecell.setAttribute(
				'label',
				parseInt(volumes_treecell.getAttribute('label')) + 1
			);

			var copies_treecell;
			if (item_row.childNodes.length < 3) {
				copies_treecell = document.createElement('treecell');
				copies_treecell.setAttribute('label','0');
				item_row.appendChild(copies_treecell);
			} else {
				copies_treecell = item_row.childNodes[2];
			}
			copies_treecell.setAttribute(
				'label',
				parseInt(copies_treecell.getAttribute('label')) + copies.length
			);


			var cn_treechildren;
			var nl = item.getElementsByTagName('treechildren');
			//unhide_branch(item,false,true);
			item.setAttribute('copies',true);
			if (nl.length == 0) {
				cn_treechildren = document.createElement('treechildren');
				item.appendChild(cn_treechildren);
			} else {
				cn_treechildren = nl[0];
			}

			var cn_treeitem = document.createElement('treeitem');
				cn_treeitem.setAttribute('container','true');
				cn_treeitem.setAttribute('open','true');
				cn_treeitem.setAttribute('object_type','volume');
				cn_treeitem.setAttribute('volume_id',volume.id());
				cn_treeitem.setAttribute('callnumber',volume.label());
				cn_treeitem.setAttribute('ou_id',lib.id());

			cn_treechildren.appendChild(cn_treeitem);

			var cn_treerow = document.createElement('treerow');
			cn_treeitem.appendChild(cn_treerow);

			var cn_treecell = document.createElement('treecell');
				cn_treecell.setAttribute('label',callnumber);
			cn_treerow.appendChild(cn_treecell);

			var treechildren = document.createElement('treechildren');
			cn_treeitem.appendChild(treechildren);
			//mw.sdump('D_CAT', 'org_unit_'+lib+' item = '+item.tagName+'\n');
			for (var j = 0; j < copies.length; j++) {
				var copy = copies[j]; n_copies++;
				//mw.sdump('D_CAT','barcode: ' + copy.barcode() + '\n');

				var treeitem = document.createElement('treeitem');
					treeitem.setAttribute('open','true');
					treeitem.setAttribute('container','true');
					treeitem.setAttribute('class','barcode_row');
					treeitem.setAttribute('object_type','copy');
					treeitem.setAttribute('ou_shortname',lib.shortname());
					treeitem.setAttribute('ou_id',lib.id());
					treeitem.setAttribute('callnumber',callnumber);
					treeitem.setAttribute('barcode',copy.barcode());
					treeitem.setAttribute('copy_id',copy.id());
					treeitem.setAttribute('volume_id',volume.id());
					//treeitem.setAttribute('copy',js2JSON(copy));
				treechildren.appendChild(treeitem);

				var treerow = document.createElement('treerow');
				treeitem.appendChild(treerow);

				var list = [ 
					copy.barcode() , '', '', lib.shortname() , callnumber , copy.copy_number() ,
					//find_id_object_in_list( mw.G.acpl_list, copy.location() ).name() , 
					mw.G.acpl_hash[ copy.location() ].name() ,
					//find_ou( mw.G.org_tree, copy.circ_lib() ).shortname() , 
					mw.G.org_tree_hash[ copy.circ_lib() ].shortname(),
					yesno( copy.circulate() ) , yesno( copy.ref() ) ,
					yesno( copy.opac_visible() ) , copy.circ_as_type() , copy.circ_modifier() ,
					copy.loan_duration() , copy.fine_level() , copy.create_date() ,
					copy.creator() , copy.edit_date() , copy.editor() , copy.deposit() ,
					copy.deposit_amount() , copy.price() , copy.status()
				];

				for (var i = 0; i < list.length; i++ ) {
					var treecell = document.createElement('treecell');
						treecell.setAttribute('label',list[i]);
					treerow.appendChild(treecell);
				}
						
			}
		} else {
			mw.sdump('D_CAT','gather_copies problem: ' + result[y] + '\n');
			//throw(result[0]);
		}
	}
	var tree = document.getElementById('browse_list_tree');
	if (tree.currentIndex != -1) {
		//mw.sdump('D_CAT','currentIndex != -1 = ' + tree.currentIndex + '\n');
		//tree.treeBoxObject.scrollToRow( tree.currentIndex );
		tree.treeBoxObject.ensureRowIsVisible( tree.currentIndex );
	} else if (flag) {
		//mw.sdump('D_CAT','currentIndex == -1\n');
		var find = find_my_treerow_index();
		mw.sdump('D_CAT','find = ' + find + ' n_volumes = ' + n_volumes + ' n_copies = ' + n_copies + '\n');
		//alert('find = ' + find + ' n_volumes = ' + n_volumes + ' n_copies = ' + n_copies + '\n');
		if (find > 0) { 
			find = find + n_volumes + n_copies;
			tree.view.selection.select( find ); 
		}
		//tree.treeBoxObject.ensureRowIsVisible( find );
	}
	var meter = document.getElementById('browse_meter');
	var real = parseFloat( meter.getAttribute('real') ) + browse_meter_per;
	meter.setAttribute('real',real);
	meter.value = Math.ceil( real );
	if ( counter_peek('gather') == counter_peek('world') ) {
		document.getElementById('browse_libs').setAttribute('value','Finished');
		document.getElementById('browse_libs').setAttribute('hidden','true');
		meter.value = 100;
		meter.setAttribute('hidden','true');
	}
	mw.sdump('D_CAT','gather callback   done : ' + timer_elapsed('gather') + '\n');
}


function build_tree_branch(treechildren,org,hide) {
	var id = org.id();
	var name = org.name();
	var shortname = org.shortname(); org_shortname2id[shortname] = id;
	var children = org.children();
	var flag = mw.G.aout_hash[ org.ou_type() ].can_have_vols() == '1';
	var item = make_treeitem('org_unit_' + shortname, name, flag);
	item.setAttribute('hidden',hide);
	item.setAttribute('ou_id',org.id());
	//if ( find_id_object_in_list( mw.G.my_orgs, id ) ) { 
	if ( mw.G.my_orgs_hash[ id ] ) {
		item.setAttribute('open','true'); 
		item.setAttribute('hidden','false');
		item.setAttribute('myorg','true');
	}
	item.setAttribute( 
		'can_have_vols', 
		//find_id_object_in_list( mw.G.aout_list, org.ou_type() ).can_have_vols() 
		mw.G.aout_hash[ org.ou_type() ].can_have_vols()
	);
	item.setAttribute( 'myid', org.id() );
	if (children && (children.length > 0)) {
		var n_treechildren = document.createElement('treechildren');
		for (var i in children) {
			var child = children[i];
			build_tree_branch(n_treechildren, child, true);
		}
		item.appendChild(n_treechildren);
	}
	treechildren.appendChild(item);
}

function make_treeitem(id,name,flag) {
	var treeitem = document.createElement('treeitem');
		treeitem.setAttribute('id',id);
		treeitem.setAttribute('container','true');
	var treerow = make_treerow(name,flag);
		treeitem.appendChild(treerow);
		treeitem.setAttribute('object_type','org_unit');
	return treeitem;
}

function make_treerow(name,flag) {
	var treerow = document.createElement('treerow');
	var treecell = document.createElement('treecell');
		treecell.setAttribute('label',name);
	treerow.appendChild(treecell);
	treecell = document.createElement('treecell');
		if (flag) treecell.setAttribute('label',0);
	treerow.appendChild(treecell);
	treecell = document.createElement('treecell');
		if (flag) treecell.setAttribute('label',0);
	treerow.appendChild(treecell);

	return treerow;
}

function get_selected_rows_by_object_type(tree,object_type) {
	var items = get_list_from_tree_selection(tree);
	var command = "filter_list(items, function (obj) { return obj.getAttribute('object_type') == '" + object_type + "'; } );";
	return eval(command);
}

function build_CopyBrowser_Context(ev) {
	mw.sdump('D_CAT','build_CopyBrowser_Context: ev.target.tagName = ' + ev.target.tagName + '\n');
	mw.sdump('D_CAT','this = ' + this.tagName + '\n');

	var popup = document.getElementById('browse_menu');
	empty_widget(popup);

	var volume_flag = 0; var copy_flag = 0; var library_flag = 0;

	var hitlist = document.getElementById('browse_list_tree');
	var start = new Object(); var end = new Object();
	var numRanges = hitlist.view.selection.getRangeCount();
	for (var t=0; t<numRanges; t++){
		hitlist.view.selection.getRangeAt(t,start,end);
		for (var v=start.value; v<=end.value; v++){
			var i = hitlist.contentView.getItemAtIndex(v);
			//mw.sdump('D_CAT',i + ':' + i.firstChild.childNodes.length + '\n');
			switch( i.getAttribute('object_type') ) {
				case 'volume' : volume_flag++; break;
				case 'copy' : copy_flag++; break;
				case 'org_unit' : if (i.getAttribute('can_have_vols') == '1') library_flag++; break;
			}
		}
	}
	mw.sdump('D_CAT','volume_flag = ' + volume_flag + ' copy_flag = ' + copy_flag + ' library_flag = ' + library_flag + '\n');
	if (library_flag > 0) {
		var menuitem = document.createElement('menuitem');
		popup.appendChild(menuitem);
			menuitem.setAttribute('label','Add Volumes');
			menuitem.setAttribute('command','cmd_volume_add');
		popup.appendChild( document.createElement( 'menuseparator' ) );
	}
	if (volume_flag > 0) {
		var menuitem = document.createElement('menuitem');
		popup.appendChild(menuitem);
			if (volume_flag > 1) {
				menuitem.setAttribute('label','Edit Volumes');
			} else {
				menuitem.setAttribute('label','Edit Volume');
			}
			menuitem.setAttribute('command','cmd_volume_edit');
		popup.appendChild( document.createElement( 'menuseparator' ) );
		menuitem = document.createElement('menuitem');
		popup.appendChild(menuitem);
			menuitem.setAttribute('label','Add Copies');
			menuitem.setAttribute('command','cmd_copy_add');
		menuitem = document.createElement('menuitem');
		popup.appendChild( document.createElement( 'menuseparator' ) );
	}
	if (copy_flag > 0) {
		var menuitem = document.createElement('menuitem');
		popup.appendChild(menuitem);
			if (copy_flag > 1) {
				menuitem.setAttribute('label','Edit Copies');
			} else {
				menuitem.setAttribute('label','Edit Copy');
			}
			menuitem.setAttribute('command','cmd_copy_edit');
		popup.appendChild( document.createElement( 'menuseparator' ) );
	}
	if (volume_flag > 0) {
		var menuitem = document.createElement('menuitem');
		popup.appendChild(menuitem);
			if (volume_flag > 1) {
				menuitem.setAttribute('label','Delete Volumes');
			} else {
				menuitem.setAttribute('label','Delete Volume');
			}
			menuitem.setAttribute('command','cmd_volume_delete');
		popup.appendChild( document.createElement( 'menuseparator' ) );

	}
	if (copy_flag > 0) {
		var menuitem = document.createElement('menuitem');
		popup.appendChild(menuitem);
			if (copy_flag > 1) {
				menuitem.setAttribute('label','Delete Copies');
			} else {
				menuitem.setAttribute('label','Delete Copy');
			}
			menuitem.setAttribute('command','cmd_copy_delete');
		popup.appendChild( document.createElement( 'menuseparator' ) );
	}

	var menuitem = document.createElement('menuitem');
	popup.appendChild(menuitem);
		menuitem.setAttribute('label','Refresh Listing');
		menuitem.setAttribute('command','cmd_refresh');
}

function volume_add(tab,params) {
	mw.sdump('D_CAT','trying to volume_add()\n');
	params['shortcut'] = 'volume_add';
	var w;
	//var items = get_selected_rows(tree);
	var items = get_list_from_tree_selection(params.tree);
	items = filter_list(
		items,
		function (obj) {
			return obj.getAttribute('object_type') == 'org_unit';
		}
	);
	var chrome = 'chrome://evergreen/content/cat/volume_copy_add_wizard.xul';
	if (tab) {
		parentWindow.new_tab('main_tabbox');
		w = parentWindow.replace_tab('main_tabbox','Add Volume',chrome);
	} else {
		w = mw.new_window( chrome );
	}
	mw.sdump('D_CAT','setting use_this_tree\n');
	w.tree_items = items;
	w.record_id = find_this_id;
	w.params = params;
}

function copy_add(tab,params) {
	mw.sdump('D_CAT','trying to copy_add()\n');
	params['shortcut'] = 'copy_add';
	var w;
	//var items = get_selected_rows(tree);
	var items = get_list_from_tree_selection(params.tree);
	items = filter_list(
		items,
		function (obj) {
			return obj.getAttribute('object_type') == 'volume';
		}
	);
	var chrome = 'chrome://evergreen/content/cat/copy_add_wizard.xul';
	if (tab) {
		parentWindow.new_tab('main_tabbox');
		w = parentWindow.replace_tab('main_tabbox','Add Copy',chrome);
	} else {
		w = mw.new_window( chrome );
	}
	mw.sdump('D_CAT','setting use_this_tree\n');
	w.tree_items = items;
	w.record_id = find_this_id;
	w.params = params;
}

function volume_edit(tab,params) {
	mw.sdump('D_CAT','trying to volume_edit()\n');
	params['shortcut'] = 'volume_edit';
	var w;
	//var items = get_selected_rows(tree);
	var items = get_list_from_tree_selection(params.tree);
	items = filter_list(
		items,
		function (obj) {
			return obj.getAttribute('object_type') == 'volume';
		}
	);
	var chrome = 'chrome://evergreen/content/cat/volume_edit_wizard.xul';
	if (tab) {
		parentWindow.new_tab('main_tabbox');
		w = parentWindow.replace_tab('main_tabbox','Edit Volumes',chrome);
	} else {
		w = mw.new_window( chrome );
	}
	mw.sdump('D_CAT','setting use_this_tree\n');
	w.tree_items = items;
	w.record_id = find_this_id;
	w.params = params;

}

function volume_delete(tab,params) {
	var volumes = get_selected_rows_by_object_type(params.tree,'volume'); 
	var cn_list = [];
	for (var i = 0; i < volumes.length; i++) {
		var cn = new acn();
		cn.id( volumes[i].getAttribute('volume_id') );
		cn.isdeleted( '1' );
		cn_list.push( cn );
	}
	var result = user_request(
			'open-ils.cat',
			'open-ils.cat.asset.volume_tree.fleshed.batch.update',
			[ mw.G['auth_ses'][0], cn_list]
	);
	mw.sdump('D_CAT','volume_tree.fleshed.batch.update result: ' + js2JSON(result) + '\n');
	refresh_browse_list();
}

function copy_delete(tab,params) {
	var copies = get_selected_rows_by_object_type(params.tree,'copy'); 
	var cn_list = [];
	for (var i = 0; i < copies.length; i++) {
		var cn = new acn();
		cn.id( copies[i].getAttribute('volume_id') );

		var cp = new acp();
		cp.id( copies[i].getAttribute('copy_id') );
		cp.isdeleted( '1' );

		cn.copies( [ cp ] );
		cn_list.push( cn );
	}
	var result = user_request(
			'open-ils.cat',
			'open-ils.cat.asset.volume_tree.fleshed.batch.update',
			[ mw.G['auth_ses'][0], cn_list]
	);
	mw.sdump('D_CAT','volume_tree.fleshed.batch.update result: ' + js2JSON(result) + '\n');
	refresh_browse_list();
}
