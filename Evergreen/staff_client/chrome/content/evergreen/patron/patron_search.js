sdump('D_TRACE','Loading patron_search.js\n');

var test_variable = false;

function patron_search_init(p) {
	sdump('D_PATRON_SEARCH',"TESTING: patron_search.js: " + mw.G['main_test_variable'] + '\n');

	var clamshell = spawn_clamshell( 
		p.w.document, 'new_iframe', p.clamshell, { 
			'onload' : patron_search_init_after_clamshell(p) 
		}
	);
}

function patron_search_init_after_clamshell(p) {
	sdump('D_PATRON_SEARCH',arg_dump(arguments));
	return function (clamshell_w) {
		var form = spawn_patron_search_form(
			clamshell_w.document, 
			'new_iframe', 
			clamshell_w.first_deck, {
				'onload' : patron_init_after_patron_search_form(p)
			}
		);

		clamshell_w.new_card_in_second_deck(
			'chrome://evergreen/content/main/about.xul', {}); 
	};
}

function patron_init_after_patron_search_form(p) {
	sdump('D_PATRON_SEARCH',arg_dump(arguments));
	return function(form_w) {
		form_w.register_search_callback(
			function (ev) {
				alert('Submitted: ' + 
					js2JSON(form_w.crazy_search_hash) + '\n');
			}
		);
	};
}
