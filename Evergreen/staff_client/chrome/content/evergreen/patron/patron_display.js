sdump('D_TRACE','Loading patron_display.js\n');

function patron_display_init(p) {
	sdump('D_PATRON_DISPLAY',"TESTING: patron_display.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));


	// gives: p.clamshell, p.right_panel, p.left_panel, p.inner_left_clamshell, p.inner_top_panel, p.inner_bottom_panel
	patron_display_clamshell_init(p);

	// gives: p.patron_items, p.redraw_patron_items
	patron_display_patron_items_init(p);

	p.set_patron = function (au) {
		return p._patron = au;
	}

	p.display_patron = function (au) {
		if (au) p.set_patron(au);
		p.redraw_patron_items();
		return render_fm(p.w.document, { 'au' : p._patron });
	}

	p.retrieve_patron_via_barcode = function (barcode) {
		if (!barcode) barcode = patron_get_barcode( p._patron );
		p.set_patron( retrieve_patron_by_barcode( barcode ) );
		return p.display_patron();
	}

	p.retrieve_patron_via_id = function (id) {
		p.set_patron( retrieve_patron_by_id( id ) );
		return p.display_patron();
	}

	p.refresh = function() {
		if (p._patron) p.retrieve_patron_via_id( p._patron.id() );
	}

	p.commandset_node.getElementsByAttribute('id','cmd_patron_refresh')[0].addEventListener(
		'command',
		function (ev) {
			p.refresh();
		},
		false
	);

	function gen_func(i) {
		// because otherwise i would be 5 for each closure
		return function(ev) {
			dump('i = ' + i + '\n');
			p.clamshell.set_second_deck(i);
		};
	}
	var cmds = [ 'cmd_patron_checkout', 'cmd_patron_items', 'cmd_patron_holds', 
		'cmd_patron_bills', 'cmd_patron_edit', 'cmd_patron_info' ]
	for (var i in cmds) {
		p.commandset_node.getElementsByAttribute('id',cmds[i])[0].addEventListener(
			'command',
			gen_func(i),
			false
		);
	}

	if (p.patron) {
		if (typeof(p.patron) == 'object') {
			p._patron = p.patron;
			p.display_patron();
		} else
			p.retrieve_patron_via_barcode( p.patron );
	}

	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return p;
}

function patron_display_clamshell_init(p) {
	p.clamshell = clam_shell_init( { 'w' : p.w, 'node' : p.clamshell_node, 'debug' : p.app } );
	p.left_panel = p.clamshell.first_deck;
	p.right_panel = p.clamshell.second_deck;

	p.inner_left_clamshell = clam_shell_init( { 'w' : p.w, 'node' : p.left_panel.firstChild, 'debug' : p.app } );
	p.inner_top_panel = p.inner_left_clamshell.first_deck;
	p.inner_bottom_panel = p.inner_left_clamshell.second_deck;
}

function patron_display_patron_items_init(p) {
	p.patron_items = patron_items_init( { 'w' : p.w, 'node' : p.patron_items_node, 'popupset_node' : p.popupset_node, 'commandset_node' : p.commandset_node, 'debug' : p.app } );

	p.redraw_patron_items = function() {
		p.patron_items.clear_patron_items();
		if (!p._patron.checkouts()) patron_get_checkouts( p._patron );
		for (var i = 0; i < p._patron.checkouts().length; i++) {
			p.patron_items.add_patron_items( [ i ] );
		}
	}

	p.patron_items.register_patron_items_select_callback(
		function (ev) {
			sdump('D_PATRON_DISPLAY','Firing patron_items_select_callback\n');
			var patron_items = get_list_from_tree_selection( p.patron_items.paged_tree.tree );
			/* grab cover art for selected item? */
		}
	);
	p.patron_items.register_flesh_patron_items_function(
		function (treeitem) {
			sdump('D_PATRON_DISPLAY','Firing flesh_patron_items_function\n');
			var record_id = treeitem.getAttribute('record_id'); 
			p.patron_items.map_patron_items_to_cols( p._patron.checkouts()[ record_id ], treeitem );
		}
	);
	p.patron_items.register_context_builder(
		function (ev) {
			sdump('D_PATRON_DISPLAY','Firing context_builder\n');
			empty_widget(p.patron_items.paged_tree.popup);
			var patron_items = get_list_from_tree_selection( p.patron_items.paged_tree.tree );
			var menuitem;

			/*** CHECKIN ***/
			menuitem = p.patron_items.paged_tree.w.document.createElement('menuitem');
			p.patron_items.paged_tree.popup.appendChild( menuitem );
			menuitem.setAttribute('label',getString('circ.check_in'));
			menuitem.addEventListener(
				'command',
				function (ev) {
					sdump('D_PATRON_DISPLAY','Firing check-in context\n');
					for (var i = 0; i < patron_items.length; i++) {
						try {
							var idx = patron_items[i].getAttribute('record_id'); 
							var copy = p._patron.checkouts()[ idx ].copy;
							alert( checkin_by_copy_barcode( copy.barcode() ) );
						} catch(E) {
							alert(E);
						}
					}
				},
				false
			);

			/*** OPAC ***/
			menuitem = p.patron_items.paged_tree.w.document.createElement('menuitem');
			p.patron_items.paged_tree.popup.appendChild( menuitem );
			menuitem.setAttribute('label','Open in OPAC');
			menuitem.addEventListener(
				'command',
				function (ev) {
					for (var i = 0; i < patron_items.length; i++) {
						spawn_patron_items.display(
							p.w.app_shell,'new_tab','main_tabbox', 
							{ 
								'circ' : retrieve_circ_by_id( 
									patron_items[i].getAttribute('record_id') 
								)
							}
						);
					}
				},
				false
			);
			
		}
	);
}


