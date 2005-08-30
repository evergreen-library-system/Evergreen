mw.sdump('D_CAT','loading marc.js\n');

var character_measure = {};
var tree;
var meta;
var backup_tree;

function my_init() {
	mw.sdump('D_CAT','Entering my_init() : ' + timer_elapsed('cat') + '\n');
	mw.sdump('D_CAT','TESTING: marc.js: ' + mw.G['main_test_variable'] + '\n');

	try {
		mw.sdump('D_CAT',"DOC ID " + find_this_id + "\n" );
	} catch(E) {
		
	}

	if (! params.import_tree ) {
		tree = retrieve_record( find_this_id );
		/*
		meta = retrieve_meta_record( find_this_id );
		document.getElementById('meta_create_date').setAttribute('value',
			meta.create_date().split('.')[0]	
		);
		document.getElementById('meta_creator').setAttribute('value',
			meta.creator()	
		);
		document.getElementById('meta_edit_date').setAttribute('value',
			meta.edit_date().split('.')[0]
		);
		document.getElementById('meta_editor').setAttribute('value',
			meta.editor()	
		);
		document.getElementById('meta_tcn_publisher').setAttribute('value',
			meta.tcn_value()	
		);
		if (params.record_columns) {
			var text = document.createTextNode(
				params.record_columns[1] + ' / ' + params.record_columns[2]
			);
			document.getElementById('meta_title_author').appendChild(
				text
			);
		}
		*/
	} else {
		tree = params.import_tree;
	}
	if (tree.name() == 'collection') { 
		tree = find_list(
			tree.children(),
			function (obj) {
				return (obj.name() == 'record');
			}
		); 
	}

	//mw.sdump('D_CAT','Retrieved: ' + js2JSON(tree) + '\n');
	//mw.sdump('D_CAT','Retrieved: ' + js2JSON(meta) + '\n');
	build_grid( 
		document.getElementById('ctrl_rows'), 
		document.getElementById('data_rows'), 
		tree
	);
	fixed_fields_show_only('fixed_grid','BKS');
	apply_event_listeners('fixed_grid','fixed');
	character_measure = measure_character('marc_win','M');
	window.addEventListener('resize',my_resize_handler,false);
	handle_tag_change();
	document.getElementById('data_rows').firstChild.firstChild.firstChild.focus();
	mw.sdump('D_CAT','Exiting my_init() : ' + timer_elapsed('cat') + '\n');
}

function measure_character(w,c) {
	var el = document.getElementById(w);
	var b = document.createElement('hbox');
	var l = document.createElement('label');
	l.setAttribute('class','marc');
	el.appendChild(b);
	b.appendChild(l);
	var lwidth = l.boxObject.width;
	l.value = c;
	lwidth = Math.abs( l.boxObject.width - lwidth);
	var lheight = l.boxObject.height;
	b.removeChild(l); el.removeChild(b);
	return { "width" : lwidth, "height" : lheight };
}

function my_resize_handler(ev) {
	mw.sdump('D_CAT','resize\n');
	resizeAllWrappers('ctrl_rows');
	resizeAllWrappers('data_rows');
}

function retrieve_record(id) {
	mw.sdump('D_CAT','Entering retrieve_record() : ' + timer_elapsed('cat') + '\n');
	var result;
	try {
		result = user_request(
			'open-ils.cat',
			'open-ils.cat.biblio.record.tree.retrieve',
			[ id ]
		);
	} catch(E) {
		handle_error(E);
	}
	//var result = [ JSON2js( test_nodeset() ) ];
	/*var result = user_request(
		'open-ils.cat',
		'open-ils.cat.biblio.record.tree.retrieve.test',
		[ id ]
	);*/
	if (typeof(result[0]) != 'object') {
		alert( 'user_request gave ' + js2JSON(result) );
		mw.sdump('D_CAT','Exiting retrieve_record() : ' + timer_elapsed('cat') + '\n');
		return 0;
	} else {
		/*
		mw.sdump('D_CAT','Entering nodeset2tree() : ' + timer_elapsed('cat') + '\n');
		result[0] = nodeset2tree( result[0] )[0];
		mw.sdump('D_CAT','Exiting nodeset2tree() : ' + timer_elapsed('cat') + '\n');
		*/
		mw.sdump('D_CAT','Exiting retrieve_record() : ' + timer_elapsed('cat') + '\n');
		return result[0];
	}
}

function retrieve_meta_record(id) {
	mw.sdump('D_CAT','Entering retrieve_meta_record() : ' + timer_elapsed('cat') + '\n');
	var result;
	try {
		result = user_request(
			'open-ils.cat',
			'open-ils.cat.biblio.record.metadata.retrieve',
			[ id ]
		);
	} catch(E) {
		handle_error(E);
	}
	if (typeof(result[0]) != 'object') {
		alert( 'user_request gave ' + js2JSON(result) );
		mw.sdump('D_CAT','Exiting retrieve_meta_record() : ' + timer_elapsed('cat') + '\n');
		return 0;
	} else {
		mw.sdump('D_CAT','Exiting retrieve_meta_record() : ' + timer_elapsed('cat') + '\n');
		return result[0][0];
	}
}



function empty_me(p) {
	while (p.lastChild) {
		//mw.sdump('D_CAT','emptying ' + p.lastChild.tagName + '\n');
		empty_me(p.lastChild);
		p.removeChild(p.lastChild);
	}
}

function empty_grid( ctrl_rows, data_rows ) {
	var rows = document.getElementById(ctrl_rows);
	empty_me(rows);
	rows = document.getElementById(data_rows);
	empty_me(rows);
}

function build_grid( ctrl_rows, data_rows, root ) {
	mw.sdump('D_CAT','Entering build_grid() : ' + timer_elapsed('cat') + '\n');
	var ctrl_count = 1; var data_count = 1;
	//mw.sdump('D_CAT', 'what is root?\n' + pretty_print(js2JSON(root)) + '\n');
	mw.sdump('D_CAT','root.children.length = ' + root.children.length + '\n');
	root_loop: 
	var children = root.children();
	for (var i in children) {
		var node = children[i];
		var node_type = node.node_type();
		var row = {};
		switch(node_type) {
			case 18: case '18': /* namespace */ 
				break;
			case 1: case '1': /* element */
				row = get_row(node);
				switch(row.type) {
					case 'leader': case 'controlfield':
							populate_xul_row( 
								ctrl_rows, 
								row, 
								'ctrl_' + ctrl_count++
							);
						break;
					case 'datafield':
							populate_xul_row( 
								data_rows, 
								row, 
								'data_' + data_count++
							);
						break;
					default:
						mw.sdump('D_CAT','Unexpected row type: ' + 
							js2JSON(node) + '\n');
						break;
				}
				break;
			default: /* eh? */
				mw.sdump('D_CAT', 'Did not expect node_type = ' + node_type + 
					' : ' + js2JSON(node) + '\n');
				break;
		}
		//mw.sdump('D_CAT', i + ' ' + dump_ns_node(node) + '\n');
	}
	mw.sdump('D_CAT','Exiting build_grid() : ' + timer_elapsed('cat') + '\n');
}

function get_row( top ) {
	var row = { 
		'field' : { 'id' : '1' },
		'tag' : { 'value' : '', 'id' : '-1' },
		'ind1' : { 'value' : '', 'id' : '-1' },
		'ind2' : { 'value' : '', 'id' : '-1' },
		'data' : { 'value' : '', 'id' : '-1' }
	};
	var name = top.name(); 
	var id = top.intra_doc_id(); 
	var children = top.children();
	row.field.id = id;
	mw.sdump('D_CAT','Making row.... row.field.id = <' + id + '>\n');
	if (name == 'leader') { row.tag.value = 'LDR'; row.tag.id = id; }
	row.type = name;
	top_loop:
	for (var i in children) {
		var node = children[i];
		var node_type = node.node_type();
		var node_name = node.name();
		var node_value = node.value();
		var node_id = node.intra_doc_id();
		var node_children = node.children();
		switch(node_type) {
			case 18: case '18': /* namespace */ 
				continue top_loop;
			case 2: case '2': /* attribute */ 
				switch(node_name) {
					case 'tag':
						row.tag.value = node_value;
						row.tag.id = node_id;
						break;
					case 'ind1':
						row.ind1.value = node_value;
						row.ind1.id = node_id;
						break;
					case 'ind2':
						row.ind2.value = node_value;
						row.ind2.id = node_id;
						break;
					default:
						mw.sdump('D_CAT','\tattribute surprise on node_name = ' +
							node_name + ' : ' 
							+ js2JSON(node) + '\n');
						break;
				}
				break;
			case 1: case '1': /* element */
				switch(node_name) {
					case 'subfield':
						row.data.value = row.data.value + 
						String.fromCharCode(8225) +
						node_children[0].value() + ' ' + 
						node_children[1].value() + ' ';
						row.data.id = node_id;
						break;
					default:
						mw.sdump('D_CAT','\telement surprise on node_name = ' +
							node_name + ' : ' 
							+ js2JSON(node) + '\n');
						break;
				}
				break;
			case 3: case '3': /* textNode */
				row.data.value = node_value;
				row.data.id = node_id;
				break;
			default: /* eh? */
				mw.sdump('D_CAT','\tunknown type surprise on node_type = ' +
					node_type + ' : '  +
					js2JSON(node) + '\n');
				break;
		}
	}
	//mw.sdump('D_CAT',js2JSON(row) + '\n');
	return row;
}

function build_xul_row( id, type ) {
	switch(type) {
		case 'leader': case 'controlfield':
			return build_ctrl_row( id );
			break;
		case 'datafield':
			return build_data_row( id );
			break;
		default:
			mw.sdump('D_CAT','Unexpected row type\n');
			break;
	}
}

function build_data_row( id ) {
	//mw.sdump('D_CAT','Entering build_xul_row() : ' + timer_elapsed('cat') + '\n');
	var xul_row = document.createElement('row');
	xul_row.setAttribute('id',id);
	xul_row.setAttribute('class','field_row data_row');
	//xul_rows.appendChild(xul_row);

	/* the elements in the row */
	var wrapper1 = document.createElement('hbox');
	wrapper1.setAttribute( 'class', 'marc_wrapper marc_tag_wrapper');
	var xul_col1 = document.createElement('textbox');
		xul_col1.setAttribute( 'cols', '3');
		xul_col1.setAttribute( 'rows', '1');
		xul_col1.setAttribute( 'multiline', 'true');
		xul_col1.setAttribute( 'size', '3');
		xul_col1.setAttribute( 'class', 'marc marc_tag');
		wrapper1.appendChild(xul_col1);
		xul_row.appendChild(wrapper1);
	var wrapper2 = document.createElement('hbox');
	wrapper2.setAttribute( 'class', 'marc_wrapper marc_ind_wrapper marc_ind1_wrapper');
	var xul_col2 = document.createElement('textbox');
		xul_col2.setAttribute( 'cols', '1');
		xul_col2.setAttribute( 'rows', '1');
		xul_col2.setAttribute( 'multiline', 'true');
		xul_col2.setAttribute( 'size', '1');
		xul_col2.setAttribute( 'class', 'marc marc_ind marc_ind1');
		wrapper2.appendChild(xul_col2);
		xul_row.appendChild(wrapper2);
	var wrapper3 = document.createElement('hbox');
	wrapper3.setAttribute( 'class', 'marc_wrapper marc_ind_wrapper marc_ind2_wrapper');
	var xul_col3 = document.createElement('textbox');
		xul_col3.setAttribute( 'cols', '1');
		xul_col3.setAttribute( 'rows', '1');
		xul_col3.setAttribute( 'multiline', 'true');
		xul_col3.setAttribute( 'size', '1');
		xul_col3.setAttribute( 'class', 'marc marc_ind marc_ind2');
		wrapper3.appendChild(xul_col3);
		xul_row.appendChild(wrapper3);
	var wrapper4 = document.createElement('hbox');
	wrapper4.setAttribute( 'class', 'marc_wrapper marc_data_wrapper');
	var xul_col4 = document.createElement('textbox');
		xul_col4.setAttribute( 'subfields', 'true');
		xul_col4.setAttribute( 'cols', '60');
		xul_col4.setAttribute( 'size', '60');
		xul_col4.setAttribute( 'rows', '1');
		xul_col4.setAttribute( 'multiline', 'true');
		xul_col4.setAttribute( 'class', 'marc marc_data resizable');
		xul_col4.setAttribute( 'flex', '1');
		wrapper4.appendChild(xul_col4);
		xul_row.appendChild(wrapper4);

	return xul_row;
	//mw.sdump('D_CAT','Exiting build_xul_row() : ' + timer_elapsed('cat') + '\n');
}

function build_ctrl_row( id ) {
	//mw.sdump('D_CAT','Entering build_xul_row() : ' + timer_elapsed('cat') + '\n');
	var xul_row = document.createElement('row');
	xul_row.setAttribute('class','field_row ctrl_row');
	xul_row.setAttribute('id',id);
	//xul_rows.appendChild(xul_row);

	/* the elements in the row */
	var wrapper1 = document.createElement('hbox');
	wrapper1.setAttribute( 'class', 'marc_wrapper marc_tag_wrapper ctrl_wrapper');
	var xul_col1 = document.createElement('textbox');
		xul_col1.setAttribute( 'cols', '3');
		xul_col1.setAttribute( 'rows', '1');
		xul_col1.setAttribute( 'multiline', 'true');
		xul_col1.setAttribute( 'size', '3');
		xul_col1.setAttribute( 'class', 'marc marc_tag ctrl');
		xul_col1.setAttribute( 'disabled', 'true');
		wrapper1.appendChild(xul_col1);
		xul_row.appendChild(wrapper1);
	var wrapper4 = document.createElement('hbox');
	wrapper4.setAttribute( 'class', 'marc_wrapper marc_data_wrapper ctrl_wrapper');
	var xul_col4 = document.createElement('textbox');
		xul_col4.setAttribute( 'cols', '60');
		xul_col4.setAttribute( 'size', '60');
		xul_col4.setAttribute( 'rows', '1');
		xul_col4.setAttribute( 'multiline', 'true');
		xul_col4.setAttribute( 'class', 'marc marc_data ctrl');
		xul_col4.setAttribute( 'flex', '1');
		xul_col4.setAttribute( 'disabled', 'true');
		wrapper4.appendChild(xul_col4);
		xul_row.appendChild(wrapper4);

	return xul_row;
	//mw.sdump('D_CAT','Exiting build_xul_row() : ' + timer_elapsed('cat') + '\n');
}


function apply_event_listeners(c,which) {
	switch(which) {
		case 'ctrl':
			break;
		case 'data':
			c[0].firstChild.addEventListener("change",handle_tag_change,false);
			c[0].firstChild.addEventListener("keypress",handle_keypress,false);
			c[1].firstChild.addEventListener("keypress",handle_keypress,false);
			c[1].firstChild.addEventListener("change",handle_tag_change,false);
			c[2].firstChild.addEventListener("keypress",handle_keypress,false);
			c[2].firstChild.addEventListener("change",handle_tag_change,false);
			c[3].firstChild.addEventListener("keypress",handle_keypress,false);
			c[3].firstChild.addEventListener("change",handle_tag_change,false);
			c[3].firstChild.addEventListener("change",handle_change,false);
			break;
		case 'fixed':
			var g = document.getElementById(c);
			var nl = g.getElementsByTagName('textbox');
			for (var i in nl) {
				if (typeof(nl[i])=='object') {
					nl[i].addEventListener("change",handle_fixed_change,false);
				}
			}
			break;
	}
}

function populate_xul_row( xul_rows, row, id ) {

	var r = document.getElementById(id);
	if (!r) {
		r = build_xul_row(id,row.type);
		xul_rows.appendChild(r);
		//r = document.getElementById(id);
	}
	r.setAttribute('notempty','true');
	r.setAttribute('mynode',row.field.id);
	var c = r.childNodes;
	switch(row.type) {
		case 'leader': case 'controlfield':
			c[0].firstChild.value = row.tag.value;
			c[0].firstChild.select();
			c[0].firstChild.setAttribute('mynode', row.tag.id);
			c[1].firstChild.value = row.data.value;
			c[1].firstChild.select();
			c[1].firstChild.setAttribute('mynode', row.data.id);
			apply_event_listeners(c,'ctrl');
			break;
		case 'datafield':
			c[0].firstChild.value = row.tag.value;
			c[0].firstChild.select();
			c[0].firstChild.setAttribute('mynode', row.tag.id);
			c[1].firstChild.value = row.ind1.value;
			c[1].firstChild.select();
			c[1].firstChild.setAttribute('mynode', row.ind1.id);
			c[2].firstChild.value = row.ind2.value;
			c[2].firstChild.select();
			c[2].firstChild.setAttribute('mynode', row.ind2.id);
			c[3].firstChild.value = row.data.value;
			c[3].firstChild.select();
			c[3].firstChild.setAttribute('mynode', row.data.id);
			apply_event_listeners(c,'data');
			break;
	}
	//resizeWrapper(c3);
}

function handle_change(ev) {
	mw.sdump('D_CAT','handle_change\n');
	var t = ev.target;
	// parse subfields
	resizeWrapper(t);
}

function resizeWrapper(t) {
	if (t.tagName != 'textbox') { return; }
	var wrapper = t.parentNode;
	var width = wrapper.boxObject.width;
	var height = wrapper.boxObject.height;

	/*var lwidth = character_measure.width * t.value.length; // linux */
	var lwidth = (character_measure.width*2+5) * t.value.length; // windows
	var lheight = character_measure.height;

	if (width == 0) { width = lwidth; }
	var xrows = Math.ceil( lwidth / width );
	if (xrows < 1) { xrows = 1; }
	var xheight = (xrows * (lheight+5)); 

	//mw.sdump('D_CAT',wrapper.parentNode.id + ' wrapper: ' + width + 'x' + height + ' label: ' + lwidth + 'x' + lheight + '\n');
	wrapper.setAttribute('style','min-height: ' + xheight + 'px;');
}

function resizeAllWrappers(rows) {
	mw.sdump('D_CAT','Entering resizeAllWrappers() : ' + timer_elapsed('cat') + '\n');
	var p = document.getElementById(rows);
	var c = p.childNodes;
	for (var r in c) {
		if (typeof(c[r])=='object') {
			if (c[r].getAttribute('notempty')) {
				resizeWrapper(c[r].lastChild.firstChild);
			} else {
				p.removeChild(c[r]);
			}
		}
	}
	mw.sdump('D_CAT','Exiting resizeAllWrappers() : ' + timer_elapsed('cat') + '\n');
}

function find_element_with_id(ns_slice,id) {
	// we might change this in the future to be a hash lookup
	// { node id => [lvl 1 index, lvl 2 index, lvl 3 index]  }
	// with the hash being populated when the tree is generated
	// and updated when we go to insert nodes
	//mw.sdump('D_CAT','Find ' + id + ' in ' + js2JSON(ns_slice) + '\n');
	//mw.sdump('D_CAT','Find ' + id + '\n');
	for (i in ns_slice) {
		if (ns_slice[i].intra_doc_id() == id) {
			//mw.sdump('D_CAT','Found at index ' + i + '\n');
			return i;
		}
	}
	mw.sdump('D_CAT',id + 'not found in' + js2JSON(ns_slice) + '\n');
}

function delete_children(branch) {
	var children = branch.children();
	for (var c in children) {
		children[c].isdeleted(1);
		mw.sdump('D_CAT', children[c].name() + ':' +
			children[c].id() + ':' +
			children[c].intra_doc_id() + '.is_deleted = 1\n');
		if (children[c].children()) {
			delete_children(children[c]);
		}
	}
}

function submit_marc() {
	// walk through the marc grid and compare with the tree
	// 1) updates and deletes

mw.sdump('D_CAT','Updates and Deletes\n');
	backup_tree = JSON2js( js2JSON( tree ) );

	var tree_fields = tree.children(); // LEVEL 1
	var ctrl_rows = document.getElementById('ctrl_rows').childNodes;
	for (var r = 0; r < ctrl_rows.length ; r++) {
		//if (r == 0) { continue; } // skip leader for now
		//mw.sdump('D_CAT', r + '\n');
		var tag_node_id;
		try {
			tag_node_id = ctrl_rows[r].getAttribute('mynode');
		} catch(E) {
			mw.sdump('D_CAT','Could not find mynode in ctrl_rows[' + r + ']\n');
			continue;
		}
		//mw.sdump('D_CAT', r + ':' + ctrl_rows[r].tagName + ':' + tag_node_id + '\n' );
		if (tag_node_id) {
mw.sdump('D_CAT','Processing ctrl_rows[' + r + '], tag_node_id = ' + tag_node_id + '\n');
			if (tag_node_id < 0) { continue; } // new node, handle elsewhere
mw.sdump('D_CAT','1st find =========================================\n')
			var tree_pos = find_element_with_id(tree_fields,tag_node_id);
			if (tree_pos == null) { alert('tree_pos problem!'); }
			var tree_field = tree_fields[tree_pos];

			if (ctrl_rows[r].getAttribute('hidden') == 'true') {
				tree_field.isdeleted(1);
				mw.sdump('D_CAT', tree_field.name() + ':' +
					tree_field.id() + ':' +
					tree_field.intra_doc_id() + '.isdeleted = 1\n');
				delete_children(tree_field);
				continue;
			}

			var col1 = ctrl_rows[r].childNodes[0].firstChild;
			var col2 = ctrl_rows[r].childNodes[1].firstChild;
			var id1 = col1.getAttribute('mynode');
			var id2 = col2.getAttribute('mynode');
			mw.sdump('D_CAT','id1 = ' + id1 + ' col1.value = ' + col1.value + '  id2 = ' + id2 + ' col2.value = ' + col2.value + '\n');
			var tree_field_children = tree_field.children(); // LEVEL 2

			if (r == 0) { // leader is special.  Only one child
				if (tree_field_children[0].value() != col2.value) {
					tree_field_children[0].value(col2.value);
					tree_field_children[0].ischanged(1);
					mw.sdump('D_CAT', tree_field_children[0].name() + ':' +
						tree_field_children[0].id() + ':' +
						tree_field_children[0].intra_doc_id() +
						'.ischanged = 1\n');
				}
				continue;
			}

mw.sdump('D_CAT','2nd find =========================================\n')
			var tree_tag = find_element_with_id(tree_field_children,id1);
mw.sdump('D_CAT','3rd find =========================================\n')
			var tree_value = find_element_with_id(tree_field_children,id2);
			if (tree_tag == null) { alert('tree_tag problem!'); }
			if (tree_value == null) { alert('tree_value problem!'); }
			if (tree_field_children[tree_tag].value() != col1.value) {
				tree_field_children[tree_tag].value(col1.value);
				tree_field_children[tree_tag].ischanged(1);
				mw.sdump('D_CAT', tree_field_children[tree_tag].name() + ':' +
					tree_field_children[tree_tag].id() + ':' +
					tree_field_children[tree_tag].intra_doc_id() +
					'.ischanged = 1\n');
			}
			if (tree_field_children[tree_value].value() != col2.value) {
				tree_field_children[tree_value].value(col2.value);
				tree_field_children[tree_value].ischanged(1);
				mw.sdump('D_CAT', tree_field_children[tree_value].name() + ':' +
					tree_field_children[tree_value].id() + ':' +
					tree_field_children[tree_value].intra_doc_id() +
					'.ischanged = 1\n');
			}
		}
	}
	var data_rows = document.getElementById('data_rows').childNodes;
	for (var r = 0; r < data_rows.length ; r++ ) {
		var tag_node_id;
		try {
			tag_node_id = data_rows[r].getAttribute('mynode');
		} catch(E) {
			continue;
		}
		//mw.sdump('D_CAT', r + ':' + data_rows[r].tagName + ':' + tag_node_id + '\n' );
		if (tag_node_id) {
mw.sdump('D_CAT','Processing data_rows[' + r + '], tag_node_id = ' + tag_node_id + '\n');
			if (tag_node_id < 0) { continue; } // new node, handle elsewhere
mw.sdump('D_CAT','4th find =========================================\n')
			var tree_pos = find_element_with_id(tree_fields,tag_node_id);
			if (tree_pos == null) { alert('tree_pos problem!'); }
			var tree_field = tree_fields[tree_pos];

			if (data_rows[r].getAttribute('hidden') == 'true') {
				tree_field.isdeleted(1);
				mw.sdump('D_CAT',tree_field.name() + ':' +
					tree_field.id() + ':' +
					tree_field.intra_doc_id() +
					'.isdeleted = 1\n');
				delete_children(tree_field);
				continue;
			}

			var col1 = data_rows[r].childNodes[0].firstChild;
			var col2 = data_rows[r].childNodes[1].firstChild;
			var col3 = data_rows[r].childNodes[2].firstChild;
			var col4 = data_rows[r].childNodes[3].firstChild;
			var id1 = col1.getAttribute('mynode');
			var id2 = col2.getAttribute('mynode');
			var id3 = col3.getAttribute('mynode');
			var id4 = col4.getAttribute('mynode');
			var tree_field_children = tree_field.children(); // LEVEL 2
mw.sdump('D_CAT','5th find =========================================\n')
			var tree_tag = find_element_with_id(tree_field_children,id1);
mw.sdump('D_CAT','6th find =========================================\n')
			var tree_ind1 = find_element_with_id(tree_field_children,id2);
mw.sdump('D_CAT','7th find =========================================\n')
			var tree_ind2 = find_element_with_id(tree_field_children,id3);
mw.sdump('D_CAT','8th find =========================================\n')
			var tree_data = find_element_with_id(tree_field_children,id4);
			if (tree_tag == null) { alert('tree_tag problem!'); }
			if (tree_ind1 == null) { alert('tree_ind1 problem!'); }
			if (tree_ind2 == null) { alert('tree_ind2 problem!'); }
			if (tree_data == null) { alert('tree_data problem!'); }
			if (tree_field_children[tree_tag].value() != col1.value) {
				tree_field_children[tree_tag].value(col1.value);
				tree_field_children[tree_tag].ischanged(1);
				mw.sdump('D_CAT', tree_field_children[tree_tag].name() + ':' +
					tree_field_children[tree_tag].id() + ':' +
					tree_field_children[tree_tag].intra_doc_id() +
					'.is_changed = 1\n');
			}
			if (tree_field_children[tree_ind1].value() != col2.value) {
				tree_field_children[tree_ind1].value(col2.value);
				tree_field_children[tree_ind1].ischanged(1);
				mw.sdump('D_CAT', tree_field_children[tree_ind1].name() + ':' +
					tree_field_children[tree_ind1].id() + ':' +
					tree_field_children[tree_ind1].intra_doc_id() +
					'.is_changed = 1\n');
			}
			if (tree_field_children[tree_ind2].value() != col3.value) {
				tree_field_children[tree_ind2].value(col3.value);
				tree_field_children[tree_ind2].ischanged(1);
				mw.sdump('D_CAT', tree_field_children[tree_ind2].name() + ':' +
					tree_field_children[tree_ind2].id() + ':' +
					tree_field_children[tree_ind2].intra_doc_id() +
					'.is_changed = 1\n');
			}
			process_subfields(tree_field_children,col4.value); // LEVEL 3
		}
	}


	// 2) inserts
mw.sdump('D_CAT','Inserts\n');

	for (var r = 0; r < ctrl_rows.length ; r++) {
		var newnode;
		try {
			newnode = ctrl_rows[r].getAttribute('newnode');
		} catch(E) {
			continue;
		}
		if (newnode=='true') {
mw.sdump('D_CAT','New node = ctrl_rows[' + r + ']');
			if (ctrl_rows[r].getAttribute('hidden')=='true') { continue; }
			var col1 = ctrl_rows[r].childNodes[0].firstChild.value;
			var col2 = ctrl_rows[r].childNodes[1].firstChild.value;
			var level1 = new brn(); 
				populate_node( level1, 1, 'controlfield' );
			var level2a = new brn(); 
				populate_node( level2a, 2, 'tag' );
				level2a.value(col1);
			var level2b = new brn();
				populate_node( level2b, 3, null );
				level2b.value(col2);
			level1.children([ level2a, level2b ]);
			ctrl_rows[r].setAttribute('mynode', level1.intra_doc_id());
mw.sdump('D_CAT',' with intra_doc_id = ' + level1.intra_doc_id() + '\n');
			insert_into_tree(tree.children(),ctrl_rows[r],level1);
		}
	}

	for (var r = 0; r < data_rows.length ; r++) {
		var newnode;
		try {
			newnode = data_rows[r].getAttribute('newnode');
		} catch(E) {
			continue;
		}
		if (newnode=='true') {
mw.sdump('D_CAT','New node = data_rows[' + r + ']');
			if (data_rows[r].getAttribute('hidden')=='true') { continue; }
			var col1 = data_rows[r].childNodes[0].firstChild.value;
			var col2 = data_rows[r].childNodes[1].firstChild.value;
			var col3 = data_rows[r].childNodes[2].firstChild.value;
			var col4 = data_rows[r].childNodes[3].firstChild.value;
			var level1 = new brn(); 
				populate_node( level1, 1, 'datafield' );
			var level2a = new brn(); 
				populate_node( level2a, 2, 'tag' );
				level2a.value(col1);
			var level2b = new brn();
				populate_node( level2b, 2, 'ind1' );
				level2b.value(col2);
			var level2c = new brn();
				populate_node( level2c, 2, 'ind2' );
				level2c.value(col3);
			level1.children([ level2a, level2b, level2c ]);
			process_subfields(level1.children(),col4);
			data_rows[r].setAttribute('mynode', level1.intra_doc_id());
mw.sdump('D_CAT',' with intra_doc_id = ' + level1.intra_doc_id() + '\n');
			insert_into_tree(tree.children(),data_rows[r],level1);
		}

	}
	//mw.sdump('D_CAT','******\nSending: ' + pretty_print(js2JSON(tree)) + '\n');
	mw.sdump('D_CAT','Auth session: ' + mw.G['auth_ses'][0] + '\n');
	try {
		if (params.import_tree) {

			if (params.new_tree) {
				tree = user_request(
					'open-ils.cat',
					'open-ils.cat.biblio.record_tree.create',
					[ mw.G.auth_ses[0], tree ]
				)[0];
			} else {
				tree = user_request(
					'open-ils.cat',
					'open-ils.cat.biblio.record.tree.import',
					[ mw.G['auth_ses'][0], tree ]
				)[0];
			}
		} else {
			tree = user_request(
					'open-ils.cat',
					'open-ils.cat.biblio.record.tree.commit',
					[ mw.G['auth_ses'][0], tree ]
			)[0];
		}
		if (typeof(tree) == 'object') {
			mw.sdump('D_CAT','\n\n\n\nnew tree = ' + js2JSON(tree) + '\n');
			params.import_tree = false;
			new_node_id = -1;
			empty_grid('ctrl_rows','data_rows');
			build_grid( 
				document.getElementById('ctrl_rows'), 
				document.getElementById('data_rows'), 
				tree
			);
			handle_tag_change();
			my_resize_handler();
			alert('MARC record successfully updated.');
		} else {
			throw('result: ' + tree + '\n');
		}
	} catch(E) {
		mw.sdump('D_CAT','backup_tree\n');
		tree = backup_tree;
		handle_tag_change();
		my_resize_handler();
		handle_error(E);
	}
}

function insert_into_tree(branch,r,n) {
	var s = nextSibling_not_hidden(r);
	if (s) {
		mw.sdump('D_CAT','9th find =========================================\n')
		mw.sdump('D_CAT','s = ' + s + '\n');
		mw.sdump('D_CAT','s.getAttribute mynode = <' + s.getAttribute('mynode') + '>\n');
		var pos = find_element_with_id(branch,s.getAttribute('mynode'));
		branch.splice(pos,0,n);
	} else {
		branch.push(n);
	}
}

var new_node_id = -1;
function populate_node(node,ntype,name) {
	node.intra_doc_id( new_node_id-- );
	node.isnew( 1 );
	node.node_type( ntype );
	node.name( name );
	mw.sdump('D_CAT', node.name() + ':' + node.intra_doc_id() + '.is_new = 1\n');
}

function process_subfields(tfc,datastring) {
	mw.sdump('D_CAT','process_subfields: <' + tfc + '> <' + datastring + '>\n');
	var orig_subfields = [];
	//mw.sdump('D_CAT','\n');
	for (var i in tfc) {
		mw.sdump('D_CAT',i + ' : ' + typeof(tfc[i]) + ' : ' + js2JSON(tfc[i]) + ' : node_type() = ' + tfc[i].node_type() + '\n');
		try {
			if (tfc[i].node_type() == 1) {
				var orig_data = tfc[i].children()[1].value();
				orig_data = orig_data.replace(/^\s+/,'').replace(/\s+$/,'');
				orig_subfields.push( [ 
					i, // subfield node index
					tfc[i].children()[0].value(), // subf indicator
					orig_data // data
				] );
			}

		} catch(E) {
			mw.sdump('D_CAT','\tan error? gasp: ' + js2JSON(E) + '\n');
			continue;
		}
	}
	datastring = datastring.replace(/^\s+/,'').replace(/\s+$/,'');
	var local_subf_array = datastring.split(String.fromCharCode(8225));
	// Our validation routines should assert that the beginning of
	// a data string start with the subfield delimiter symbol.  We're
	// passing the buck of the 'implicit' subfield-a check elsewhere.
	local_subf_array.shift();
	mw.sdump('D_CAT','orig_subfields = ' + js2JSON(orig_subfields) + '\n');
	mw.sdump('D_CAT','local_subfields = ' + js2JSON(local_subf_array) + '\n');
	for (var i in local_subf_array) {
		if ((local_subf_array[i]=='')||(local_subf_array==null)) { continue; }
		var s_ind = local_subf_array[i].substr(0,1);
		var s_data = local_subf_array[i].substr(1).replace(/^\s+/,'').replace(/\s+$/,'');
		mw.sdump('D_CAT','Processing code = ' + s_ind + ' and value = ' + s_data + '\n');
		if (!orig_subfields[i]) { // new subfield
			mw.sdump('D_CAT','making new subfield : i = ' + i + '\n');
			var level1 = new brn(); 
				populate_node( level1, 1, 'subfield' );
			var level2a = new brn(); 
				populate_node( level2a, 2, 'code' );
				level2a.value(s_ind);
			var level2b = new brn();
				populate_node( level2b, 3, null );
				level2b.value(s_data);
			level1.children([ level2a, level2b ]);
			tfc.push(level1);
			mw.sdump('D_CAT','New node = ' + js2JSON(level1) + '\n');
		} else {
			var orig_node = orig_subfields[i][0];
			var orig_ind = orig_subfields[i][1];
			var orig_data = orig_subfields[i][2];
			if (orig_ind != s_ind) { // update subf indicator
				tfc[orig_node].children()[0].value(s_ind);
				tfc[orig_node].children()[0].ischanged(1);
				mw.sdump('D_CAT', tfc[orig_node].children()[0].name() + ':' +
					tfc[orig_node].children()[0].id() + ':' +
					tfc[orig_node].children()[0].intra_doc_id() +
					'.is_changed = 1\n');
			mw.sdump('D_CAT','Updated node = ' + js2JSON(tfc[orig_node].children()[0]) + '\n');
			}
			if (orig_data != s_data) { // update subf data
				tfc[orig_node].children()[1].value(s_data);
				tfc[orig_node].children()[1].ischanged(1);
				mw.sdump('D_CAT', tfc[orig_node].children()[1].name() + ':' +
					tfc[orig_node].children()[1].id() + ':' +
					tfc[orig_node].children()[1].intra_doc_id() +
					'.is_changed = 1\n');
			mw.sdump('D_CAT','Updated node = ' + js2JSON(tfc[orig_node].children()[1]) + '\n');
			}
		}
	}
	// delete any remaining
	for (var i = local_subf_array.length; i < orig_subfields.length; i++) {
		var orig_node = orig_subfields[i][0];
		tfc[orig_node].isdeleted(1);
		mw.sdump('D_CAT', tfc[orig_node].name() + ':' +
			tfc[orig_node].id() + ':' +
			tfc[orig_node].intra_doc_id() + '.is_deleted = 1\n');
		delete_children(tfc[orig_node]);
	}
}



function test_nodeset() {
	return null;
}
