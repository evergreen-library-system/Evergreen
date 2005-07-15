sdump('D_TRACE','Loading paged_tree.js\n');

function paged_tree_init(p) {
	sdump('D_PAGED_TREE',"TESTING: paged_tree.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	p.current_idx = 0;

	p.tree = p.node.getElementsByAttribute('name','tree')[0];
	p.popup = p.popupset_node.getElementsByAttribute('name','tree')[0];
	p.treecols = p.tree.firstChild;
	p.tc = p.tree.lastChild;

	p._context_function = function (ev) { alert('default _context_function'); };
	p.popup.addEventListener('popupshowing',function (ev) { return p._context_function(ev); },false);

	p._select_callback = function (ev) { alert('default _select_callback'); };
	p.tree.addEventListener('select',function (ev) { return p._select_callback(ev); },false);

	paged_tree_make_columns( p, p.treecols, p.cols )

	p.clear_tree = function () {
		sdump('D_PAGED_TREE','p.clear_tree()\n');
		empty_widget( p.w.document, p.tc );
		p.current_idx = 0;
		return paged_tree_update_nav(p);
	}

	p.add_rows = function (ids) { 
		sdump('D_PAGED_TREE','p.add_rows()\n');
		return paged_tree_add_rows(p,p.tc,ids); 
	}

	p.register_flesh_row_function = function (f) { 
		sdump('D_PAGED_TREE','p.register_flesh_row_function(' + f + ')\n');
		return p._flesh_row_function = f; 
	}

	p.register_select_callback = function (f) { 
		sdump('D_PAGED_TREE','p.register_select_callback(' + f + ')\n');
		return p._select_callback = f; 
	}

	p.register_context_builder = function (f) {
		sdump('D_PAGED_TREE','p.register_context_builder(' + f + ')\n');
		return p._context_function = f;
	}

	p.map_cols_to_treeitem = map_array_to_treecells_via_treeitem;

	p.nav_bar = p.node.getElementsByAttribute('name','nav')[0];
	if (p.hide_nav) p.nav_bar.hidden = p.hide_nav;

	p.results_label = p.nav_bar.getElementsByAttribute('name','label_results')[0];
	p.range_label = p.nav_bar.getElementsByAttribute('name','label_range')[0];

	p.next_button = p.nav_bar.getElementsByAttribute('name','button_next')[0];
	p.prev_button = p.nav_bar.getElementsByAttribute('name','button_prev')[0];

	p.hits_per_page_menu = p.nav_bar.getElementsByAttribute('name','hits_per_page')[0];
	if (p.hits_per_page) {
		p.display_count = parseInt( p.hits_per_page );
	} else {
		p.display_count = parseInt( p.hits_per_page_menu.getAttribute('value') );
	}

	p.set_hits_per_page = function (ev) {
		try {
			p.display_count = parseInt( p.hits_per_page_menu.getAttribute('value') );
			paged_tree_update_visibility( p );
			paged_tree_update_nav( p );
			paged_tree_flesh_records( p );
		} catch(E) {
			sdump('D_ERROR',js2JSON(E)+'\n');
		}
	}
	p.hits_per_page_menu.addEventListener(
		'command',
		p.set_hits_per_page,
		false
	);

	var cmd_next = p.commandset_node.getElementsByAttribute('id', 'cmd_tree_next' )[0];
	cmd_next.addEventListener(
		'command',
		function (ev) {
			var backup_select_callback = p._select_callback;
			p._select_callback = function (ev) {};
			var result = paged_tree_nav_next(p);
			p._select_callback = backup_select_callback;
			return result;
		},
		false
	);

	var cmd_prev = p.commandset_node.getElementsByAttribute('id', 'cmd_tree_prev' )[0];
	cmd_prev.addEventListener(
		'command',
		function (ev) {
			var backup_select_callback = p._select_callback;
			p._select_callback = function (ev) {};
			var result = paged_tree_nav_prev(p);
			p._select_callback = backup_select_callback;
			return result;
		},
		false
	);

	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return p;
}

function paged_tree_make_columns( p, treecols, cols ) {
	sdump('D_PAGED_TREE',arg_dump(arguments,{2:'.length'}));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var d = p.w.document;
	// cols[ idx ] = { 'id':???, 'label':???, 'primary':???, 'flex':??? }
	for (var i = 0; i < cols.length; i++) {
		var col = cols[i];
		sdump('D_PAGED_TREE','Col ' + i + ' : ' + js2JSON( col ) + '\n');
		var treecol = d.createElement( 'treecol' );
		treecols.appendChild( treecol );
		for (var j in col) {
			treecol.setAttribute( j, col[j] );
		}
		var splitter = d.createElement( 'splitter' );
		treecols.appendChild(splitter);
		splitter.setAttribute('class','tree-splitter');
	}
	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return treecols;
}

function paged_tree_add_rows( p, tc, ids ) {
	sdump('D_PAGED_TREE',arg_dump(arguments,{2:'.length'}));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var d = p.w.document;
	var offset = 0;
	if (tc.childNodes.length > 0) { offset = tc.lastChild.id; }
	for (var i = 0; i < ids.length; i++) {
		var id = ids[i];

		var treeitem = d.createElement( 'treeitem' );
		treeitem.setAttribute( 'id', i+offset+1 );
		treeitem.setAttribute( 'record_id', id );
		treeitem.setAttribute( 'retrieved', 'false' );
		if ( (i+offset) < (p.display_count + p.current_idx) ) {
			treeitem.setAttribute( 'hidden', 'false' );
		} else {
			treeitem.setAttribute( 'hidden', 'true' );
		}
		tc.appendChild( treeitem );

		var treerow = d.createElement( 'treerow' );
		treeitem.appendChild( treerow );

		for (var j = 0; j < p.treecols.childNodes.length; j++) {
			var treecell = d.createElement( 'treecell' );
			if (j == 0)
				treecell.setAttribute('label', getString('retrieving.record') );
			else
				treecell.setAttribute('label', '' );
			treerow.appendChild( treecell );
		}
	}
	paged_tree_update_visibility( p );
	paged_tree_update_nav( p );
	paged_tree_flesh_records( p );
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

function paged_tree_flesh_record(p,treeitem) {
	sdump('D_PAGED_TREE',arg_dump(arguments));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	treeitem.setAttribute('retrieved','true');
	if (p._flesh_row_function) {
		p._flesh_row_function( treeitem );
	}
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

function paged_tree_flesh_records(p) {
	sdump('D_PAGED_TREE',arg_dump(arguments));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	for (var i = 0; i < p.tc.childNodes.length; i++) {
		var treeitem = p.tc.childNodes[i];
		if ( (treeitem.hidden == false) && (treeitem.getAttribute('retrieved')=='false') ) {
			paged_tree_flesh_record(p,treeitem);
		}
	}
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

function paged_tree_update_nav(p) {
	sdump('D_PAGED_TREE',arg_dump(arguments));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	if (p.results_label)
		p.results_label.setAttribute('value', p.tc.childNodes.length );

	var min = p.current_idx + 1;
	var max = p.current_idx + p.display_count;
	if (max > p.tc.childNodes.length)
		max = p.tc.childNodes.length;
	if (p.range_label) {
		if (max > 0)
			p.range_label.setAttribute('value', min + ' - ' + max );
		else
			p.range_label.setAttribute('value', '0 - 0' );
	}

	if (p.next_button) {
		if (max < p.tc.childNodes.length)
			p.next_button.disabled = false;
		else
			p.next_button.disabled = true;
	}

	if (p.prev_button) {
		if (min == 1)
			p.prev_button.disabled = true;
		else
			p.prev_button.disabled = false;
	}
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

function paged_tree_update_visibility(p) {
	sdump('D_PAGED_TREE',arg_dump(arguments));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	for (var i = 0; i < p.tc.childNodes.length; i++) {
		var treeitem = p.tc.childNodes[i];
		if ( (i >= p.current_idx) && (i < (p.current_idx+p.display_count)) )
			treeitem.hidden = false;
		else
			treeitem.hidden = true;
	}
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

function paged_tree_nav_next(p) {
	sdump('D_PAGED_TREE',arg_dump(arguments));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var proposed_idx = p.current_idx + p.display_count;
	if (proposed_idx >= p.tc.childNodes.length)
		proposed_idx = p.tc.childNodes.length - 1;
	p.current_idx = proposed_idx;
	paged_tree_update_visibility(p);
	paged_tree_update_nav(p);
	paged_tree_flesh_records(p);
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

function paged_tree_nav_prev(p) {
	sdump('D_PAGED_TREE',arg_dump(arguments));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var proposed_idx = p.current_idx - p.display_count;
	if (proposed_idx < 0)
		proposed_idx = 0;
	p.current_idx = proposed_idx;
	paged_tree_update_visibility(p);
	paged_tree_update_nav(p);
	paged_tree_flesh_records(p);
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

