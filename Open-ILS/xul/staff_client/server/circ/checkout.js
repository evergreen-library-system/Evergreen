dump('entering circ.checkout.js\n');

if (typeof circ == 'undefined') circ = {};
circ.checkout = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
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
					'checkout_menu_placeholder' : [
						['render'],
						function(e) {
							return function() {
								JSAN.use('util.widgets'); JSAN.use('util.functional');
								var items = [ [ 'Barcode:' , 'barcode' ] ].concat(
									util.functional.map_list(
										obj.data.list.cnct,
										function(o) {
											return [ o.name(), o.id() ];
										}
									)
								);
								g.error.sdump('D_TRACE','items = ' + js2JSON(items));
								util.widgets.remove_children( e );
								var ml = util.widgets.make_menulist(
									items
								);
								e.appendChild( ml );
								ml.setAttribute('id','checkout_menulist');
								ml.addEventListener(
									'command',
									function(ev) {
										var tb = obj.controller.view.checkout_barcode_entry_textbox;
										if (ev.target.value == 'barcode') {
											tb.disabled = false;
											tb.value = '';
											tb.focus();
										} else {
											tb.disabled = true;
											tb.value = 'Non-Cataloged';
										}
									}, false
								);
								obj.controller.view.checkout_menu = ml;
							};
						},
					],
					'checkout_barcode_entry_textbox' : [
						['keypress'],
						function(ev) {
							if (ev.keyCode && ev.keyCode == 13) {
								obj.checkout( { barcode: ev.target.value } );
							}
						}
					],
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_checkout_submit' : [
						['command'],
						function() {
							var params = {};
							if (obj.controller.view.checkout_menu.value == 'barcode' ||
								obj.controller.view.checkout_menu.value == '') {
								params.barcode = obj.controller.view.checkout_barcode_entry_textbox.value;
							} else {
								params.noncat = 1;
								params.noncat_type = obj.controller.view.checkout_menu.value;
							}
							obj.checkout( params );
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
		this.controller.render();
		this.controller.view.checkout_barcode_entry_textbox.focus();

	},

	'checkout' : function(params) {
		if (!params) params = {};
		var obj = this;
		try {

			params.patron = obj.patron_id;

			var permit = obj.network.request(
				api.CHECKOUT_PERMIT.app,
				api.CHECKOUT_PERMIT.method,
				[ obj.session, params ]
			);

			if (permit.ilsevent == 0) {

				params.permit_key = permit.payload;

				var checkout = obj.network.request(
					api.CHECKOUT.app,
					api.CHECKOUT.method,
					[ obj.session, params ]
				);
				if (checkout.ilsevent == 0) {
					if (!checkout.payload) checkout.payload = {};
					if (!checkout.payload.circ) {
						checkout.payload.circ = new aoc();
						if (checkout.payload.noncat_circ) {
							checkout.payload.circ.circ_lib( checkout.payload.noncat_circ.circ_lib() );
							checkout.payload.circ.circ_staff( checkout.payload.noncat_circ.staff() );
							checkout.payload.circ.usr( checkout.payload.noncat_circ.patron() );
							
							JSAN.use('util.date');
							var c = checkout.payload.noncat_circ.circ_time();
							var d = c == "now" ? new Date() : util.date.db_date2Date( c );
							var t =obj.data.hash.cnct[ checkout.payload.noncat_circ.item_type() ];
							var cd = t.circ_duration() || "14 days";
							var i = util.date.interval_to_seconds( cd ) * 1000;
							d.setTime( Date.parse(d) + i );
							checkout.payload.circ.due_date( util.date.formatted_date(d,'%F') );

						}
					}
					if (!checkout.payload.record) {
						checkout.payload.record = new mvr();
						if (checkout.payload.noncat_circ) {
							checkout.payload.record.title(
								obj.data.hash.cnct[ checkout.payload.noncat_circ.item_type() ].name()
							);
						}
					}
					if (!checkout.payload.copy) {
						checkout.payload.copy = new acp();
						checkout.payload.copy.barcode( 'special' );
					}
					obj.list.append(
						{
							'row' : {
								'my' : {
								'circ' : checkout.payload.circ,
								'mvr' : checkout.payload.record,
								'acp' : checkout.payload.copy
								}
							}
						//I could override map_row_to_column here
						}
					);
					if (typeof obj.on_checkout == 'function') {
						obj.on_checkout(checkout.payload);
					}
					if (typeof window.xulG == 'object' && typeof window.xulG.on_checkout == 'function') {
						obj.error.sdump('D_CIRC','circ.checkout: Calling external .on_checkout()\n');
						window.xulG.on_checkout(checkout.payload);
					} else {
						obj.error.sdump('D_CIRC','circ.checkout: No external .on_checkout()\n');
					}
				} else {
					throw(checkout);
				}

			} else {
				throw(permit);
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
