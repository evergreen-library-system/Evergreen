sdump('D_TRACE','Loading hold_capture.js\n');

function hold_capture_init(p) {
	sdump('D_HOLD_CAPTURE',"TESTING: hold_capture.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));


	// gives: p.clamshell, p.right_panel, p.left_panel, p.inner_left_clamshell, p.inner_top_panel, p.inner_bottom_panel
	hold_capture_clamshell_init(p);

	// gives: p.hold_capture_items, p.redraw_hold_capture_items
	hold_capture_hold_capture_items_init(p);

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

function hold_capture_clamshell_init(p) {
	p.clamshell = clam_shell_init( { 'w' : p.w, 'node' : p.clamshell_node, 'debug' : p.app } );
	p.left_panel = p.clamshell.first_deck;
	p.right_panel = p.clamshell.second_deck;
}

function hold_capture_hold_capture_items_init(p) {
	p.hold_capture_items = hold_capture_items_init( { 'w' : p.w, 'node' : p.hold_capture_items_node, 'debug' : p.app } );

	var hold_captures = [];
	var tb = p.hold_capture_items_node.getElementsByAttribute('id','hold_capture_barcode_entry_textbox')[0];
	var submit_button = p.hold_capture_items_node.getElementsByAttribute('id','hold_capture_submit_barcode_button')[0];

	p.attempt_hold_capture = function(barcode) {
		try {
			//if (! is_barcode_valid(barcode) ) throw('Invalid Barcode');
			var check = hold_capture_by_copy_barcode( barcode );
			if (check) {
				sdump('D_HOLD_CAPTURE','check = ' + check + '\n' + pretty_print( js2JSON( check ) ) + '\n');

				check.status = 0;
				check.text = 'Captured for Hold Request';

				hold_captures.push( check );
				p.hold_capture_items.add_hold_capture_items( [ hold_captures.length - 1 ] );

				tb.value = ''; 
			}
		} catch(E) {
			handle_error(E);
		}
		tb.select(); tb.focus();
	}

	tb.addEventListener(
		'keypress',
		function(ev) {
			if (ev.keyCode == 13 || ev.keyCode == 77 ) { p.attempt_hold_capture( tb.value ); }
		},
		false
	);
	submit_button.addEventListener(
		'command',
		function(ev) {
			p.attempt_hold_capture( tb.value );
		},
		false
	);

	p.redraw_hold_capture_items = function() {
		p.hold_capture_items.clear_hold_capture_items();
		for (var i = 0; i < hold_captures.length; i++) {
			p.hold_capture_items.add_hold_capture_items( [ i ] );
		}
	}

	p.hold_capture_items.register_hold_capture_items_select_callback(
		function (ev) {
			sdump('D_HOLD_CAPTURE','Firing hold_capture_items_select_callback\n');
			var hold_capture_items = get_list_from_tree_selection( p.hold_capture_items.paged_tree.tree );
			/* grab cover art for selected item? */
		}
	);
	p.hold_capture_items.register_flesh_hold_capture_items_function(
		function (treeitem) {
			sdump('D_HOLD_CAPTURE','Firing flesh_hold_capture_items_function\n');
			var record_id = treeitem.getAttribute('record_id'); 
			p.hold_capture_items.map_hold_capture_items_to_cols( hold_captures[ record_id ], treeitem );
		}
	);
	p.hold_capture_items.register_context_builder(
		function (ev) {
			sdump('D_HOLD_CAPTURE','Firing context_builder\n');
			empty_widget(p.hold_capture_items.paged_tree.popup);
			var hold_capture_items = get_list_from_tree_selection( p.hold_capture_items.paged_tree.tree );
			var menuitem;

			/*** COPY EDITOR ***/
			menuitem = p.hold_capture_items.paged_tree.w.document.createElement('menuitem');
			p.hold_capture_items.paged_tree.popup.appendChild( menuitem );
			menuitem.setAttribute('label',getString('circ.context_edit'));
			menuitem.addEventListener(
				'command',
				function (ev) {
					for (var i = 0; i < hold_capture_items.length; i++) {
						var idx = hold_capture_items[i].getAttribute('record_id');
						sdump('D_HOLD_CAPTURE','Firing copy edit context\n');
					}
				},
				false
			);

			/*** OPAC ***/
			menuitem = p.hold_capture_items.paged_tree.w.document.createElement('menuitem');
			p.hold_capture_items.paged_tree.popup.appendChild( menuitem );
			menuitem.setAttribute('label',getString('circ.context_opac'));
			menuitem.addEventListener(
				'command',
				function (ev) {
					for (var i = 0; i < hold_capture_items.length; i++) {
						var idx = hold_capture_items[i].getAttribute('record_id');
						sdump('D_HOLD_CAPTURE','Firing opac context\n');
					}
				},
				false
			);
			
		}
	);
}


