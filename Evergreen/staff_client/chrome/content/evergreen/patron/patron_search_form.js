sdump('D_TRACE','Loading patron_search_form.js\n');

function patron_search_form_init(p) {
	sdump('D_PATRON_SEARCH_FORM',"TESTING: patron_search_form.js: " + mw.G['main_test_variable'] + '\n');
	p.w.crazy_search_hash = {}; // hash[ field ] = { 'value' : ???, 'group' : ??? }

	var nl = p.w.document.getElementsByTagName('textbox');
	for (var i = 0; i < nl.length; i++) 
		nl[i].addEventListener(
			'change',
			function (ev) {
				return patron_search_form_textbox_handler(
					p.w.document,
					ev.target,
					p.w.crazy_search_hash); },
			false);

	var search_command = p.w.document.getElementById('cmd_search');
	var clear_command = p.w.document.getElementById('cmd_clear');

	p.w.register_search_callback = function (f) { search_command.addEventListener( 'command',f,false ); };

	if (clear_command)
		clear_command.addEventListener(
			'command',
			function (ev) {
				var nl = p.w.document.getElementsByTagName('textbox');
				for (var i = 0; i < nl.length; i++) 
					nl[i].value = '';
				p.w.crazy_search_hash = {}; },
			false);
	else
		sdump('D_PATRON_SEARCH_FORM',"No cmd_clear element.\n");

	if (p.onload) {
		try {
			sdump('D_TRACE','trying psuedo-onload: ' + p.onload + '\n');
			p.onload(p.w);
		} catch(E) {
			sdump('D_ERROR', js2JSON(E) + '\n' );
		}
	}

}

function patron_search_form_textbox_handler(doc,textbox,search_hash) {
	sdump('D_PATRON_SEARCH_FORM',arg_dump(arguments));
	textbox = get_widget(doc,textbox);
	var field = textbox.getAttribute('field');
	var group = textbox.getAttribute('group');
	var value = textbox.value;
	search_hash[ field ] = { 'value' : value, 'group' : group };
}
