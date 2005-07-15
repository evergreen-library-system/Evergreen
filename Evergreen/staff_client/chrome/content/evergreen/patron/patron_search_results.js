sdump('D_TRACE','Loading patron_search_results.js\n');

function patron_search_results_init(p) {
	sdump('D_PATRON_SEARCH_RESULTS',"TESTING: patron_search_results.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_TRACE_ENTER',arg_dump(arguments));

	p.patron_cols = [
		{ 
			'id' : 'id_col', 'label' : getString('au_label_id'), 'flex' : 1, 
			'primary' : true, 'hidden' : false, 'fm_field_render' : '.id()'
		},
		{ 
			'id' : 'prefix_col', 'label' : getString('au_label_prefix'), 'flex' : 1, 
			'primary' : false, 'hidden' : false, 'fm_field_render' : '.prefix()'
		},
		{ 
			'id' : 'family_name_col', 'label' : getString('au_label_family_name'), 'flex' : 1, 
			'primary' : false, 'hidden' : false, 'fm_field_render' : '.family_name()'
		},
		{ 
			'id' : 'first_given_name_col', 'label' : getString('au_label_first_given_name'), 'flex' : 1, 
			'primary' : false, 'hidden' : false, 'fm_field_render' : '.first_given_name()'
		},
		{ 
			'id' : 'second_given_name_col', 'label' : getString('au_label_second_given_name'), 'flex' : 1, 
			'primary' : false, 'hidden' : false, 'fm_field_render' : '.second_given_name()'
		},
		{ 
			'id' : 'suffix_col', 'label' : getString('au_label_suffix'), 'flex' : 1, 
			'primary' : false, 'hidden' : false, 'fm_field_render' : '.suffix()'
		}
	];

	p.paged_tree = paged_tree_init( { 'w' : p.w, 'node' : p.node, 'cols' : p.patron_cols, 'debug' : p.app } );
	p.add_patrons = p.paged_tree.add_rows;
	p.clear_patrons = p.paged_tree.clear_tree;

	p.register_patron_select_callback = function (f) {
		sdump('D_PATRON_SEARCH_RESULTS','p.register_patron_select_callback(' + f + ')\n');
		p.paged_tree.register_select_callback( f );
	}

	p.register_flesh_patron_function = function (f) {
		sdump('D_PATRON_SEARCH_RESULTS','p.register_flesh_patron_function(' + f + ')\n');
		p.paged_tree.register_flesh_row_function( f );
	}

	p.register_context_builder = function (f) {
		sdump('D_PATRON_SEARCH_RESULTS','p.register_context_builder(' + f + ')\n');
		p.paged_tree.register_context_builder( f );
	}

	p.map_patron_to_cols = function (patron, treeitem) {
		sdump('D_PATRON_SEARCH_RESULTS','p.map_patron_to_cols(' + patron + ',' + treeitem + ')\n');
		patron_search_results_map_patron_to_cols(p, patron, treeitem);	
	}

	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return p;
}

function patron_search_results_map_patron_to_cols(p, patron, treeitem) {
	sdump('D_PATRON_SEARCH_RESULTS',arg_dump(arguments));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var cols = new Array();
	for (var i = 0; i < p.patron_cols.length; i++) {
		var hash = p.patron_cols[i];
		sdump('D_PATRON_SEARCH_RESULTS','Considering ' + js2JSON(hash) + '\n');
		var cmd = 'patron'+hash.fm_field_render;
		sdump('D_PATRON_SEARCH_RESULTS','cmd = ' + cmd + '\n');
		var col = '';
		try {
			col = eval( cmd );
			sdump('D_PATRON_SEARCH_RESULTS','eval = ' + col + '\n');
		} catch(E) {
			sdump('D_ERROR',js2JSON(E) + '\n');
		}
		cols.push( col );
	}
	sdump('D_PATRON_SEARCH_RESULTS','cols = ' + js2JSON(cols) + '\n');
	p.paged_tree.map_cols_to_treeitem( cols, treeitem );
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}
