sdump('D_TRACE','Loading patron_items.js\n');

function patron_items_init(p) {
	sdump('D_PATRON_ITEMS',"TESTING: patron_items.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	p.patron_items_cols = circ_cols; /* clone if you're going to modify.  ie. js2JSON(JSON2js(circ_cols)); */

	p._patron_items_select_callback = function(){};
	p._flesh_patron_items_function = function(){};
	p._context_function = function(){};

	p.register_patron_items_select_callback = function (f) {
		p._patron_items_select_callback = f;
	}

	p.register_flesh_patron_items_function = function (f) {
		p._flesh_patron_items_function = f;
	}

	p.register_context_builder = function (f) {
		p._context_function = f;
	}

	p.map_patron_items_to_cols = function (patron_items, treeitem) {
		patron_items_tree_map_patron_items_to_cols(p, patron_items, treeitem);	
	}

	p.paged_tree = paged_tree_init( { 'w' : p.w, 'node' : p.node, 'popupset_node' : p.popupset_node, 'commandset_node' : p.commandset_node, 'cols' : p.patron_items_cols, 'debug' : p.app } );
	p.paged_tree.register_select_callback( p._patron_items_select_callback );
	p.paged_tree.register_flesh_row_function( p._flesh_patron_items_function );
	p.paged_tree.register_context_builder( p._context_function );
	p.add_patron_items = p.paged_tree.add_rows;
	p.clear_patron_items = p.paged_tree.clear_tree;


	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return p;
}

function patron_items_tree_map_patron_items_to_cols(p, patron_items, treeitem) {
	sdump('D_CIRC_TREE',arg_dump(arguments,{1:true}));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var cols = new Array();
	for (var i = 0; i < p.patron_items_cols.length; i++) {
		var hash = p.patron_items_cols[i];
		sdump('D_CIRC_TREE','Considering ' + js2JSON(hash) + '\n');
		var obj_string;
		switch( hash.fm_class ) {
			case 'acp' : obj_string = 'patron_items.copy'; break;
			case 'patron_items' : obj_string = 'patron_items.patron_items'; break;
			case 'mvr' : obj_string = 'patron_items.record'; break;
		}
		var cmd = parse_render_string( obj_string, hash.fm_field_render );
		sdump('D_CIRC_TREE','cmd = ' + cmd + '\n');
		var col = '';
		try {
			col = eval( cmd );
			sdump('D_CIRC_TREE','eval = ' + col + '\n');
		} catch(E) {
			sdump('D_ERROR',js2JSON(E) + '\n');
		}
		cols.push( col );
	}
	sdump('D_CIRC_TREE','cols = ' + js2JSON(cols) + '\n');
	p.w.tree_win.map_cols_to_treeitem( cols, treeitem );
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}
