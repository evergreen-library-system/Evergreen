dump('entering circ.checkout.js\n');

if (typeof patron == 'undefined') patron = {};
circ.checkout = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	this.OpenILS = {}; JSAN.use('OpenILS.data'); this.OpenILS.data = new OpenILS.data(); this.OpenILS.data.init({'via':'stash'});
}

circ.checkout.prototype = {

	'init' : function( params ) {

		var obj = this;

		obj.session = params['session'];
		obj.patron_id = params['patron_id'];

		JSAN.use('circ.util');
		var columns = circ.util.columns( 
			{ 
				'barcode' : { 'hidden' : false },
				'title' : { 'hidden' : false },
				'due_date' : { 'hidden' : false },
			} 
		);

		JSAN.use('util.list'); obj.list = new util.list('checkout_list');
		obj.list.init(
			{
				'columns' : columns,
				'map_row_to_column' : circ.util.std_map_row_to_column(),
			}
		);
		
		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				'control_map' : {
					'checkout_barcode_entry_textbox' : [
						['keypress'],
						function(ev) {
							if (ev.keyCode && ev.keyCode == 13) {
								obj.checkout();
							}
						}
					],
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_checkout_submit_barcode' : [
						['command'],
						function() {
							obj.checkout();
						}
					],
					'cmd_checkout_print' : [
						['command'],
						function() {
						}
					],
					'cmd_checkout_reprint' : [
						['command'],
						function() {
						}
					],
					'cmd_checkout_done' : [
						['command'],
						function() {
						}
					],
				}
			}
		);
		this.controller.view.checkout_barcode_entry_textbox.focus();

	},

	'checkout' : function() {
		var obj = this;
		try {
			var barcode = obj.controller.view.checkout_barcode_entry_textbox.value;
			var permit = obj.network.request(
				api.checkout_permit_via_barcode.app,
				api.checkout_permit_via_barcode.method,
				[ obj.session, barcode, obj.patron_id, 0 ]
			);

			if (permit.status == 0) {
				var checkout = obj.network.request(
					api.checkout_via_barcode.app,
					api.checkout_via_barcode.method,
					[ obj.session, barcode, obj.patron_id ]
				);
				obj.list.append(
					{
						'row' : {
							'my' : {
							'circ' : checkout.circ,
							'mvr' : checkout.record,
							'acp' : checkout.copy
							}
						}
					//I could override map_row_to_column here
					}
				);
				if (typeof obj.on_checkout == 'function') {
					obj.on_checkout(checkout);
				}
				if (typeof window.xulG == 'object' && typeof window.xulG.on_checkout == 'function') {
					obj.error.sdump('D_CIRC','circ.checkout: Calling external .on_checkout()\n');
					window.xulG.on_checkout(checkout);
				} else {
					obj.error.sdump('D_CIRC','circ.checkout: No external .on_checkout()\n');
				}

			} else {
				throw(permit.text);
			}
		} catch(E) {
			alert('FIXME: need special alert and error handling\n'
				+ js2JSON(E));
			if (typeof obj.on_failure == 'function') {
				obj.on_failure(E);
			}
			if (typeof window.xulG == 'object' && typeof window.xulG.on_failure == 'function') {
				obj.error.sdump('D_CIRC','circ.checkout: Calling external .on_failure()\n');
				window.xulG.on_failure(E);
			} else {
				obj.error.sdump('D_CIRC','circ.checkout: No external .on_failure()\n');
			}
		}

	},

	'on_checkout' : function() {
		this.controller.view.checkout_barcode_entry_textbox.value = '';
		this.controller.view.checkout_barcode_entry_textbox.focus();
	},

	'on_failure' : function() {
		this.controller.view.checkout_barcode_entry_textbox.select();
		this.controller.view.checkout_barcode_entry_textbox.focus();
	}
}

dump('exiting circ.checkout.js\n');
