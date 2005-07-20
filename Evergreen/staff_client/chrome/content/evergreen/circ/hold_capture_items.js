sdump('D_TRACE','Loading hold_capture_items.js\n');

function hold_capture_items_init(p) {
	sdump('D_HOLD_CAPTURE_ITEMS',"TESTING: hold_capture_items.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	p.hold_capture_items_cols = checkin_cols();

	p.paged_tree = paged_tree_init( { 'w' : p.w, 'node' : p.node, 'cols' : p.hold_capture_items_cols, 'hide_nav' : true, 'hits_per_page' : '9999', 'debug' : p.app } );
	p.add_hold_capture_items = p.paged_tree.add_rows;
	p.clear_hold_capture_items = p.paged_tree.clear_tree;

	p.register_hold_capture_items_select_callback = function (f) {
		sdump('D_HOLD_CAPTURE_ITEMS','p.register_hold_capture_items_select_callback(' + f + ')\n');
		p.paged_tree.register_select_callback( f );
	}

	p.register_flesh_hold_capture_items_function = function (f) {
		sdump('D_HOLD_CAPTURE_ITEMS','p.register_flesh_hold_capture_items_function(' + f + ')\n');
		p.paged_tree.register_flesh_row_function( f );
	}

	p.register_context_builder = function (f) {
		sdump('D_HOLD_CAPTURE_ITEMS','p.register_context_builder(' + f + ')\n');
		p.paged_tree.register_context_builder( f );
	}

	p.map_hold_capture_items_to_cols = function (hold_capture_items, treeitem) {
		sdump('D_HOLD_CAPTURE_ITEMS','p.map_hold_capture_items_to_cols( ' + hold_capture_items + ',' + treeitem + ')\n');
		hold_capture_items_tree_map_hold_capture_items_to_cols(p, hold_capture_items, treeitem);	
	}

	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return p;
}

function hold_capture_items_tree_map_hold_capture_items_to_cols(p, hold_capture_items, treeitem) {
	sdump('D_HOLD_CAPTURE_ITEMS',arg_dump(arguments,{1:true}));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var cols = new Array();
	for (var i = 0; i < p.hold_capture_items_cols.length; i++) {
		var hash = p.hold_capture_items_cols[i];
		sdump('D_HOLD_CAPTURE_ITEMS','Considering ' + js2JSON(hash) + '\n');
		var obj_string = 'hold_capture_items';
		switch( hash.fm_class ) {
			case 'acp' : obj_string = 'hold_capture_items.copy'; break;
			case 'circ' : obj_string = 'hold_capture_items.circ'; break;
			case 'mvr' : obj_string = 'hold_capture_items.record'; break;
		}
		var cmd = parse_render_string( obj_string, hash.fm_field_render );
		sdump('D_HOLD_CAPTURE_ITEMS','cmd = ' + cmd + '\n');
		var col = '';
		try {
			col = eval( cmd );
			sdump('D_HOLD_CAPTURE_ITEMS','eval = ' + col + '\n');
		} catch(E) {
			sdump('D_ERROR',js2JSON(E) + '\n');
		}
		cols.push( col );
	}
	sdump('D_HOLD_CAPTURE_ITEMS','cols = ' + js2JSON(cols) + '\n');
	p.paged_tree.map_cols_to_treeitem( cols, treeitem );
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}
