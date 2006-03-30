var myPackageDir = 'open_ils_staff_client'; var IAMXUL = true; var g = {};

function $(id) {
	return document.getElementById(id);
}

function my_init() {
	try {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect UniversalFileRead");
		if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
		JSAN.errorLevel = "die"; // none, warn, or die
		JSAN.addRepository('..');
		JSAN.use('util.error'); g.error = new util.error();
		g.error.sdump('D_TRACE','my_init() for offline_checkout.html');

		if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
			try { window.xulG.set_tab_name('Upload Offline Transactions'); } catch(E) { alert(E); }
		}

		JSAN.use('util.file'); g.file = new util.file('pending_xacts');

		if (g.file._file.exists()) {
			$('submit').disabled = false;
			$('file').value = g.file._file.path;
		}

		g.cgi = new CGI();

		g.session = g.cgi.param('session');
		$( 'ws' ).setAttribute('value', g.cgi.param('ws_name'));
		$( 'ses' ).setAttribute('value', g.session);
		$( 'delta' ).setAttribute('value', 0 );

		JSAN.use('util.widgets');
		util.widgets.click('submit');

	} catch(E) {
		var err_msg = "!! This software has encountered an error.  Please tell your friendly " +
			"system administrator or software developer the following:\nmain/test_checkout.html\n" + E + '\n';
		try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); }
		alert(err_msg);
	}
}


