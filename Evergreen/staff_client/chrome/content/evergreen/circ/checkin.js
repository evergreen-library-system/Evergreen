sdump('D_TRACE','Loading checkin.js\n');

function checkin_init(p) {
	sdump('D_CHECKIN',"TESTING: checkin.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));


	// gives: p.clamshell, p.right_panel, p.left_panel, p.inner_left_clamshell, p.inner_top_panel, p.inner_bottom_panel
	checkin_clamshell_init(p);

	// gives: p.checkin_items, p.redraw_checkin_items
	checkin_checkin_items_init(p);

	p.refresh = function() {
	}

	p.retrieve_button = p.w.document.getElementById('PatronSearch_retrieve_button');
	p.retrieve_button.addEventListener(
		'command',
		function (ev) {
			spawn_patron_display(
				p.w.app_shell,'new_tab','main_tabbox',
				{
					'patron' : retrieve_patron_by_id(
						p._patron.id()
					)
				}
			);
		}
		,false
	);


	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return p;
}

function checkin_clamshell_init(p) {
	p.clamshell = clam_shell_init( { 'w' : p.w, 'node' : p.clamshell_node, 'debug' : p.app } );
	p.left_panel = p.clamshell.first_deck;
	p.right_panel = p.clamshell.second_deck;
}

function checkin_checkin_items_init(p) {
	p.checkin_items = checkin_items_init( { 'w' : p.w, 'node' : p.checkin_items_node, 'debug' : p.app } );

	var checkins = [];
	var tb = p.checkin_items_node.getElementsByAttribute('id','checkin_barcode_entry_textbox')[0];
	var submit_button = p.checkin_items_node.getElementsByAttribute('id','checkin_submit_barcode_button')[0];

	p.attempt_checkin = function(barcode) {
		try {
			//if (! is_barcode_valid(barcode) ) throw('Invalid Barcode');
			var check = checkin_by_copy_barcode( barcode );
			if (check) {
				sdump('D_CHECKIN','check = ' + check + '\n' + pretty_print( js2JSON( check ) ) + '\n');

				if (check.status == 0) {
					checkins.push( check );
					p.checkin_items.add_checkin_items( [ checkins.length - 1 ] );
				} else {
					// should be handled already
				}

				tb.value = ''; tb.focus();
			}
		} catch(E) {
			handle_error(E);
		}
	}

	tb.addEventListener(
		'keypress',
		function(ev) {
			if (ev.keyCode == 13 || ev.keyCode == 77 ) { p.attempt_checkin( tb.value ); }
		},
		false
	);
	submit_button.addEventListener(
		'command',
		function(ev) {
			p.attempt_checkin( tb.value );
		},
		false
	);

	p.redraw_checkin_items = function() {
		p.checkin_items.clear_checkin_items();
		for (var i = 0; i < checkins.length; i++) {
			p.checkin_items.add_checkin_items( [ i ] );
		}
	}

	p.checkin_items.register_checkin_items_select_callback(
		function (ev) {
			sdump('D_CHECKIN','Firing checkin_items_select_callback\n');
			var checkin_items = get_list_from_tree_selection( p.checkin_items.paged_tree.tree );
			/* grab cover art for selected item? */
		}
	);
	p.checkin_items.register_flesh_checkin_items_function(
		function (treeitem) {
			sdump('D_CHECKIN','Firing flesh_checkin_items_function\n');
			var record_id = treeitem.getAttribute('record_id'); 
			p.checkin_items.map_checkin_items_to_cols( checkins[ record_id ], treeitem );
		}
	);
	p.checkin_items.register_context_builder(
		function (ev) {
			sdump('D_CHECKIN','Firing context_builder\n');
			empty_widget(p.checkin_items.paged_tree.popup);
			var checkin_items = get_list_from_tree_selection( p.checkin_items.paged_tree.tree );
			var menuitem;

			/*** COPY EDITOR ***/
			menuitem = p.checkin_items.paged_tree.w.document.createElement('menuitem');
			p.checkin_items.paged_tree.popup.appendChild( menuitem );
			menuitem.setAttribute('label',getString('circ.context_edit'));
			menuitem.addEventListener(
				'command',
				function (ev) {
					for (var i = 0; i < checkin_items.length; i++) {
						var idx = checkin_items[i].getAttribute('record_id');
						sdump('D_CHECKIN','Firing copy edit context\n');
					}
				},
				false
			);

			/*** OPAC ***/
			menuitem = p.checkin_items.paged_tree.w.document.createElement('menuitem');
			p.checkin_items.paged_tree.popup.appendChild( menuitem );
			menuitem.setAttribute('label',getString('circ.context_opac'));
			menuitem.addEventListener(
				'command',
				function (ev) {
					for (var i = 0; i < checkin_items.length; i++) {
						var idx = checkin_items[i].getAttribute('record_id');
						sdump('D_CHECKIN','Firing opac context\n');
					}
				},
				false
			);
			
		}
	);
}


