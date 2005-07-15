sdump('D_TRACE','Loading patron_search_form.js\n');

function patron_search_form_init(p) {
	sdump('D_PATRON_SEARCH_FORM',"TESTING: patron_search_form.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	p.crazy_search_hash = {}; // hash[ field ] = { 'value' : ???, 'group' : ??? }

	var nl = p.node.getElementsByTagName('textbox');
	for (var i = 0; i < nl.length; i++) {
		nl[i].addEventListener(
			'change',
			function (ev) {
				return patron_search_form_textbox_handler(
					ev.target,
					p.crazy_search_hash
				); 
			},false
		);
	}

	var search_button = p.node.getElementsByAttribute('name','button_search')[0];
	var clear_button = p.node.getElementsByAttribute('name','button_clear')[0];

	p.register_search_callback = function (f) { search_button.addEventListener( 'command',f,false ); };

	if (clear_button) {
		clear_button.addEventListener(
			'command',
			function (ev) {
				var nl = p.node.getElementsByTagName('textbox');
				for (var i = 0; i < nl.length; i++) 
					nl[i].value = '';
				p.crazy_search_hash = {}; 
			},false
		);
	} else {
		sdump('D_PATRON_SEARCH_FORM',"No name=button_clear element.\n");
	}

	return p;
}

function patron_search_form_textbox_handler(textbox,search_hash) {
	sdump('D_PATRON_SEARCH_FORM',arg_dump(arguments));
	var field = textbox.getAttribute('field');
	var group = textbox.getAttribute('group');
	var value = textbox.value;
	search_hash[ field ] = { 'value' : value, 'group' : group };
	try {
		if (value==''||value==null||value==undefined) delete(search_hash[ field ]);
	} catch(E) {
		sdump('D_ERROR',E);
	}
}
