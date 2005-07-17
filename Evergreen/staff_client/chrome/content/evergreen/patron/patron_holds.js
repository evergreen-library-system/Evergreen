sdump('D_TRACE','Loading patron_holds.js\n');

function patron_holds_init(p) {
	sdump('D_PATRON_HOLDS',"TESTING: patron_holds.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	p.patron_holds_cols = hold_cols();

	p.paged_tree = paged_tree_init( { 'w' : p.w, 'node' : p.node, 'cols' : p.patron_holds_cols, 'hide_nav' : true, 'hits_per_page' : '9999', 'debug' : p.app } );
	p.add_patron_holds = p.paged_tree.add_rows;
	p.clear_patron_holds = p.paged_tree.clear_tree;

	p.register_patron_holds_select_callback = function (f) {
		sdump('D_PATRON_HOLDS','p.register_patron_holds_select_callback(' + f + ')\n');
		p.paged_tree.register_select_callback( f );
	}

	p.register_flesh_patron_holds_function = function (f) {
		sdump('D_PATRON_HOLDS','p.register_flesh_patron_holds_function(' + f + ')\n');
		p.paged_tree.register_flesh_row_function( f );
	}

	p.register_item_context_builder = function (f) {
		sdump('D_PATRON_HOLDS','p.register_context_builder(' + f + ')\n');
		p.paged_tree.register_context_builder( f );
	}

	p.map_patron_holds_to_cols = function (patron_holds, treeitem) {
		sdump('D_PATRON_HOLDS','p.map_patron_holds_to_cols( ' + patron_holds + ',' + treeitem + ')\n');
		patron_holds_tree_map_patron_holds_to_cols(p, patron_holds, treeitem);	
	}

	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return p;
}

function patron_holds_tree_map_patron_holds_to_cols(p, patron_holds, treeitem) {
	sdump('D_PATRON_HOLDS',arg_dump(arguments,{1:true}));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var cols = new Array();
	for (var i = 0; i < p.patron_holds_cols.length; i++) {
		var hash = p.patron_holds_cols[i];
		sdump('D_PATRON_HOLDS','Considering ' + js2JSON(hash) + '\n');
		var obj_string = 'patron_holds';
		switch( hash.fm_class ) {
			case 'acp' : obj_string = 'patron_holds.copy'; break;
			case 'circ' : obj_string = 'patron_holds.circ'; break;
			case 'mvr' : obj_string = 'patron_holds.record'; break;
		}
		var cmd = parse_render_string( obj_string, hash.fm_field_render );
		sdump('D_PATRON_HOLDS','cmd = ' + cmd + '\n');
		var col = '';
		try {
			col = eval( cmd );
			sdump('D_PATRON_HOLDS','eval = ' + col + '\n');
		} catch(E) {
			sdump('D_ERROR',js2JSON(E) + '\n');
		}
		cols.push( col );
	}
	sdump('D_PATRON_HOLDS','cols = ' + js2JSON(cols) + '\n');
	p.paged_tree.map_cols_to_treeitem( cols, treeitem );
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}
