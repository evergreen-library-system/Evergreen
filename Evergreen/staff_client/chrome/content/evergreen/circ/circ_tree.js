sdump('D_TRACE','Loading circ_tree.js\n');

function circ_tree_init(p) {
	sdump('D_CIRC_TREE',"TESTING: circ_tree.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_TRACE_ENTER',arg_dump(arguments));

	p.w.circ_cols = [
		{
			'id' : 'barcode', 'label' : getString('acp_label_barcode'), 'flex' : 1,
			'primary' : true, 'hidden' : false, 'fm_class' : 'acp', 'fm_field_render' : '.barcode()'
		},
		{
			'id' : 'call_number', 'label' : getString('acp_label_call_number'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.call_number()'
		},
		{
			'id' : 'copy_number', 'label' : getString('acp_label_copy_number'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.copy_number()'
		},
		{
			'id' : 'status', 'label' : getString('acp_label_status'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.status()'
		},
		{
			'id' : 'location', 'label' : getString('acp_label_location'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.location()'
		},
		{
			'id' : 'loan_duration', 'label' : getString('acp_label_loan_duration'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.loan_duration()'
		},
		{
			'id' : 'circ_lib', 'label' : getString('acp_label_circ_lib'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.circ_lib()'
		},
		{
			'id' : 'fine_level', 'label' : getString('acp_label_fine_level'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.fine_level()'
		},
		{
			'id' : 'deposit', 'label' : getString('acp_label_deposit'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.deposit()'
		},
		{
			'id' : 'deposit_amount', 'label' : getString('acp_label_deposit_amount'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.deposit_amount()'
		},
		{
			'id' : 'price', 'label' : getString('acp_label_price'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.price()'
		},
		{
			'id' : 'circ_as_type', 'label' : getString('acp_label_circ_as_type'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.circ_as_type()'
		},
		{
			'id' : 'circ_modifier', 'label' : getString('acp_label_circ_modifier'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'acp', 'fm_field_render' : '.circ_modifier()'
		},
		{
			'id' : 'xact_start', 'label' : getString('circ_label_xact_start'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'circ', 'fm_field_render' : '.xact_start()'
		},
		{
			'id' : 'xact_finish', 'label' : getString('circ_label_xact_finish'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'fm_class' : 'circ', 'fm_field_render' : '.xact_finish()'
		},
		{
			'id' : 'renewal_remaining', 'label' : getString('circ_label_renewal_remaining'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'circ', 'fm_field_render' : '.renewal_remaining()'
		},
		{
			'id' : 'due_date', 'label' : getString('circ_label_due_date'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'circ', 'fm_field_render' : '.due_date()'
		},
		{
			'id' : 'title', 'label' : getString('mvr_label_title'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mvr', 'fm_field_render' : '.title()'
		},
		{
			'id' : 'author', 'label' : getString('mvr_label_author'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mvr', 'fm_field_render' : '.author()'
		}
		
	];

	p.w.register_circ_select_callback = function (f) {
		p.w._circ_select_callback = f;
	}

	p.w.register_flesh_circ_function = function (f) {
		p.w._flesh_circ_function = f;
	}

	p.w.register_context_builder = function (f) {
		p.w._context_function = f;
	}

	p.w.map_circ_to_cols = function (circ, treeitem) {
		circ_tree_map_circ_to_cols(p, circ, treeitem);	
	}

	setTimeout(
		function() {
			sdump('D_TIMEOUT','***** timeout occured circ_tree.js');
		        p.w.tree_win = spawn_paged_tree(
		                p.w.document, 'new_iframe', p.paged_tree, {
					'hide_nav' : true,
					'hits_per_page' : 99999, 
					'cols' : p.w.circ_cols,
					'onload' : circ_tree_init_after_paged_tree(p) 
				}
		        );
			setTimeout(
				function () {
					sdump('D_TIMEOUT','***** timeout timeout occured circ_tree.js');
				        if (p.onload) {
				                try {
							sdump('D_TRACE','trying psuedo-onload: ' + p.onload + '\n');
				                        p.onload(p.w);
				                } catch(E) {
				                        sdump('D_ERROR', js2JSON(E) + '\n' );
				                }
				        }
				}, 0
			);
		}, 0
	);

	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return;
}

function circ_tree_init_after_paged_tree(p) {
	sdump('D_CIRC_TREE',arg_dump(arguments));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var result = function (tree_win) {
		sdump('D_TRACE_ENTER',arg_dump(arguments));
		sdump('D_CIRC_TREE',arg_dump(arguments));
		tree_win.register_select_callback( p.w._circ_select_callback );
		tree_win.register_flesh_row_function( p.w._flesh_circ_function );
		tree_win.register_context_builder( p.w._context_function );
		p.w.add_circs = tree_win.add_rows;
		p.w.clear_circs = tree_win.clear_tree;
		setTimeout(
			function() {
				sdump('D_TIMEOUT','***** timeout after paged_tree occured circ_tree.js');
				try {
					if (p.paged_tree_onload) p.paged_tree_onload(tree_win);
				} catch(E) {
		                        sdump('D_ERROR', js2JSON(E) + '\n' );
				}
			}, 0
		);
		sdump('D_TRACE_EXIT',arg_dump(arguments));
		return;
	};
	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return result;
}

function circ_tree_map_circ_to_cols(p, circ, treeitem) {
	sdump('D_CIRC_TREE',arg_dump(arguments,{1:true}));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var cols = new Array();
	for (var i = 0; i < p.w.circ_cols.length; i++) {
		var hash = p.w.circ_cols[i];
		sdump('D_CIRC_TREE','Considering ' + js2JSON(hash) + '\n');
		var obj_string;
		switch( hash.fm_class ) {
			case 'acp' : obj_string = 'circ.copy'; break;
			case 'circ' : obj_string = 'circ.circ'; break;
			case 'mvr' : obj_string = 'circ.record'; break;
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
