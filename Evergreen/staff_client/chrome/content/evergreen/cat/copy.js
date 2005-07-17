var local_stat_cats;
var local_stat_cat_entries = {};

function my_init() {
	dump('entering my_init for copy.js\n');
	dump('TESTING: copy.js: ' + mw.G['main_test_variable'] + '\n');
	dump('real_parentWindow: ' + real_parentWindow + '\n');
	populate_copy_status_list('copy-status-menu','copy-status-popup','0');
	populate_copy_location_list('shelving-location-menu','shelving-location-popup');
	populate_lib_list_with_branch('circulating-library-menu','circulating-library-popup', mw.G.user_ou, mw.G.org_tree, true );
	dump('super_dump cn_list = ' + super_dump_norecurse(cn_list) + '\n');
	dump('my_init: cn_list = ' + js2JSON(cn_list) + '\n');
	/*cn_list = fixJSON(cn_list);
	dump('super_dump cn_list = ' + super_dump_norecurse(cn_list) + '\n');
	dump('my_init: cn_list = ' + js2JSON(cn_list) + '\n');*/
	var pertinent_libs = [];
	for (var i = 0; i < cn_list.length; i++) {
		var cn = cn_list[i];
		for (var j = 0; j < cn.copies().length; j++) {
			var cp = cn.copies()[j];
			add_to_listbox(
				i,j,
				mw.G.org_tree_hash[ cn.owning_lib() ].shortname(),
				cn.label(),
				cp.barcode()
			);
		}
		pertinent_libs.push( cn.owning_lib() );
	}
	local_stat_cats = mw.G.asc_list;
	populate_listbox_with_local_stat_cats_myself(
		local_stat_cats,
		local_stat_cat_entries,
		'local_attr_listbox',
		pertinent_libs,
		'open-ils.circ',
		'open-ils.circ.stat_cat.asset.multirange.intersect.retrieve',
		false
	);
	if (params.select_all) {
		document.getElementById('ephemeral_listbox').selectAll();
		apply_attributes();
	}
}

function transfer_attributes(event) {
	var items = event.target.selectedItems;
	dump('selectedItems.length = ' + items.length + '\n');
	if (items.length == 0) { return; }

	// Dump items
	var dump_copies = map_list(
		items,
		function (obj) {
			var cnp = obj.getAttribute('cn_pos');
			var cpp = obj.getAttribute('cp_pos');
			return cn_list[cnp].copies()[cpp];
		}
	);
	for (var i in dump_copies) {
		dump('\n\n\n,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_\n\n\n');
		dump( js2JSON(dump_copies[i]) );
		dump('\n\n\n,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_\n\n\n');
	}

	// Transfer values from first item to XUL

	var cp_pos = items[0].getAttribute('cp_pos');
	var cn_pos = items[0].getAttribute('cn_pos');
	var cp_list = cn_list[cn_pos].copies();
	var copy = cp_list[cp_pos];
	if (copy.circ_lib()) document.getElementById('circulating-library-menu').value =
		copy.circ_lib().id();
	if (copy.location()) document.getElementById('shelving-location-menu').value = 
		copy.location().id();
	if (copy.status()) document.getElementById('copy-status-menu').value =
		copy.status().id();
	if (copy.loan_duration()) document.getElementById('loan-duration-menu').value =
		copy.loan_duration();
	if (copy.fine_level()) document.getElementById('fine-level-menu').value =
		copy.fine_level();
	if (copy.circulate()) document.getElementById('circulate_menu').value =
		copy.circulate();
	if (copy.deposit()) document.getElementById('deposit_menu').value =
		copy.deposit();
	if (copy.deposit_amount()) document.getElementById('deposit_amount').value =
		copy.deposit_amount();
	if (copy.price()) document.getElementById('price').value =
		copy.price();
	if (copy.ref()) document.getElementById('reference_menu').value =
		copy.ref();
	if (copy.opac_visible()) document.getElementById('opac_visible_menu').value =
		copy.opac_visible();

	for (var i in copy.stat_cat_entries()) {
		var entry = copy.stat_cat_entries()[i];
		var menuitem = document.getElementById('menuitem_stat_cat_entry_' + entry.id());
		if (menuitem) {
			menuitem.parentNode.parentNode.selectedItem = menuitem;
		}
	}
	dump('select fired\n');
}


function save_attributes() {
	real_parentWindow.cn_list = cn_list;
	real_parentWindow.document.getElementById('volume_add').canAdvance = true;
	//window.close();
}

function apply_attributes() {
	var circ_lib = document.getElementById('circulating-library-menu').value;
	var shelving_loc = document.getElementById('shelving-location-menu').value;
	var copy_status = document.getElementById('copy-status-menu').value;
	var loan_duration = document.getElementById('loan-duration-menu').value;
	var fine_level = document.getElementById('fine-level-menu').value;
	var circulate = document.getElementById('circulate_menu').value;
	var deposit = document.getElementById('deposit_menu').value;
	var deposit_amount = document.getElementById('deposit_amount').value;
	var price = document.getElementById('price').value;
	var ref = document.getElementById('reference_menu').value;
	var opac = document.getElementById('opac_visible_menu').value;
	var listbox = document.getElementById('ephemeral_listbox');
	var items = listbox.selectedItems;
	dump('selectedItems.length = ' + items.length + '\n');
	for (var i = 0; i < items.length; i++) {
		var listitem = items[i];
		var cn_pos = listitem.getAttribute('cn_pos');
		var cp_pos = listitem.getAttribute('cp_pos');
		var copy_node = cn_list[cn_pos].copies()[cp_pos];
		copy_node.circ_lib(	mw.G.org_tree_hash[ circ_lib ]);
		copy_node.location(	mw.G.acpl_hash[ shelving_loc ]);
		copy_node.status(	mw.G.ccs_hash[ copy_status ]);
		copy_node.loan_duration(loan_duration);
		copy_node.fine_level(fine_level);
		copy_node.circulate(circulate);
		copy_node.deposit(deposit);
		copy_node.deposit_amount(deposit_amount);
		copy_node.price(price);
		copy_node.ref(ref);
		copy_node.opac_visible(opac);
		copy_node.ischanged(1);
	}

	dump('changed cn_list: ' + js2JSON(cn_list) + '\n');
}

function apply_attribute(ev) {
	dump('Entering apply_attribute with element id = ');
	var popup_id;
	if (ev.target.tagName == 'menuitem') {
		popup_id = ev.target.parentNode.getAttribute('id');
	} else {
		popup_id = ev.target.getAttribute('id');
	}
	dump(popup_id + '\n');
	dump('ev.target = ' + ev.target + '  .tagName = ' + ev.target.tagName + '\n');

	var circ_lib = document.getElementById('circulating-library-menu').value;
	var shelving_loc = document.getElementById('shelving-location-menu').value;
	var copy_status = document.getElementById('copy-status-menu').value;
	var loan_duration = document.getElementById('loan-duration-menu').value;
	var fine_level = document.getElementById('fine-level-menu').value;
	var circulate = document.getElementById('circulate_menu').value;
	var deposit = document.getElementById('deposit_menu').value;
	var deposit_amount = document.getElementById('deposit_amount').value;
	var price = document.getElementById('price').value;
	var ref = document.getElementById('reference_menu').value;
	var opac = document.getElementById('opac_visible_menu').value;
	var listbox = document.getElementById('ephemeral_listbox');
	var items = listbox.selectedItems;

	dump('selectedItems.length = ' + items.length + '\n');
	dump('before  cn_list: ' + js2JSON(cn_list) + '\n');
	for (var i = 0; i < items.length; i++) {
		var listitem = items[i];
		var cn_pos = listitem.getAttribute('cn_pos');
		var cp_pos = listitem.getAttribute('cp_pos');
		var copy_node = cn_list[cn_pos].copies()[cp_pos];

		dump('\n\n\n\n+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+\n\n\n\n');
		dump('Setting copy ' + copy_node.id() + '...\n');
		switch(popup_id) {
			case 'circulating-library-popup':
				dump('\tbefore circ_lib = ' + js2JSON(copy_node.circ_lib()) + '\n');
				copy_node.circ_lib(	mw.G.org_tree_hash[ circ_lib ] );
				dump('\tafter  circ_lib = ' + js2JSON(copy_node.circ_lib()) + '\n');
				break;
			case 'shelving-location-popup':
				dump('\tbefore location = ' + js2JSON(copy_node.location()) + '\n');
				copy_node.location(	mw.G.acpl_hash[ shelving_loc ] );
				dump('\tafter  location = ' + js2JSON(copy_node.location()) + '\n');
				break;
			case 'copy-status-popup':
				dump('\tbefore status = ' + js2JSON(copy_node.status()) + '\n');
				copy_node.status(	mw.G.ccs_hash[ copy_status ]);
				dump('\tafter  status = ' + js2JSON(copy_node.status()) + '\n');
				break;
			case 'loan-duration-popup':
				dump('\tbefore loan_duration = ' + js2JSON(copy_node.loan_duration()) + '\n');
				copy_node.loan_duration(loan_duration);
				dump('\tafter  loan_duration = ' + js2JSON(copy_node.loan_duration()) + '\n');
				break;
			case 'fine-level-popup':
				dump('\tbefore fine_level = ' + js2JSON(copy_node.fine_level()) + '\n');
				copy_node.fine_level(fine_level);
				dump('\tafter  fine_level = ' + js2JSON(copy_node.fine_level()) + '\n');
				break;
			case 'circulate_popup':
				dump('\tbefore circulate = ' + js2JSON(copy_node.circulate()) + '\n');
				copy_node.circulate(circulate);
				dump('\tafter  circulate = ' + js2JSON(copy_node.circulate()) + '\n');
				break;
			case 'deposit_popup':
				dump('\tbefore deposit = ' + js2JSON(copy_node.deposit()) + '\n');
				copy_node.deposit(deposit);
				dump('\tafter  deposit = ' + js2JSON(copy_node.deposit()) + '\n');
				break;
			case 'deposit_amount':
				dump('\tbefore deposit_amount = ' + js2JSON(copy_node.deposit_amount()) + '\n');
				copy_node.deposit_amount(deposit_amount);
				dump('\tafter  deposit_amount = ' + js2JSON(copy_node.deposit_amount()) + '\n');
				break;
			case 'price':
				dump('\tbefore price = ' + js2JSON(copy_node.price()) + '\n');
				copy_node.price(price);
				dump('\tafter  price = ' + js2JSON(copy_node.price()) + '\n');
				break;
			case 'reference_popup':
				dump('\tbefore ref = ' + js2JSON(copy_node.ref()) + '\n');
				copy_node.ref(ref);
				dump('\tafter  ref = ' + js2JSON(copy_node.ref()) + '\n');
				break;
			case 'opac_visible_popup':
				dump('\tbefore opac_visible = ' + js2JSON(copy_node.opac_visible()) + '\n');
				copy_node.opac_visible(opac);
				dump('\tafter  opac_visible = ' + js2JSON(copy_node.opac_visible()) + '\n');
				break;
			default:
				dump('\t++++++++ Unhandled.. this should be a stat_cat: ' + popup_id + ' / ' + ev.target.tagName + '\n');
				update_stat_cat_entry(copy_node,ev.target);
				break;
		}
		dump('\n\n\n\n+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+_+\n\n\n\n');
		copy_node.ischanged(1);
	}

	dump('changed cn_list: ' + js2JSON(cn_list) + '\n');
}

function update_stat_cat_entry(copy,menuitem) {
	dump('\tupdate_stat_cat_entry: value = ' + menuitem.value + '\n');
	var entries = copy.stat_cat_entries();
	//dump('\n\n\ncopy = ' + js2JSON(copy) + '\n');
	//dump('\n\n\ncopy.stat_cat_entries() = ' + js2JSON(copy.stat_cat_entries()) + '\n');
	var stat_cat_id = menuitem.getAttribute('stat_cat');
	var entry = find_attr_object_in_list(entries,'stat_cat',stat_cat_id);
	if (entry) {
		dump('\tReplacing old stat_cat_entry with ');

		entries = filter_list(
			entries,
			function (obj) {
				return (obj.id() != entry.id());
			}
		);

	} else {
		dump('\tAppending new stat_cat_entry = ');
	}
	dump(js2JSON(local_stat_cat_entries[menuitem.value]) + '\n');
	entries.push( local_stat_cat_entries[ menuitem.value ] );
	copy.stat_cat_entries( entries );
}

function add_to_listbox(cn_pos,cp_pos,name,callnumber,barcode) {
	dump('xul: name = ' + name + ' cn = ' + callnumber + ' bc = ' + barcode + '\n');
	var listbox = document.getElementById('ephemeral_listbox');
	var listitem = document.createElement('listitem');
		listitem.setAttribute('cn_pos',cn_pos);
		listitem.setAttribute('cp_pos',cp_pos);
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

