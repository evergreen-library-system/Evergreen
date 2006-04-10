function my_init() {
	try {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
		JSAN.errorLevel = "die"; // none, warn, or die
		JSAN.addRepository('..');
		JSAN.use('util.error'); g.error = new util.error();
		g.error.sdump('D_TRACE','my_init() for offline_checkout.xul');

		if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
			try { window.xulG.set_tab_name('Standalone'); } catch(E) { alert(E); }
		}

		JSAN.use('util.list'); g.list = new util.list('checkout_list');
		JSAN.use('circ.util');
		g.list.init( {
			'columns' : circ.util.offline_inhouse_use_columns(),
			'map_row_to_column' : circ.util.std_map_row_to_column(),
		} );

		$('i_barcode').addEventListener('keypress',handle_keypress,false);
		$('enter').addEventListener('command',handle_enter,false);
		$('submit').addEventListener('command',next_patron,false);

		$('i_barcode').focus();

		JSAN.use('util.file');
		var file = new util.file('offline_delta'); 
		if (file._file.exists()) { g.delta = file.get_object(); file.close(); } else { g.delta = 0; }

	} catch(E) {
		var err_msg = "!! This software has encountered an error.  Please tell your friendly " +
			"system administrator or software developer the following:\ncirc/offline_in_house_use.xul\n" + E + '\n';
		try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); }
		alert(err_msg);
	}
}

function $(id) { return document.getElementById(id); }

function handle_keypress(ev) {
	if ( (! ev.keyCode) || (ev.keyCode != 13) ) return;
	switch(ev.target) {
		case $('i_barcode') : append_to_list(); break;
		default: break;
	}
}

function handle_enter(ev) {
	append_to_list();
}

function append_to_list() {

	try {

		JSAN.use('util.date');

		var my = {};

		my.type = 'in_house_use';
		my.timestamp = parseInt( new Date().getTime() / 1000) + g.delta;
		my.use_time = util.date.formatted_date(new Date(),"%F %H:%M:%s");

		var i_barcode = $('i_barcode').value;
		if (! i_barcode) return; 
		my.barcode = i_barcode; 

		var count = $('count').value;
		if (!Number(count) || count < 1) count = 1;
		my.count = count;

		g.list.append( { 'row' : { 'my' : my } } );

		var x = $('i_barcode'); x.value = ''; x.focus();

	} catch(E) {

		dump(E+'\n'); alert(E);

	}
}

function next_patron() {
	try {
		JSAN.use('util.file'); var file = new util.file('pending_xacts');
		var rows = g.list.dump_with_keys();
		for (var i = 0; i < rows.length; i++) {
			var row = rows[i]; row.delta = g.delta;
			file.append_object(row);
		}
		file.close();
		g.list.clear();
		
		var x;
		x = $('i_barcode'); x.value = ''; x.focus();

	} catch(E) {
		dump(E+'\n'); alert(E);
	}
}
