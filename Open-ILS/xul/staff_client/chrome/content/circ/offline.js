dump('entering circ.offline.js\n');

if (typeof circ == 'undefined') circ = {};
circ.offline = function (params) {
	try {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		JSAN.use('util.error'); this.error = new util.error();
	} catch(E) {
		dump('circ.offline: ' + E + '\n');
	}
}

circ.offline.prototype = {

	'init' : function( params ) {

		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");

			var obj = this;

			JSAN.use('util.deck'); obj.deck = new util.deck('main');

			JSAN.use('util.controller'); obj.controller = new util.controller();
			obj.controller.init(
				{
					control_map : {
						'cmd_broken' : [
							['command'],
							function() { alert('Not Yet Implemented'); }
						],
						'cmd_checkout' : [
							['command'],
							function() { obj.deck.set_iframe('offline_checkout.xul',{},{}); }
						],
						'cmd_renew' : [
							['command'],
							function() { obj.deck.set_iframe('offline_renew.xul',{},{}); }
						],
						'cmd_in_house_use' : [
							['command'],
							function() { obj.deck.set_iframe('offline_in_house_use.xul',{},{}); }
						],
						'cmd_checkin' : [
							['command'],
							function() { obj.deck.set_iframe('offline_checkin.xul',{},{}); }
						],
						'cmd_register_patron' : [
							['command'],
							function() { obj.deck.set_iframe('offline_register.xul',{},{}); }
						],
						'cmd_print_last_receipt' : [
							['command'],
							function() { 
								JSAN.use('util.print'); var print = new util.print();
								print.reprint_last();
							}
						],
						'cmd_exit' : [
							['command'],
							function() { window.close(); }
						],
					}
				}
			);

			obj.receipt_init();

			obj.patron_init();

		} catch(E) {
			this.error.sdump('D_ERROR','circ.offline.init: ' + E + '\n');
		}
	},

	'receipt_init' : function() {
		function backup_receipt_templates() {
			data.print_list_templates = {
				'offline_checkout' : {
					'type' : 'offline_checkout',
					'header' : 'Patron %patron_barcode%<br/>\r\nYou checked out the following items:<hr/><ol>',
					'line_item' : '<li>Barcode: %barcode%<br/>\r\nDue: %due_date%\r\n',
					'footer' : '</ol><hr />%TODAY_TRIM%<br/>\r\n<br/>\r\n',
				},
				'offline_checkin' : {
					'type' : 'offline_checkin',
					'header' : 'You checked in the following items:<hr/><ol>',
					'line_item' : '<li>Barcode: %barcode%\r\n',
					'footer' : '</ol><hr />%TODAY_TRIM%<br/>\r\n<br/>\r\n',
				},
				'offline_renew' : {
					'type' : 'offline_renew',
					'header' : 'You renewed the following items:<hr/><ol>',
					'line_item' : '<li>Barcode: %barcode%\r\n',
					'footer' : '</ol><hr />%TODAY_TRIM%<br/>\r\n<br/>\r\n',
				},
				'offline_inhouse_use' : {
					'type' : 'offline_inhouse_use',
					'header' : 'You marked the following in-house items used:<hr/><ol>',
					'line_item' : '<li>Barcode: %barcode%\r\nUses: %count%',
					'footer' : '</ol><hr />%TODAY_TRIM%<br/>\r\n<br/>\r\n',
				},
			};
			data.stash('print_list_templates');
		}

		JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
		JSAN.use('util.file'); var file = new util.file('print_list_templates');
		if (file._file.exists()) {
			try {
				var x = file.get_object();
				if (x) {
					data.print_list_templates = x;
					data.stash('print_list_templates');
				} else {
					backup_receipt_templates();
				}
			} catch(E) {
				alert(E);
				backup_receipt_templates();
			}
		} else {
			backup_receipt_templates();
		}
		file.close();
	},

	'patron_init' : function() {
		JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
		JSAN.use('util.file'); var file = new util.file('offline_patron_list');
		if (file._file.exists()) {
			var lines = file.get_content().split(/\n/);
			var hash = {};
			for (var i = 0; i < lines.length; i++) {
				hash[ lines[i].split(/\s+/)[0] ] = lines[i].split(/\s+/)[1];
			}
			delete(lines);
			data.bad_patrons = hash;
			data.stash('bad_patrons');
			var file2 = new util.file('offline_patron_list.date');
			if (file2._file.exists()) {
				data.bad_patrons_date = file2.get_content();
				data.stash('bad_patrons_date');
			}
			file2.close();
		} else {
			data.bad_patrons = {};
			data.stash('bad_patrons');
		}
		file.close();
	},

}

dump('exiting circ.offline.js\n');
