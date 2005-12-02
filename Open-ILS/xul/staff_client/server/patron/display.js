dump('entering patron/display.js\n');

if (typeof patron == 'undefined') patron = {};
patron.display = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('main.window'); this.window = new main.window();
	JSAN.use('main.network'); this.network = new main.network();
	this.w = window;
}

patron.display.prototype = {

	'init' : function( params ) {

		this.session = params['session'];
		this.barcode = params['barcode'];

		JSAN.use('OpenILS.data'); this.OpenILS = {}; 
		this.OpenILS.data = new OpenILS.data( { 'session' : params.session } ); this.OpenILS.data.init(true);

		var obj = this;
		obj.view = {}; obj.render_list = [];

		var control_map = {
			'cmd_broken' : [
				['command'],
				function() { alert('Not Yet Implemented'); }
			],
			'patron_caption' : [
				['render'],
				function(e) {
					return function() { 
						e.setAttribute('label',obj.patron.family_name() 
							+ obj.patron.first_given_name());
					};
				}
			],

			'patron_profile' : [
				['render'],
				function(e) {
					return function() { 
						e.setAttribute('value',
							obj.OpenILS.data.hash.pgt[
								obj.patron.profile()
							]
						);
					};
				}
			],
			'patron_credit' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_bill' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_checkouts' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_overdue' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_holds' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_holds_available' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_card' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_ident_type_1' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_ident_value_1' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_ident_type_2' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_date_of_birth' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_day_phone' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_evening_phone' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_other_phone' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_email' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_mailing_address_street1' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_mailing_address_street2' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_mailing_address_city' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_mailing_address_state' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_mailing_address_post_code' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_physical_address_street1' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_physical_address_street2' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_physical_address_city' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_physical_address_state' : [
				['render'],
				function(e) {
					return function() { };
				}
			],
			'patron_physical_address_post_code' : [
				['render'],
				function(e) {
					return function() { };
				}
			]
		};

		for (var i in control_map) {
			var cmd = this.w.document.getElementById(i);
			if (cmd) {
				for (var j in control_map[i][0]) {
					if (control_map[i][1]) {
						var ev_type = control_map[i][0][j];
						switch(ev_type) {
							case 'render':
								obj.render_list.push( control_map[i][1](cmd) ); 
							break;
							default: cmd.addEventListener(ev_type,control_map[i][1],false);
						}
					}
				}
			}
			obj.view[i] = cmd;
		}

		obj.retrieve();

	},

	'retrieve' : function() {

		var patron;
		try {
			patron = this.network.request(
				'open-ils.actor',
				'open-ils.actor.user.fleshed.retrieve_by_barcode',
				[ this.session, this.barcode ]
			);

			if (patron) {

				if (instanceOf(patron,au)) {

					this.patron = patron;
					this.render();

				} else {

					throw('patron is not an au fm object');
				}
			} else {

				throw('patron == false');
			}

		} catch(E) {
			var error = ('patron.display.retrieve : ' + js2JSON(E));
			this.error.sdump('D_ERROR',error);
			alert(error);
		}
	},

	'render' : function() {

		for (var i in this.render_list) {
			try {
				this.render_list[i]();
			} catch(E) {
				var error = 'Problem in patron.display.render with\n' + this.render_list[i] + '\n\n' + js2JSON(E);
				this.error.sdump('D_ERROR',error);
			}
		}
	}

}

dump('exiting patron/display.js\n');
