function my_init() {
	try {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
		JSAN.errorLevel = "die"; // none, warn, or die
		JSAN.addRepository('..');
		JSAN.use('util.error'); g.error = new util.error();
		g.error.sdump('D_TRACE','my_init() for offline_checkout.xul');

		JSAN.use('util.widgets'); JSAN.use('util.file');

		if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
			try { window.xulG.set_tab_name('Standalone'); } catch(E) { alert(E); }
		}

		JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});

		JSAN.use('util.list'); g.list = new util.list('checkout_list');
		JSAN.use('circ.util');
		g.list.init( {
			'columns' : circ.util.offline_checkout_columns(),
			'map_row_to_column' : circ.util.std_map_row_to_column(),
		} );

		JSAN.use('util.date');
		var today = new Date();
		var todayPlus = new Date(); todayPlus.setTime( today.getTime() + 24*60*60*1000*14 );
		todayPlus = util.date.formatted_date(todayPlus,"%F");

		$('duedate').setAttribute('value',todayPlus);
		$('duedate').addEventListener('change',check_date,false);

		$('p_barcode').addEventListener('keypress',handle_keypress,false);
		$('p_barcode').focus();	

		$('i_barcode').addEventListener('keypress',handle_keypress,false);
		$('enter').addEventListener('command',handle_enter,false);

		$('duedate_menu').addEventListener('command',handle_duedate_menu,false);

		$('submit').addEventListener('command',function(ev){
			save_xacts(); next_patron(); /* kludge */ ev.target.focus(); next_patron();
		},false);
		$('cancel').addEventListener('command',function(ev){
			next_patron(); /* kludge */ ev.target.focus(); next_patron();
		},false);

		var file; var list_data; var ml;

		file = new util.file('offline_cnct_list'); 
		if (file._file.exists()) {
			list_data = file.get_object(); file.close();
			ml = util.widgets.make_menulist( 
				[ ['or choose a non-barcoded option...', ''] ].concat(list_data[0]), 
				list_data[1] 
			);
			ml.setAttribute('id','noncat_type_menu'); $('x_noncat_type').appendChild(ml);
			ml.addEventListener(
				'command',
				function(ev) { 
					var count = window.prompt('Enter the number of items:',1,ml.getAttribute('label'));
					append_to_list('noncat',count);	
					ml.value = '';
				},
				false
			);
		} else {
			alert('WARNING: The non-barcode types have not been downloaded from the server.  You should log in to retrieve these.');
		}

		var file = new util.file('offline_delta'); 
		if (file._file.exists()) { g.delta = file.get_object(); file.close(); } else { g.delta = 0; }

	} catch(E) {
		var err_msg = "!! This software has encountered an error.  Please tell your friendly " +
			"system administrator or software developer the following:\ncirc/offline_checkout.xul\n" + E + '\n';
		try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); }
		alert(err_msg);
	}
}

function $(id) { return document.getElementById(id); }

function check_date(ev) {
	JSAN.use('util.date');
	try {
		if (! util.date.check('YYYY-MM-DD',ev.target.value) ) { throw('Invalid Date'); }
		if (util.date.check_past('YYYY-MM-DD',ev.target.value) ) { throw('Due date needs to be after today.'); }
		if ( util.date.formatted_date(new Date(),'%F') == ev.target.value) { throw('Due date needs to be after today.'); }
	} catch(E) {
		alert(E);
		var today = new Date();
		var todayPlus = new Date(); todayPlus.setTime( today.getTime() + 24*60*60*1000*14 );
		todayPlus = util.date.formatted_date(todayPlus,"%F");
		ev.target.value = todayPlus;
	}
}

function handle_keypress(ev) {
	if ( (! ev.keyCode) || (ev.keyCode != 13) ) return;
	switch(ev.target) {
		case $('p_barcode') : $('p_barcode').disabled = true; $('i_barcode').focus(); break;
		case $('i_barcode') : append_to_list('barcode'); break;
		default: break;
	}
}

function handle_enter(ev) {
	append_to_list('barcode');
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

function append_to_list(checkout_type,count) {

	try {

		var my = {};

		my.type = 'checkout';
		my.timestamp = parseInt( new Date().getTime() / 1000) + g.delta;
		my.checkout_time = util.date.formatted_date(new Date(),"%F %H:%M:%s");

		var p_barcode = $('p_barcode').value;
		if (! p_barcode) {
			g.error.yns_alert('Please enter a patron barcode first.','Required Field','Ok',null,null,'Check here to confirm this message');
			return;
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
						g.error.yns_alert('This barcode has already been scanned.','Duplicate Scan','Ok',null,null,'Check here to confirm this message');
						return;
					}
				}

				my.barcode = i_barcode; 
			break;
			case 'noncat' :
				count = parseInt(count); if (! (count>0) ) {
					g.error.yns_alert("Please try again and enter a valid count.",'Required Value','Ok',null,null,'Check here to confirm this message');
					return;
				}
				my.barcode = $('noncat_type_menu').getAttribute('label');
				my.noncat = 1;
				my.noncat_type = JSON2js($('noncat_type_menu').value)[0];
				my.noncat_count = count;
			break;
			default: alert("Please report that this happened."); break;
		}
	
		g.list.append( { 'row' : { 'my' : my } } );

		var x = $('i_barcode'); x.value = ''; x.focus();

	} catch(E) {

		dump(E+'\n'); alert(E);

	}
}


function save_xacts() {
	JSAN.use('util.file'); var file = new util.file('pending_xacts');
	var rows = g.list.dump_with_keys();
	for (var i = 0; i < rows.length; i++) {
		var row = rows[i]; row.delta = g.delta;
		if (row.noncat == 1) {
			delete(row.barcode);
		} else {
			delete(row.noncat);
			delete(row.noncat_type);
			delete(row.noncat_count);
		}
		file.append_object(row);
	}
	file.close();
}

function next_patron() {
	try {
	
		if ($('print_receipt').checked) {
			try {
				var params = {
					'patron_barcode' : $('p_barcode').value,
					'header' : g.data.print_list_templates.offline_checkout.header,
					'line_item' : g.data.print_list_templates.offline_checkout.line_item,
					'footer' : g.data.print_list_templates.offline_checkout.footer,
					'type' : g.data.print_list_templates.offline_checkout.type,
					'list' : g.list.dump(),
				};
				JSAN.use('util.print'); var print = new util.print();
				print.tree_list( params );
			} catch(E) {
				g.error.sdump('D_ERROR','print: ' + E);
				alert('print: ' + E);
			}
		}

		g.list.clear();
		
		var x;
		x = $('i_barcode'); x.value = '';
		x = $('p_barcode'); x.value = ''; 
		x.setAttribute('disabled','false'); x.disabled = false; 
		x.focus();

	} catch(E) {
		dump(E+'\n'); alert(E);
	}
}
