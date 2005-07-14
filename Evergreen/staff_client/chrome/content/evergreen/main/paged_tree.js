sdump('D_TRACE','Loading paged_tree.js\n');

function paged_tree_init(p) {
	sdump('D_PAGED_TREE',"TESTING: paged_tree.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_TRACE_ENTER',arg_dump(arguments));

	p.w.current_idx = 0;

	p.w.results_label = get_widget( p.w.document, p.nav_results );
	p.w.range_label = get_widget( p.w.document, p.nav_range );

	p.w.hits_per_page_menu = get_widget( p.w.document, p.nav_hits_per_page );
	if (p.hits_per_page) 
		p.w.display_count = parseInt( p.hits_per_page );
	else 
		p.w.display_count = parseInt( p.w.hits_per_page_menu.getAttribute('value') );

	p.w.next_button = get_widget( p.w.document, p.nav_next );
	p.w.prev_button = get_widget( p.w.document, p.nav_prev );

	p.w.nav_bar = get_widget( p.w.document, p.nav_bar );
	if (p.hide_nav) p.w.nav_bar.hidden = p.hide_nav;

	/*
	// Doesn't work for some reason
	var cmd_set_hits_per_page = get_widget( p.w.document, 'cmd_set_hits_per_page' );
	cmd_set_hits_per_page.addEventListener(
		'command',
		function (ev) {
			sdump('D_TRACE','In set_hits handler\n');
			alert('testing123');
			try {
				p.w.display_count = parseInt( p.w.hits_per_page_menu.getAttribute('value') );
				paged_tree_update_visibility( p );
				paged_tree_update_nav( p );
				paged_tree_flesh_records( p );
			} catch(E) {
				sdump('D_ERROR',js2JSON(E)+'\n');
			}
			sdump('D_TRACE','Leaving set_hits handler\n');
		},
		false
	);
	*/

	p.w.set_hits_per_page = function () {
		try {
			p.w.display_count = parseInt( p.w.hits_per_page_menu.getAttribute('value') );
			paged_tree_update_visibility( p );
			paged_tree_update_nav( p );
			paged_tree_flesh_records( p );
		} catch(E) {
			sdump('D_ERROR',js2JSON(E)+'\n');
		}
	}

	var cmd_next = get_widget( p.w.document, 'cmd_next' );
	cmd_next.addEventListener(
		'command',
		function (ev) {
			var backup_select_callback = p.w._select_callback;
			p.w._select_callback = function (ev) {};
			var result = paged_tree_nav_next(p);
			p.w._select_callback = backup_select_callback;
			return result;
		},
		false
	);

	var cmd_prev = get_widget( p.w.document, 'cmd_prev' );
	cmd_prev.addEventListener(
		'command',
		function (ev) {
			var backup_select_callback = p.w._select_callback;
			p.w._select_callback = function (ev) {};
			var result = paged_tree_nav_prev(p);
			p.w._select_callback = backup_select_callback;
			return result;
		},
		false
	);

	p.w.tree = get_widget(p.w.document,p.paged_tree);
	p.w.popup = get_widget(p.w.document,p.popup);
	p.w.treecols = p.w.tree.firstChild;
	p.w.tc = p.w.tree.lastChild;

	p.w._context_function = function (ev) {};
	p.w.popup.addEventListener('popupshowing',function (ev) { return p.w._context_function(ev); },false);

	p.w._select_callback = function (ev) {};
	p.w.tree.addEventListener('select',function (ev) { return p.w._select_callback(ev); },false);

	paged_tree_make_columns( p, p.w.treecols, p.cols )

	p.w.clear_tree = function () {
		empty_widget( p.w.document, p.w.tc );
		p.w.current_idx = 0;
		return paged_tree_update_nav(p);
	}

	p.w.add_rows = function (ids) { 
		return paged_tree_add_rows(p,p.w.tc,ids); 
	}

	p.w.register_flesh_row_function = function (f) { 
		return p.w._flesh_row_function = f; 
	}

	p.w.register_select_callback = function (f) { 
		return p.w._select_callback = f; 
	}

	p.w.register_context_builder = function (f) {
		return p.w._context_function = f;
	}

	p.w.map_cols_to_treeitem = map_array_to_treecells_via_treeitem;

	setTimeout(
		function() {
			sdump('D_TIMEOUT','***** timeout occured paged_tree.js');
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
	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return;
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
		if ( (i+offset) < (p.w.display_count + p.w.current_idx) ) {
			treeitem.setAttribute( 'hidden', 'false' );
		} else {
			treeitem.setAttribute( 'hidden', 'true' );
		}
		tc.appendChild( treeitem );

		var treerow = d.createElement( 'treerow' );
		treeitem.appendChild( treerow );

		for (var j = 0; j < p.w.treecols.childNodes.length; j++) {
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
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	treeitem.setAttribute('retrieved','true');
	if (p.w._flesh_row_function) {
		p.w._flesh_row_function( treeitem );
	}
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

function paged_tree_flesh_records(p) {
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	for (var i = 0; i < p.w.tc.childNodes.length; i++) {
		var treeitem = p.w.tc.childNodes[i];
		if ( (treeitem.hidden == false) && (treeitem.getAttribute('retrieved')=='false') ) {
			paged_tree_flesh_record(p,treeitem);
		}
	}
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

function paged_tree_update_nav(p) {
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	if (p.w.results_label)
		p.w.results_label.setAttribute('value', p.w.tc.childNodes.length );

	var min = p.w.current_idx + 1;
	var max = p.w.current_idx + p.w.display_count;
	if (max > p.w.tc.childNodes.length)
		max = p.w.tc.childNodes.length;
	if (p.w.range_label) {
		if (max > 0)
			p.w.range_label.setAttribute('value', min + ' - ' + max );
		else
			p.w.range_label.setAttribute('value', '0 - 0' );
	}

	if (p.w.next_button) {
		if (max < p.w.tc.childNodes.length)
			p.w.next_button.disabled = false;
		else
			p.w.next_button.disabled = true;
	}

	if (p.w.prev_button) {
		if (min == 1)
			p.w.prev_button.disabled = true;
		else
			p.w.prev_button.disabled = false;
	}
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

function paged_tree_update_visibility(p) {
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	for (var i = 0; i < p.w.tc.childNodes.length; i++) {
		var treeitem = p.w.tc.childNodes[i];
		if ( (i >= p.w.current_idx) && (i < (p.w.current_idx+p.w.display_count)) )
			treeitem.hidden = false;
		else
			treeitem.hidden = true;
	}
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

function paged_tree_nav_next(p) {
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var proposed_idx = p.w.current_idx + p.w.display_count;
	if (proposed_idx >= p.w.tc.childNodes.length)
		proposed_idx = p.w.tc.childNodes.length - 1;
	p.w.current_idx = proposed_idx;
	paged_tree_update_visibility(p);
	paged_tree_update_nav(p);
	paged_tree_flesh_records(p);
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

function paged_tree_nav_prev(p) {
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var proposed_idx = p.w.current_idx - p.w.display_count;
	if (proposed_idx < 0)
		proposed_idx = 0;
	p.w.current_idx = proposed_idx;
	paged_tree_update_visibility(p);
	paged_tree_update_nav(p);
	paged_tree_flesh_records(p);
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

