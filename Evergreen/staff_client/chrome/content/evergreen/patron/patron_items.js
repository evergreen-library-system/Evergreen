sdump('D_TRACE','Loading patron_items.js\n');

function patron_items_init(p) {
	sdump('D_PATRON_ITEMS',"TESTING: patron_items.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	p.patron_items_cols = circ_cols();

	p.paged_tree = paged_tree_init( { 'w' : p.w, 'node' : p.node, 'cols' : p.patron_items_cols, 'hide_nav' : true, 'hits_per_page' : '9999', 'debug' : p.app } );
	p.add_patron_items = p.paged_tree.add_rows;
	p.clear_patron_items = p.paged_tree.clear_tree;

	p.register_patron_items_select_callback = function (f) {
		sdump('D_PATRON_ITEMS','p.register_patron_items_select_callback(' + f + ')\n');
		p.paged_tree.register_select_callback( f );
	}

	p.register_flesh_patron_items_function = function (f) {
		sdump('D_PATRON_ITEMS','p.register_flesh_patron_items_function(' + f + ')\n');
		p.paged_tree.register_flesh_row_function( f );
	}

	p.register_item_context_builder = function (f) {
		sdump('D_PATRON_ITEMS','p.register_context_builder(' + f + ')\n');
		p.paged_tree.register_context_builder( f );
	}

	p.map_patron_items_to_cols = function (patron_items, treeitem) {
		sdump('D_PATRON_ITEMS','p.map_patron_items_to_cols( ' + patron_items + ',' + treeitem + ')\n');
		patron_items_tree_map_patron_items_to_cols(p, patron_items, treeitem);	
	}

	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return p;
}

function patron_items_tree_map_patron_items_to_cols(p, patron_items, treeitem) {
	sdump('D_PATRON_ITEMS',arg_dump(arguments,{1:true}));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var cols = new Array();
	for (var i = 0; i < p.patron_items_cols.length; i++) {
		var hash = p.patron_items_cols[i];
		sdump('D_PATRON_ITEMS','Considering ' + js2JSON(hash) + '\n');
		var obj_string;
		switch( hash.fm_class ) {
			case 'acp' : obj_string = 'patron_items.copy'; break;
			case 'circ' : obj_string = 'patron_items.circ'; break;
			case 'mvr' : obj_string = 'patron_items.record'; break;
		}
		var cmd = parse_render_string( obj_string, hash.fm_field_render );
		sdump('D_PATRON_ITEMS','cmd = ' + cmd + '\n');
		var col = '';
		try {
			col = eval( cmd );
			sdump('D_PATRON_ITEMS','eval = ' + col + '\n');
		} catch(E) {
			sdump('D_ERROR',js2JSON(E) + '\n');
		}
		cols.push( col );
	}
	sdump('D_PATRON_ITEMS','cols = ' + js2JSON(cols) + '\n');
	p.paged_tree.map_cols_to_treeitem( cols, treeitem );
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}
