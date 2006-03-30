function my_init() {
	try {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
		JSAN.errorLevel = "die"; // none, warn, or die
		JSAN.addRepository('..');
		JSAN.use('util.error'); g.error = new util.error();
		g.error.sdump('D_TRACE','my_init() for offline_register.xul');

		if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
			try { window.xulG.set_tab_name('Standalone'); } catch(E) { alert(E); }
		}

		$('barcode').addEventListener('keypress',handle_keypress,false);
		$('submit').addEventListener('command',next_patron,false);

		JSAN.use('util.file');

		var file; var xml; var parser; var doc; var node;

		file = new util.file('offline_ou_list'); xml = file.get_content(); file.close();
		parser = new DOMParser(); doc = parser.parseFromString(xml, "text/xml"); node = doc.documentElement;
		$('x_home_ou').appendChild(node);

		file = new util.file('offline_pgt_list'); xml = file.get_content(); file.close();
		parser = new DOMParser(); doc = parser.parseFromString(xml, "text/xml"); node = doc.documentElement;
		$('x_profile').appendChild(node);

		file = new util.file('offline_cit_list'); xml = file.get_content(); file.close();
		parser = new DOMParser(); doc = parser.parseFromString(xml, "text/xml"); node = doc.documentElement;
		$('x_ident_type').appendChild(node);

	} catch(E) {
		var err_msg = "!! This software has encountered an error.  Please tell your friendly " +
			"system administrator or software developer the following:\ncirc/offline_register.xul\n" + E + '\n';
		try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); }
		alert(err_msg);
	}
}

function $(id) { return document.getElementById(id); }

function handle_keypress(ev) {
	if ( (! ev.keyCode) || (ev.keyCode != 13) ) return;
	switch(ev.target) {
		case $('barcode') : $('family_name').focus(); break;
		default: break;
	}
}

function next_patron() {
	try {
		JSAN.use('util.file'); var file = new util.file('pending_xacts');
		file.append_object(row);
		file.close();

		alert(location.href);

	} catch(E) {
		dump(E+'\n'); alert(E);
	}
}
