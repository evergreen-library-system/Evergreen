sdump('D_TRACE','Loading patron_search_results.js\n');

function patron_search_results_init(p) {
	sdump('D_PATRON_SEARCH_RESULTS',"TESTING: patron_search_results.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_TRACE_ENTER',arg_dump(arguments));

	p.w.patron_cols = [
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

        p.w.tree_win = spawn_paged_tree(
                p.w.document, 'new_iframe', p.paged_tree, { 
			'cols' : p.w.patron_cols,
			'onload' : patron_search_results_init_after_paged_tree(p) 
		}
        );

	p.w.register_patron_select_callback = function (f) {
		p.w._patron_select_callback = f;
	}

	p.w.register_flesh_patron_function = function (f) {
		p.w._flesh_patron_function = f;
	}

	p.w.map_patron_to_cols = function (patron, treeitem) {
		patron_search_results_map_patron_to_cols(p, patron, treeitem);	
	}

        if (p.onload) {
                try {
			sdump('D_TRACE','trying psuedo-onload: ' + p.onload + '\n');
                        p.onload(p.w);
                } catch(E) {
                        sdump('D_ERROR', js2JSON(E) + '\n' );
                }
        }
	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return;
}

function patron_search_results_init_after_paged_tree(p) {
	sdump('D_PATRON_SEARCH_RESULTS',arg_dump(arguments));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return function (tree_win) {
		sdump('D_TRACE_ENTER',arg_dump(arguments));
		sdump('D_PATRON_SEARCH_RESULTS',arg_dump(arguments));
		tree_win.register_select_callback( p.w._patron_select_callback );
		tree_win.register_flesh_row_function( p.w._flesh_patron_function );
		p.w.add_patrons = tree_win.add_rows;
		sdump('D_TRACE_EXIT',arg_dump(arguments));
		return;
	};
}

function patron_search_results_map_patron_to_cols(p, patron, treeitem) {
	sdump('D_PATRON_SEARCH_RESULTS',arg_dump(arguments));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var cols = new Array();
	for (var i = 0; i < p.w.patron_cols.length; i++) {
		var hash = p.w.patron_cols[i];
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
	p.w.tree_win.map_cols_to_treeitem( cols, treeitem );
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}
