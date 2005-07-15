sdump('D_TRACE','Loading patron_search.js\n');

var test_variable = false;

function patron_search_init(p) {
	sdump('D_PATRON_SEARCH',"TESTING: patron_search.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	/* gives: p.clamshell, p.right_panel, p.left_panel */
	patron_search_clamshell_init(p);

	/* gives: p.search_form */
	patron_search_patron_search_form_init(p);

	/* gives: p.search_results */
	patron_search_patron_search_results_init(p);

	p.crazy_search = function (crazy_search_hash) {
		return patron_search( crazy_search_hash );
	};

	p.w.document.getElementById('PatronSearch_retrieve_button').addEventListener(
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
	return;
}

function patron_search_clamshell_init(p) {
	p.clamshell = clam_shell_init( { 'w' : p.w, 'node' : p.clamshell_node, 'debug' : p.app } );
	p.left_panel = p.clamshell.first_deck;
	p.right_panel = p.clamshell.second_deck;
}

function patron_search_patron_search_form_init(p) {
	p.search_form = patron_search_form_init( { 'w' : p.w, 'node' : p.patron_search_form_node, 'debug' : p.ap } );
	p.search_form.register_search_callback(
		function (ev) {
			sdump('D_PATRON_SEARCH','Submitted: ' + js2JSON(p.search_form.crazy_search_hash) + '\n');
			if (p.crazy_search) {
				p.search_results.clear_patrons();
				p.search_results.add_patrons(
					p.crazy_search( p.search_form.crazy_search_hash )
				);
			}
		}
	);
}

function patron_search_patron_search_results_init(p) {
	p.search_results = patron_search_results_init( { 'w' : p.w, 'node' : p.patron_search_results_node, 'popupset_node' : p.popupset_node, 'debug' : p.app } );

	p.redraw_search_results = function() {
		p.search_results.clear_search_results();
		if (!p._patron.checkouts()) patron_get_checkouts( p._patron );
		for (var i = 0; i < p._patron.checkouts().length; i++) {
			p.search_results.add_search_results( [ i ] );
		}
	}

	p.search_results.register_patron_select_callback(
		function (ev) {
			sdump('D_PATRON_SEARCH','Firing patron_select_callback\n');
			var patrons = get_list_from_tree_selection( p.search_results.paged_tree.tree );
			p._patron = retrieve_patron_by_id( patrons[ patrons.length - 1 ].getAttribute('record_id') )
			render_fm( p.w.document, { 'au' : p._patron } );
		}
	);
	p.search_results.register_flesh_patron_function(
		function (treeitem) {
			sdump('D_PATRON_SEARCH','Firing flesh_patron_function\n');
			var record_id = treeitem.getAttribute('record_id'); 
			retrieve_patron_by_id( 
				record_id, 
				function (request) {
					sdump('D_PATRON_SEARCH','flesh_patron callback\n');
					try {
						var patron = request.getResultObject();
						sdump('D_PATRON_SEARCH','patron = ' + js2JSON( patron ) + '\n');
						try {
							p.search_results.map_patron_to_cols( patron, treeitem );
						} catch(E) {
							sdump('D_ERROR','map in flesh_patron callback\n' + E+ '\n');
						}
					} catch(E) {
						sdump('D_ERROR','flesh_patron callback\n' + E+ '\n');
					}
					sdump('D_PATRON_SEARCH','leaving flesh_patron callback\n');
				}
			);
		}
	);
	p.search_results.register_context_builder(
		function (ev) {
			sdump('D_PATRON_DISPLAY','Firing context_builder\n');
			empty_widget(p.search_results.paged_tree.popup);
			var search_results = get_list_from_tree_selection( p.search_results.paged_tree.tree );
			var menuitem;

			/*** PATRON DISPLAY ***/
			menuitem = p.search_results.paged_tree.w.document.createElement('menuitem');
			p.search_results.paged_tree.popup.appendChild( menuitem );
			menuitem.setAttribute('label',getString('patron.context_display'));
			menuitem.addEventListener(
				'command',
				function (ev) {
					sdump('D_PATRON_DISPLAY','Firing renew context\n');
					for (var i = 0; i < search_results.length; i++) {
						spawn_patron_display(
							p.w.app_shell,'new_tab','main_tabbox',
							{
								'patron' : retrieve_patron_by_id(
									search_results[i].getAttribute('record_id')
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

function patron_search(crazy_search_hash) {
	sdump('D_PATRON_SEARCH',arg_dump(arguments));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var result = [];
	try {
		result = user_request(
			'open-ils.actor',
			'open-ils.actor.patron.search.advanced',
			[ G.auth_ses[0], crazy_search_hash ]
		)[0];
		sdump('D_PATRON_SEARCH','result.length = ' + result.length + '\n');
	} catch(E) {
		handle_error(E);
	}
	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return result;
}

