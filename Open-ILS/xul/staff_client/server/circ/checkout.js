dump('entering circ.checkout.js\n');

if (typeof patron == 'undefined') patron = {};
circ.checkout = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('main.network'); this.network = new main.network();

	JSAN.use('OpenILS.data'); this.OpenILS = {};
	this.OpenILS.data = new OpenILS.data(); this.OpenILS.data.init(true);
}

circ.checkout.prototype = {

	'init' : function( params ) {

		var obj = this;

		obj.session = params['session'];
		obj.patron_id = params['patron_id'];

		JSAN.use('OpenILS.data'); obj.OpenILS = {}; 
		obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init(true);


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
						'primary' : false, 'hidden' : false, 'render' : 'my.acp.barcode()'
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
						'primary' : false, 'hidden' : false, 'render' : 'my.circ.renewal_remaining()'
					},
					{
						'id' : 'status', 'label' : getString('staff.acp_label_status'), 'flex' : 1,
						'primary' : false, 'hidden' : false, 'render' : 'stash.data.hash.acp[ my.acp.status() ].name()'
					}
				],
				'map_row_to_column' : function(row,col) {
					// row contains { 'my' : { 'acp' : {}, 'circ' : {}, 'mvr' : {} } }
					// col contains one of the objects listed above in columns
					JSAN.use('OpenILS.data'); var stash = new OpenILS.data(); stash.init(true);
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
						}
					],
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_checkout_submit_barcode' : [
						['command'],
						function() {
							try {
								var barcode = obj.controller.view.checkout_barcode_entry_textbox.value;
								var permit = obj.network.request(
									'open-ils.circ',
									'open-ils.circ.permit_checkout',
									[ obj.session, barcode, obj.patron_id, 0 ]
								);

								if (permit.status == 0) {
									var checkout = obj.network.request(
										'open-ils.circ',
										'open-ils.circ.checkout.barcode',
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

								} else {
									throw(permit.text);
								}
							} catch(E) {
								alert('FIXME: need special alert and error handling\n'
									+ js2JSON(E));
							}
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

	}
}

dump('exiting circ.checkout.js\n');
