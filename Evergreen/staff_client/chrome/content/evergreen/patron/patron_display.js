sdump('D_TRACE','Loading patron_display.js\n');

function patron_display_init(p) {
	sdump('D_PATRON_DISPLAY',"TESTING: patron_display.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	// gives: p.clamshell, p.right_panel, p.left_panel
	patron_display_clamshell_init(p);

	// gives: p.patron_items, p.redraw_patron_items
	patron_display_patron_items_init(p);

	// gives: p.patron_checkout_items, p.redraw_patron_checkout_items
	patron_display_patron_checkout_items_init(p);

	// gives: p.patron_holds, p.redraw_patron_holds
	patron_display_patron_holds_init(p);

	// gives: p.patron_bills, p.redraw_patron_bills
	patron_display_patron_bills_init(p);

	// gives: p.patron_edit, p.redraw_patron_edit
	patron_display_patron_edit_init(p);

	p.set_patron = function (au) {
		p.patron_edit._patron = au;
		return p._patron = au;
	}

	p.display_patron = function (exceptions) {
		if (!exceptions) exceptions = {};
		if (!exceptions.all) {
			if (!exceptions.patron_checkout_items) p.redraw_patron_checkout_items();
			if (!exceptions.patron_items) p.redraw_patron_items();
			if (!exceptions.patron_holds) p.redraw_patron_holds();
			if (!exceptions.patron_bills) p.redraw_patron_bills();
			//if (!exceptions.patron_edit) p.redraw_patron_edit();
		}
		return render_fm(p.w.document, { 'au' : p._patron });
	}
	p.redraw = p.display_patron;

	p.retrieve_patron_via_barcode = function (barcode) {
		if (!barcode) barcode = patron_get_barcode( p._patron );
		p.set_patron( retrieve_patron_by_barcode( barcode ) );
		return p.display_patron( {} );
	}

	p.retrieve_patron_via_id = function (id, exceptions) {
		p.set_patron( retrieve_patron_by_id( id ) );
		return p.display_patron(exceptions);
	}

	p.refresh = function(exceptions) {
		if (p._patron) p.retrieve_patron_via_id( p._patron.id(), exceptions );
	}

	set_patron_display_widgets(p);

	if (p.patron) {
		if (typeof(p.patron) == 'object') {
			//p._patron = p.patron;
			p.set_patron( p.patron );
			p.display_patron();
		} else
			p.retrieve_patron_via_barcode( p.patron );
	}

	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return p;
}

function set_patron_display_widgets(p) {
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
	p.commandset_node.getElementsByAttribute('id','cmd_patron_checkout')[0].addEventListener(
		'command',
		function () {
			focus_widget( p.w.document, 'patron_checkout_barcode_entry_textbox' );
		},
		false
	);
	p.commandset_node.getElementsByAttribute('id','cmd_patron_bills')[0].addEventListener(
		'command',
		function () {
			focus_widget( p.w.document, 'bill_payment_amount_textbox' );
		},
		false
	);
	p.commandset_node.getElementsByAttribute('id','cmd_patron_edit')[0].addEventListener(
		'command',
		function () {
			p.redraw_patron_edit();
		},
		false
	);




}


function patron_display_clamshell_init(p) {
	p.clamshell = clam_shell_init( { 'w' : p.w, 'node' : p.clamshell_node, 'debug' : p.app } );
	p.left_panel = p.clamshell.first_deck;
	p.right_panel = p.clamshell.second_deck;
}

function patron_display_patron_items_init(p) {
	p.patron_items = patron_items_init( { 'w' : p.w, 'node' : p.patron_items_node, 'debug' : p.app } );

	p.w.document.getElementById('item_print').addEventListener(
		'command',
		function(ev) {
			var params = { 
				'au' : p._patron, 
				'lib' : mw.G.user_ou,
				'staff' : mw.G.user,
				'header' : mw.G.itemsout_header,
				'line_item' : mw.G.itemsout_line_item,
				'footer' : mw.G.itemsout_footer
			};
			mw.print_itemsout_receipt( params );
		}, false
	);

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
			sdump('D_PATRON_DISPLAY','ev.target = ' + ev.target + '\n');
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
	p.patron_items.register_item_context_builder(
		function (ev) {
			sdump('D_PATRON_DISPLAY','Firing context_builder for patron_items\n');
			sdump('D_PATRON_DISPLAY','ev.target = ' + ev.target + '\np.patron_items.paged_tree.popup = ' + p.patron_items.paged_tree.popup + '\n');
			empty_widget(p.patron_items.paged_tree.popup);
			var patron_items = get_list_from_tree_selection( p.patron_items.paged_tree.tree );
			sdump('D_PATRON_DISPLAY','patron_items.length = ' + patron_items.length + '\n');

			/*** RENEW ***/
			var menuitem_pi_r = p.patron_items.paged_tree.w.document.createElement('menuitem');
			p.patron_items.paged_tree.popup.appendChild( menuitem_pi_r );
			menuitem_pi_r.setAttribute('label',getString('circ.context_renew'));
			menuitem_pi_r.addEventListener(
				'command',
				function (ev) {
					sdump('D_PATRON_DISPLAY','Firing renew context for patron_items\n');
					for (var i = 0; i < patron_items.length; i++) {
						try {
							var idx = patron_items[i].getAttribute('record_id'); 
							var circ = p._patron.checkouts()[ idx ].circ;
							alert( js2JSON(renew_by_circ_id( circ.id() )) );
							p.refresh();
						} catch(E) {
							alert(E);
						}
					}
				},
				false
			);

			/*** CHECKIN ***/
			var menuitem_pi_c = p.patron_items.paged_tree.w.document.createElement('menuitem');
			p.patron_items.paged_tree.popup.appendChild( menuitem_pi_c );
			menuitem_pi_c.setAttribute('label',getString('circ.context_checkin'));
			menuitem_pi_c.addEventListener(
				'command',
				function (ev) {
					sdump('D_PATRON_DISPLAY','Firing checkin context for patron_items\n');
					for (var i = 0; i < patron_items.length; i++) {
						try {
							var idx = patron_items[i].getAttribute('record_id'); 
							var copy = p._patron.checkouts()[ idx ].copy;
							var check = checkin_by_copy_barcode( copy.barcode(), null );
							if (check.status == 0) {
								alert('Check In: ' + check.text + '  Route To: ' + check.route_to);
							} else {
								alert('Check In: ' + check.text + '  Route To: ' + mw.G.org_tree_hash[check.route_to].shortname());
							}
							p.refresh();
						} catch(E) {
							alert(E);
						}
					}
				},
				false
			);

			/* separator */
			var menuitem_pi_s = p.patron_items.paged_tree.w.document.createElement('menuseparator');
			p.patron_items.paged_tree.popup.appendChild( menuitem_pi_s );
			

			/*** COPY EDITOR ***/
			var menuitem_pi_ce = p.patron_items.paged_tree.w.document.createElement('menuitem');
			p.patron_items.paged_tree.popup.appendChild( menuitem_pi_ce );
			menuitem_pi_ce.setAttribute('label',getString('circ.context_edit'));
			menuitem_pi_ce.addEventListener(
				'command',
				function (ev) {
					sdump('D_PATRON_DISPLAY','Firing copy editor context for patron_items\n');
					for (var i = 0; i < patron_items.length; i++) {
						sdump('D_PATRON_DISPLAY','Firing copy edit context\n');
					}
				},
				false
			);

			/*** OPAC ***/
			var menuitem_pi_o = p.patron_items.paged_tree.w.document.createElement('menuitem');
			p.patron_items.paged_tree.popup.appendChild( menuitem_pi_o );
			menuitem_pi_o.setAttribute('label',getString('circ.context_opac'));
			menuitem_pi_o.addEventListener(
				'command',
				function (ev) {
					sdump('D_PATRON_DISPLAY','Firing opac context for patron_items\n');
					for (var i = 0; i < patron_items.length; i++) {
						sdump('D_PATRON_DISPLAY','Firing opac context\n');
					}
				},
				false
			);
			
		}
	);
}

function patron_display_patron_checkout_items_init(p) {
	p.patron_checkout_items = patron_checkout_items_init( { 'w' : p.w, 'node' : p.patron_checkout_items_node, 'debug' : p.app } );
	var tb = p.patron_checkout_items_node.getElementsByAttribute('id','patron_checkout_barcode_entry_textbox')[0];
	var submit_button = p.patron_checkout_items_node.getElementsByAttribute('id','patron_checkout_submit_barcode_button')[0];

	var checkouts = [];

	function print_receipt() {
		p._patron._current_checkouts = checkouts;
		var params = { 
			'au' : p._patron, 
			'lib' : mw.G.user_ou,
			'staff' : mw.G.user,
			'header' : mw.G.checkout_header,
			'line_item' : mw.G.checkout_line_item,
			'footer' : mw.G.checkout_footer
		};
		mw.print_checkout_receipt( params );
	}

	p.w.document.getElementById('checkout_print').addEventListener( 'command',print_receipt, false);

	p.w.document.getElementById('checkout_done').addEventListener(
		'command',
		function () {
			if (p.w.document.getElementById('checkout_auto').checked) print_receipt(); 
			checkouts = []; p.display_patron(); tb.focus();
		},
		false
	);
	p.attempt_checkout = function(barcode) {
		try {
			//if (! is_barcode_valid(barcode) ) throw('Invalid Barcode');
			var permit_check = checkout_permit( barcode, p._patron.id(), 0 );
			if (permit_check.status == 0) {
				var check = checkout_by_copy_barcode( barcode, p._patron.id() );
				if (check) {
					checkouts.push( check );
					p.patron_checkout_items.add_checkout_items( [ checkouts.length - 1 ] );
					var temp = p._patron.checkouts();
					temp.push( check );
					p._patron.checkouts( temp );
					render_fm(p.w.document, { 'au' : p._patron }); // p.display_patron();
					p.redraw_patron_items();
					tb.value = '';
				}
			} else {
				throw(permit_check.text);
			}
		} catch(E) {
			tb.select();
			if (typeof(E) == 'object') {
				handle_error(E,true);
			} else {
				s_alert(E);
			}
		}
		tb.focus();
	}

	tb.addEventListener(
		'keypress',
		function(ev) {
			if (ev.keyCode == 13 || ev.keyCode == 77 ) { p.attempt_checkout( tb.value ); }
		},
		false
	);
	submit_button.addEventListener(
		'command',
		function(ev) {
			p.attempt_checkout( tb.value );
		},
		false
	);

	p.redraw_patron_checkout_items = function() {
		p.patron_checkout_items.clear_checkout_items();
		for (var i = 0; i < checkouts.length; i++) {
			p.patron_checkout_items.add_checkout_items( [ i ] );
		}
	}

	p.patron_checkout_items.register_patron_checkout_items_select_callback(
		function (ev) {
			sdump('D_PATRON_DISPLAY','Firing patron_checkout_items_select_callback\n');
			sdump('D_PATRON_DISPLAY','ev.target = ' + ev.target + '\n');
			var patron_checkout_items = get_list_from_tree_selection( p.patron_checkout_items.paged_tree.tree );
			/* grab cover art for selected item? */
		}
	);
	p.patron_checkout_items.register_flesh_patron_checkout_items_function(
		function (treeitem) {
			sdump('D_PATRON_DISPLAY','Firing flesh_patron_checkout_items_function\n');
			var record_id = treeitem.getAttribute('record_id'); 
			p.patron_checkout_items.map_patron_checkout_items_to_cols( checkouts[ record_id ], treeitem );
		}
	);
	p.patron_checkout_items.register_checkout_context_builder(
		function (ev) {
			sdump('D_PATRON_DISPLAY','Firing context_builder for patron_checkout_items\n');
			sdump('D_PATRON_DISPLAY','ev.target = ' + ev.target + '\np.patron_checkout_items.paged_tree.popup = ' + p.patron_checkout_items.paged_tree.popup + '\n');
			empty_widget(p.patron_checkout_items.paged_tree.popup);
			var patron_checkout_items = get_list_from_tree_selection( p.patron_checkout_items.paged_tree.tree );

			/*** CHECKIN ***/
			var menuitem_pci_c = p.patron_checkout_items.paged_tree.w.document.createElement('menuitem');
			p.patron_checkout_items.paged_tree.popup.appendChild( menuitem_pci_c );
			menuitem_pci_c.setAttribute('label',getString('circ.context_checkin'));
			menuitem_pci_c.addEventListener(
				'command',
				function (ev) {
					sdump('D_PATRON_DISPLAY','Firing checkin context for patron_checkout_items\n');
					var keep_these = [];
					for (var i = 0; i < patron_checkout_items.length; i++) {
						try {
							var idx = patron_checkout_items[i].getAttribute('record_id'); 
							var copy = checkouts[ idx ].copy;
							var check = checkin_by_copy_barcode( copy.barcode(), null );
							if (check == null) { // change this to whatever it takes
								keep_these.push( checkouts[ idx ] );	
							}
							checkouts = keep_these;
							if (check.status == 0) {
								alert('Check In: ' + check.text + '  Route To: ' + check.route_to);
							} else {
								alert('Check In: ' + check.text + '  Route To: ' + mw.G.org_tree_hash[check.route_to].shortname());
							}
							p.refresh();
						} catch(E) {
							alert(E);
						}
					}
				},
				false
			);

			/* separator */
			var menuitem_pci_s = p.patron_checkout_items.paged_tree.w.document.createElement('menuseparator');
			p.patron_checkout_items.paged_tree.popup.appendChild( menuitem_pci_s );
			

			/*** COPY EDITOR ***/
			var menuitem_pci_ce = p.patron_checkout_items.paged_tree.w.document.createElement('menuitem');
			p.patron_checkout_items.paged_tree.popup.appendChild( menuitem_pci_ce );
			menuitem_pci_ce.setAttribute('label',getString('circ.context_edit'));
			menuitem_pci_ce.addEventListener(
				'command',
				function (ev) {
					sdump('D_PATRON_DISPLAY','Firing copy editor context for patron_checkout_items\n');
					for (var i = 0; i < patron_checkout_items.length; i++) {
						var idx = patron_checkout_items[i].getAttribute('record_id');
						sdump('D_PATRON_DISPLAY','Firing copy edit context\n');
					}
				},
				false
			);

			/*** OPAC ***/
			var menuitem_pci_o = p.patron_checkout_items.paged_tree.w.document.createElement('menuitem');
			p.patron_checkout_items.paged_tree.popup.appendChild( menuitem_pci_o );
			menuitem_pci_o.setAttribute('label',getString('circ.context_opac'));
			menuitem_pci_o.addEventListener(
				'command',
				function (ev) {
					sdump('D_PATRON_DISPLAY','Firing opac context for patron_checkout_items\n');
					for (var i = 0; i < patron_checkout_items.length; i++) {
						var idx = patron_checkout_items[i].getAttribute('record_id');
						sdump('D_PATRON_DISPLAY','Firing opac context\n');
					}
				},
				false
			);
			
		}
	);
}

function patron_display_patron_holds_init(p) {
	p.patron_holds = patron_holds_init( { 'w' : p.w, 'node' : p.patron_holds_node, 'debug' : p.app } );

	p.redraw_patron_holds = function() {
		p.patron_holds.clear_patron_holds();
		if (!p._patron.hold_requests()) patron_get_holds( p._patron );
		for (var i = 0; i < p._patron.hold_requests().length; i++) {
			p.patron_holds.add_patron_holds( [ i ] );
		}
	}

	p.patron_holds.register_patron_holds_select_callback(
		function (ev) {
			sdump('D_PATRON_DISPLAY','Firing patron_holds_select_callback\n');
			sdump('D_PATRON_DISPLAY','ev.target = ' + ev.target + '\n');
			var patron_holds = get_list_from_tree_selection( p.patron_holds.paged_tree.tree );
			/* grab cover art for selected item? */
		}
	);
	p.patron_holds.register_flesh_patron_holds_function(
		function (treeitem) {
			sdump('D_PATRON_DISPLAY','Firing flesh_patron_holds_function\n');
			var record_id = treeitem.getAttribute('record_id'); 
			var hold = p._patron.hold_requests()[ record_id ];
			patron_get_hold_status(
				hold,
				function (request) {
					var result = request.getResultObject();
					hold.status( hold_status_as_text( result ) );
					p.patron_holds.map_patron_holds_to_cols( hold, treeitem );
				}
			);
		}
	);
	p.patron_holds.register_item_context_builder(
		function (ev) {
			sdump('D_PATRON_DISPLAY','Firing context_builder for patron_holds\n');
			sdump('D_PATRON_DISPLAY','ev.target = ' + ev.target + '\np.patron_holds.paged_tree.popup = ' + p.patron_holds.paged_tree.popup + '\n');
			empty_widget(p.patron_holds.paged_tree.popup);
			var patron_holds = get_list_from_tree_selection( p.patron_holds.paged_tree.tree );
			sdump('D_PATRON_DISPLAY','patron_holds.length = ' + patron_holds.length + '\n');

			/*** CANCEL HOLD ***/
			var menuitem_ph_ce = p.patron_holds.paged_tree.w.document.createElement('menuitem');
			p.patron_holds.paged_tree.popup.appendChild( menuitem_ph_ce );
			menuitem_ph_ce.setAttribute('label',getString('circ.context_cancel_hold'));
			menuitem_ph_ce.addEventListener(
				'command',
				function (ev) {
					sdump('D_PATRON_DISPLAY','Firing cancel hold context for patron_holds\n');
					for (var i = 0; i < patron_holds.length; i++) {
						sdump('D_PATRON_DISPLAY','Firing cancel edit context\n');
						var record_id = patron_holds[i].getAttribute('record_id');
						var hold = p._patron.hold_requests()[ record_id ];
						cancel_hold( hold );
					}
					p.refresh();
				},
				false
			);

			/* separator */
			var menuitem_ph_s = p.patron_holds.paged_tree.w.document.createElement('menuseparator');
			p.patron_holds.paged_tree.popup.appendChild( menuitem_ph_s );
			
			/*** COPY EDITOR ***/
			var menuitem_ph_ce = p.patron_holds.paged_tree.w.document.createElement('menuitem');
			p.patron_holds.paged_tree.popup.appendChild( menuitem_ph_ce );
			menuitem_ph_ce.setAttribute('label',getString('circ.context_edit'));
			menuitem_ph_ce.addEventListener(
				'command',
				function (ev) {
					sdump('D_PATRON_DISPLAY','Firing copy editor context for patron_holds\n');
					for (var i = 0; i < patron_holds.length; i++) {
						sdump('D_PATRON_DISPLAY','Firing copy edit context\n');
					}
				},
				false
			);

			/*** OPAC ***/
			var menuitem_ph_o = p.patron_holds.paged_tree.w.document.createElement('menuitem');
			p.patron_holds.paged_tree.popup.appendChild( menuitem_ph_o );
			menuitem_ph_o.setAttribute('label',getString('circ.context_opac'));
			menuitem_ph_o.addEventListener(
				'command',
				function (ev) {
					sdump('D_PATRON_DISPLAY','Firing opac context for patron_holds\n');
					for (var i = 0; i < patron_holds.length; i++) {
						sdump('D_PATRON_DISPLAY','Firing opac context\n');
					}
				},
				false
			);
			
		}
	);
}

function patron_display_patron_bills_init(p) {
	p.patron_bills = patron_bills_init( { 
		'w' : p.w, 
		'node' : p.patron_bills_node, 
		'debug' : p.app 
	} );

	p.patron_bills.refresh = function() { p.refresh(); }

	p.redraw_patron_bills = function() {
		try {
			p.patron_bills.clear_patron_bills();
			if (!p._patron.bills) patron_get_bills( p._patron );
			p.patron_bills.add_patron_bills( p._patron.bills );
		} catch(E) {
			sdump('D_ERROR',js2JSON(E) + '\n');
		}
	}
}

function patron_display_patron_edit_init(p) {
	/*
	p.patron_edit = patron_edit_init( { 
		'w' : p.w, 
		'node' : p.patron_edit_node, 
		'debug' : p.app
	} );

	p.patron_edit.redisplay = function() { p.display_patron( {'patron_edit':true} ); }
	p.patron_edit.refresh = function() { p.refresh( {'patron_edit':true} ); }

	p.redraw_patron_edit = function() {
		try {
			p.patron_edit.clear_patron_edit();
			p.patron_edit.add_rows( p._patron );
		} catch(E) {
			sdump('D_ERROR',js2JSON(E) + '\n');
		}
	}
	*/
	/* shoehorn in the old legacy stuff */
	p.patron_edit = {};
	p.redraw_patron_edit = function() { 
		empty_widget( p.patron_edit_node );
		setTimeout(
			function() {
				var frame = p.w.document.createElement('iframe');
				p.patron_edit_node.appendChild( frame );
				frame.setAttribute('flex','1');
				frame.setAttribute('src','chrome://evergreen/content/patron/patron_edit_legacy.xul');
				frame.contentWindow.mw = mw;
				frame.contentWindow.params = {};
				var barcode = patron_get_barcode( p._patron );
				frame.contentWindow.params.barcode = barcode;
				frame.contentWindow.params._patron = p._patron;
				frame.contentWindow.patron_save_callback = function ( params ) {
					p._patron = params.au;
					p.display_patron();
				}
				p.patron_edit.frame = frame;
			}, 0
		);
	}
}

