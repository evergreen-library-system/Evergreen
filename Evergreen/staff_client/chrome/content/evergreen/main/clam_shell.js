sdump('D_TRACE','Loading clam_shell.js\n');

function clam_shell_init(p) {
	dump("TESTING: clam_shell.js: " + mw.G['main_test_variable'] + '\n');
	if (d.params && d.params.vertical) {
		p.d.setAttribute('orient','verticle');
	}
}

