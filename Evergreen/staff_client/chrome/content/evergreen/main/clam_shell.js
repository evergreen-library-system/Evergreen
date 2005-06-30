sdump('D_TRACE','Loading clam_shell.js\n');

function clam_shell_init(p) {
	dump("TESTING: clam_shell.js: " + mw.G['main_test_variable'] + '\n');
	if (p) {
		if (p.horizontal) {
			get_widget(p.d,'ClamShell_main').orient = 'horizontal';
		} else if (p.vertical) {
			get_widget(p.d,'ClamShell_main').orient = 'vertical';
		}
	}
}

