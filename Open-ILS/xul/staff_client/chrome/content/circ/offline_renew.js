function my_init() {
	try {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
		JSAN.errorLevel = "die"; // none, warn, or die
		JSAN.addRepository('..');
		JSAN.use('util.error'); g.error = new util.error();
		g.error.sdump('D_TRACE','my_init() for offline_renew.xul');

		if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
			try { window.xulG.set_tab_name('Standalone'); } catch(E) { alert(E); }
		}

		JSAN.use('util.list'); g.list = new util.list('checkout_list');
		g.list.init( {
			'columns' : [
				{ 
					'id' : 'timestamp', 
					'label' : 'Timestamp', 
					'flex' : 1, 'primary' : false, 'hidden' : true, 
					'render' : 'my.timestamp' 
				},
				{ 
					'id' : 'checkout_time', 
					'label' : 'Check Out Time', 
					'flex' : 1, 'primary' : false, 'hidden' : true, 
					'render' : 'my.checkout_time' 
				},
				{ 
					'id' : 'type', 
					'label' : 'Transaction Type', 
					'flex' : 1, 'primary' : false, 'hidden' : true, 
					'render' : 'my.type' 
				},
				{ 
					'id' : 'patron_barcode', 
					'label' : 'Patron Barcode', 
					'flex' : 1, 'primary' : false, 'hidden' : true, 
					'render' : 'my.patron_barcode' 
				},
				{ 
					'id' : 'barcode', 
					'label' : 'Item Barcode', 
					'flex' : 2, 'primary' : true, 'hidden' : false, 
					'render' : 'my.barcode' 
				},
				{ 
					'id' : 'due_date', 
					'label' : 'Due Date', 
					'flex' : 1, 'primary' : false, 'hidden' : false, 
					'render' : 'my.due_date' 
				},
			],
			'map_row_to_column' : function(row,col) {
				// row contains { 'my' : { 'barcode' : xxx, 'duedate' : xxx } }
				// col contains one of the objects listed above in columns

				var my = row.my;
				var value;
				try {
					value = eval( col.render );
					if (typeof value == 'undefined') value = '';

				} catch(E) {
					JSAN.use('util.error'); var error = new util.error();
					error.sdump('D_WARN','map_row_to_column: ' + E);
					value = '???';
				}
				return value;
			}
		} );

		JSAN.use('util.date');
		var today = new Date();
		var todayPlus = new Date(); todayPlus.setTime( today.getTime() + 24*60*60*1000*14 );
		todayPlus = util.date.formatted_date(todayPlus,"%F");

		$('duedate').setAttribute('value',todayPlus);

		$('p_barcode').addEventListener('keypress',handle_keypress,false);
		$('p_barcode').focus();	

		$('i_barcode').addEventListener('keypress',handle_keypress,false);

		$('duedate_menu').addEventListener('command',handle_duedate_menu,false);

		$('submit').addEventListener('command',next_patron,false);

	} catch(E) {
		var err_msg = "!! This software has encountered an error.  Please tell your friendly " +
			"system administrator or software developer the following:\ncirc/offline_renew.xul\n" + E + '\n';
		try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); }
		alert(err_msg);
	}
}

function $(id) { return document.getElementById(id); }

function handle_keypress(ev) {
	if ( (! ev.keyCode) || (ev.keyCode != 13) ) return;
	switch(ev.target) {
		case $('p_barcode') : $('i_barcode').focus(); break;
		case $('i_barcode') : append_to_list('barcode'); break;
		default: break;
	}
}

function handle_duedate_menu(ev) {
	if (ev.target.value=='0') return; 
	JSAN.use('util.date'); 
	var today = new Date(); 
	var todayPlus = new Date(); 
	todayPlus.setTime( today.getTime() + 24*60*60*1000*ev.target.value ); 
	todayPlus = util.date.formatted_date(todayPlus,'%F'); 
	$('duedate').setAttribute('value',todayPlus); 
	$('duedate').value = todayPlus;
}

function handle_barcode_menu(ev) {
}

function append_to_list(checkout_type,count) {

	try {

		var my = {};

		my.type = 'renew';
		my.timestamp = new Date().getTime();
		my.checkout_time = util.date.formatted_date(new Date(),"%F %H:%M:%s");

		var p_barcode = $('p_barcode').value;
		if (! p_barcode) {
			/* Not strictly necessary for a renewal
			alert('Please enter a patron barcode first.');
			return;
			*/
		} else {

			// Need to validate patron barcode against bad patron list
			my.patron_barcode = p_barcode;
		}

		var due_date = $('duedate').value; // Need to validate this
		my.due_date = due_date;

		var i_barcode = $('i_barcode').value;
		switch(checkout_type) {
			case 'barcode' : 
				if (! i_barcode) return; 
				
				var rows = g.list.dump_with_keys();
				for (var i = 0; i < rows.length; i++) {
					if (rows[i].barcode == i_barcode) {
						alert('This barcode has already been scanned.');
						return;
					}
				}

				my.barcode = i_barcode; 
			break;
			default: alert("Please report that this happened."); break;
		}
	
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
			var row = rows[i];
			if (row.patron_barcode == '') {
				delete(row.patron_barcode);
			}
			file.append_object(row);
		}
		file.close();
		g.list.clear();
		
		var x;
		x = $('i_barcode'); x.value = '';
		x = $('p_barcode'); x.value = ''; x.focus();

	} catch(E) {
		dump(E+'\n'); alert(E);
	}
}
