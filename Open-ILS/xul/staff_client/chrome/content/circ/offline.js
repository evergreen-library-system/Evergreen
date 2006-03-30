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
							function() { alert('Not Yet Implemented'); }
						],
						'cmd_exit' : [
							['command'],
							function() { window.close(); }
						],
					}
				}
			);


		} catch(E) {
			this.error.sdump('D_ERROR','circ.offline.init: ' + E + '\n');
		}
	},
}

dump('exiting circ.offline.js\n');
