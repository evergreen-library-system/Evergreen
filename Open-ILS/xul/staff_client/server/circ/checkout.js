dump('entering circ.checkout.js\n');

if (typeof patron == 'undefined') patron = {};
circ.checkout = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('main.network'); this.network = new main.network();

	JSAN.use('OpenILS.data'); this.OpenILS = {};
	this.OpenILS.data = new OpenILS.data(); this.OpenILS.data.init({'via':'stash'});
}

circ.checkout.prototype = {

	'init' : function( params ) {

		var obj = this;

		obj.session = params['session'];
		obj.patron_id = params['patron_id'];

		JSAN.use('main.list'); obj.list = new main.list('checkout_list');
		//FIXME//getString used to wrap StringBundles, but we need to do the entity/div thing
		function getString(s) { return obj.OpenILS.data.entities[s]; }
		obj.list.init(
			{
				'columns' : [
					{
						'id' : 'acp_id', 'label' : getString('staff.acp_label_id'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.acp.id()'
					},
					{
						'id' : 'circ_id', 'label' : getString('staff.circ_label_id'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.circ.id()'
					},
					{
						'id' : 'mvr_doc_id', 'label' : getString('staff.mvr_label_doc_id'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.mvr.doc_id()'
					},
					{
						'id' : 'barcode', 'label' : getString('staff.acp_label_barcode'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.acp.barcode()'
					},
					{
						'id' : 'call_number', 'label' : getString('staff.acp_label_call_number'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.acp.call_number()'
					},
					{
						'id' : 'copy_number', 'label' : getString('staff.acp_label_copy_number'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.acp.copy_number()'
					},
					{
						'id' : 'location', 'label' : getString('staff.acp_label_location'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.acp.location()'
					},
					{
						'id' : 'loan_duration', 'label' : getString('staff.acp_label_loan_duration'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.acp.loan_duration()'
					},
					{
						'id' : 'circ_lib', 'label' : getString('staff.acp_label_circ_lib'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.acp.circ_lib()'
					},
					{
						'id' : 'fine_level', 'label' : getString('staff.acp_label_fine_level'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.acp.fine_level()'
					},
					{
						'id' : 'deposit', 'label' : getString('staff.acp_label_deposit'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.acp.deposit()'
					},
					{
						'id' : 'deposit_amount', 'label' : getString('staff.acp_label_deposit_amount'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.acp.deposit_amount()'
					},
					{
						'id' : 'price', 'label' : getString('staff.acp_label_price'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.acp.price()'
					},
					{
						'id' : 'circ_as_type', 'label' : getString('staff.acp_label_circ_as_type'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.acp.circ_as_type()'
					},
					{
						'id' : 'circ_modifier', 'label' : getString('staff.acp_label_circ_modifier'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.acp.circ_modifier()'
					},
					{
						'id' : 'xact_start', 'label' : getString('staff.circ_label_xact_start'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.circ.xact_start()'
					},
					{
						'id' : 'xact_finish', 'label' : getString('staff.circ_label_xact_finish'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'my.circ.xact_finish()'
					},
					{
						'id' : 'due_date', 'label' : getString('staff.circ_label_due_date'), 'flex' : 1,
						'primary' : false, 'hidden' : false, 'render' : 'my.circ.due_date().substr(0,10)'
					},
					{
						'id' : 'title', 'label' : getString('staff.mvr_label_title'), 'flex' : 2,
						'primary' : false, 'hidden' : false, 'render' : 'my.mvr.title()'
					},
					{
						'id' : 'author', 'label' : getString('staff.mvr_label_author'), 'flex' : 1,
						'primary' : false, 'hidden' : false, 'render' : 'my.mvr.author()'
					},
					{
						'id' : 'renewal_remaining', 'label' : getString('staff.circ_label_renewal_remaining'), 'flex' : 0,
						'primary' : false, 'hidden' : true, 'render' : 'my.circ.renewal_remaining()'
					},
					{
						'id' : 'status', 'label' : getString('staff.acp_label_status'), 'flex' : 1,
						'primary' : false, 'hidden' : true, 'render' : 'obj.OpenILS.data.hash.ccs[ my.acp.status() ].name()'
					}
				],
				'map_row_to_column' : function(row,col) {
					// row contains { 'my' : { 'acp' : {}, 'circ' : {}, 'mvr' : {} } }
					// col contains one of the objects listed above in columns
					var my = row.my;
					return eval( col.render );
				},
			}
		);
		
		JSAN.use('main.controller'); obj.controller = new main.controller();
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
