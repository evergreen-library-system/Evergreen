sdump('D_TRACE','Loading patron_search.js\n');

var test_variable = false;

function patron_search_init(p) {
	dump("TESTING: patron_search.js: " + mw.G['main_test_variable'] + '\n');

	var clamshell = spawn_clamshell( 
		p.w.document, 'new_iframe', p.clamshell, {

			'onload' : function (w) {
				var form = spawn_patron_search_form(
					w.document, 
					'new_iframe', 
					w.first_deck, {
						'onload' : function(w2) {
							w2.register_search_callback(
								function (ev) {
									alert('Submitted: ' + 
										js2JSON(form.crazy_search_hash) + '\n');
									test_variable = true; });

							w.new_card_in_second_deck(
								'chrome://evergreen/content/main/about.xul', {}); 
						}
					}
				);
	
			}
		}
	);
}
