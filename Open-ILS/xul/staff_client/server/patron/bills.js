dump('entering patron.bills.js\n');

if (typeof patron == 'undefined') patron = {};
patron.bills = function (params) {

	var obj = this;
	try { JSAN.use('util.error'); obj.error = new util.error(); } catch(E) { alert(E); }
	try { JSAN.use('util.network'); obj.network = new util.network(); } catch(E) { alert(E); }
	try { 
		obj.OpenILS = {}; JSAN.use('OpenILS.data'); obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'}); 
	} catch(E) { 
		alert(E); 
	}
}

patron.bills.prototype = {

	'version' : 'test123',

	'current_payments' : [],

	'refresh' : function() {
		location.href = location.href;
	},

	'init' : function( params ) {

		var obj = this;

		obj.session = obj.session || params['session'];
		obj.patron_id = obj.patron_id || params['patron_id'];

		JSAN.use('util.list'); obj.list = new util.list('bill_list');

		function getString(s) { return obj.OpenILS.data.entities[s]; }
		obj.list.init(
			{
				'columns' : [
						{
							'id' : 'xact_dates', 'label' : getString('staff.bills_xact_dates_label'), 'flex' : 1,
							'primary' : false, 'hidden' : false, 'render' : 'obj.xact_dates_box(my.mobts)'
						},
						{
							'id' : 'notes', 'label' : getString('staff.bills_information'), 'flex' : 2,
							'primary' : false, 'hidden' : false, 'render' : 'obj.info_box(my.mobts)'
						},
						{
							'id' : 'money', 'label' : getString('staff.bills_money_label'), 'flex' : 1,
							'primary' : false, 'hidden' : false, 'render' : 'obj.money_box(my.mobts)'
						},
						{
							'id' : 'current_pay', 'label' : getString('staff.bills_current_payment_label'), 'flex' : 0, 
							'render' : 'obj.payment_box()'
						}
				],
				'map_row_to_column' : obj.gen_map_row_to_column(),
			}
		);

		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				'control_map' : {
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_bill_wizard' : [
						['command'],
						function() { 
							try {
								JSAN.use('util.window');
								var win = new util.window();
								var w = win.open(
									urls.remote_patron_bill_wizard
										+ '?session=' + window.escape(obj.session)
										+ '&patron_id=' + window.escape(obj.patron_id),
									'billwizard',
									'chrome,resizable,modal'
								);
								if (typeof window.display_refresh == 'function') {
									try { window.display_refresh(); } catch(E) { obj.error.sdump('D_ERROR',E); }
								}
								obj.refresh();
							} catch(E) {
								obj.error.sdump('D_ERROR',E);
								alert(E);
							}
						}
					],
					'cmd_change_to_credit' : [
						['command'],
						function() {
							obj.change_to_credit();
						}
					],
					'cmd_bill_apply_payment' : [
						['command'],
						function() {
							try { obj.apply_payment(); } catch(E) { alert(E); }
						}
					],
					'bill_total_owed' : [
						['render'],
						function(e) { return function() {}; }
					],
					'payment_type' : [
						['render'],
						function(e) { return function() {}; }
					],
					'bill_payment_amount' : [
						['change'],
						function(ev) {
							JSAN.use('util.money');
							var tb = ev.target;
							tb.value = util.money.cents_as_dollars( util.money.dollars_float_to_cents_integer( tb.value ) );
							tb.setAttribute('value', tb.value );
							var total = util.money.dollars_float_to_cents_integer( tb.value );
							for (var i = 0; i < obj.current_payments.length; i++) {
								var bill = obj.current_payments[i];
								if (bill.checkbox.checked) {
									var bo = util.money.dollars_float_to_cents_integer( bill.balance_owed );
									if ( bo > total ) {
										bill.textbox.value = util.money.cents_as_dollars( total );
										total = 0;
									} else {
										bill.textbox.value = util.money.cents_as_dollars( bo );
										total = total - bo;
									}
								} else {
									bill.textbox.value = '0.00';
								}
								bill.textbox.setAttribute('value',bill.textbox.value);
							}
							obj.update_payment_applied();
						} 
					],
					'bill_payment_applied' : [
						['render'],
						function(e) { return function() {}; }
					],
					'bill_change_amount' : [
						['change'],
						function(ev) {
							JSAN.use('util.money');
							var tb = ev.target;
							var proposed_change = util.money.dollars_float_to_cents_integer( tb.value );
							var proposed_credit = 0;
							obj.update_payment_applied();
							var real_change = util.money.dollars_float_to_cents_integer( tb.value );
							if ( proposed_change > real_change ) {
								obj.error.sdump('D_ERROR','Someone wanted more money than they deserved\n');
								proposed_change = real_change;
							} else if ( real_change > proposed_change ) {
								proposed_credit = real_change - proposed_change;
							}
							tb.value = util.money.cents_as_dollars( proposed_change );
							tb.setAttribute('value',tb.value);
							obj.controller.view.bill_credit_amount.value = util.money.cents_as_dollars( proposed_credit );
							obj.controller.view.bill_credit_amount.setAttribute(
								'value',
								obj.controller.view.bill_credit_amount.value
							);
						}
					],
					'bill_credit_amount' : [
						['render'],
						function(e) { return function() {}; }
					],
					'bill_new_balance' : [
						['render'],
						function(e) { return function() {}; }
					],
				}
			}
		);

		obj.retrieve();

		var total_owed = 0;

		JSAN.use('util.money');

		obj.current_payments = [];
		//FIXME//.bills virtual field
		for (var i = 0; i < obj.bills.length; i++) {
			var rnode = obj.list.append( { 'row' : { 'my' : { 'mobts' : obj.bills[i] } }, 'attributes' : { 'allowevents' : true } } );
			var cb = rnode.getElementsByTagName('checkbox')[0];
			var tb = rnode.getElementsByTagName('textbox')[0];
			var bo = obj.bills[i].balance_owed();
			total_owed += util.money.dollars_float_to_cents_integer( bo );
			var id = obj.bills[i].id();
			obj.current_payments.push( { 'mobts_id' : id, 'balance_owed' : bo, 'checkbox' : cb, 'textbox' : tb, } );
		}
		obj.controller.view.bill_total_owed.value = util.money.cents_as_dollars( total_owed );
		obj.controller.view.bill_total_owed.setAttribute('value',obj.controller.view.bill_total_owed.value);
	},

	/*****************************************************************************************************************************/

	'apply_payment' : function() {
		var obj = this;
		var payment_blob = {};
		JSAN.use('util.window');
		var win = new util.window();
		switch(obj.controller.view.payment_type.value) {
			case 'credit_card_payment' :
				var w = win.open(
					urls.remote_patron_bill_cc_info,
					'billccinfo',
					'chrome,resizable,modal'
				);
				obj.OpenILS.data.stash_retrieve();
				payment_blob = JSON2js( obj.OpenILS.data.temp );
			break;
			case 'check_payment' :
				var w = win.open(
					urls.remote_patron_bill_check_info,
					'billccinfo',
					'chrome,resizable,modal'
				);
				obj.OpenILS.data.stash_retrieve();
				payment_blob = JSON2js( obj.OpenILS.data.temp );
			break;
		}
		if (payment_blob.cancelled == 'true') { alert('cancelled'); return; }
		payment_blob.userid = obj.patron_id;
		payment_blob.note = payment_blob.note || '';
		payment_blob.cash_drawer = 1; // FIXME: get new Config() to work
		payment_blob.payment_type = obj.controller.view.payment_type.value;
		payment_blob.payments = [];
		payment_blob.patron_credit = obj.controller.view.bill_credit_amount.value;
		for (var i = 0; i < obj.current_payments.length; i++) {
			var tb = obj.current_payments[ i ].textbox;
			if ( !(tb.value == '0.00' || tb.value == '') ) {
				payment_blob.payments.push( 
					[
						obj.current_payments[ i ].mobts_id,
						tb.value
					]
				);
			}
		}
		try {
			if ( obj.pay( payment_blob ) ) {

				obj.refresh();

			} else {

				alert('oops');
			}

		} catch(E) {

			obj.error.sdump('D_ERROR',E);
		}
	},

	'pay' : function(payment_blob) {
		var obj = this;
		try {
			var robj = obj.network.request(
				api.bill_pay.app,	
				api.bill_pay.method,
				[ obj.session, payment_blob ]
			);
			if (robj && robj.ilsevent && robj.ilsevent == 0) {
				return true;
			} else if (robj == 1) {
				return true;
			} else {
				throw robj;
			}
		} catch(E) {
			var error = 'patron.bills.pay: ' + js2JSON(E);
			obj.error.sdump('D_ERROR',error);
			alert(error);
			return false;
		}
	},

	'update_payment_applied' : function() {
		JSAN.use('util.money');
		var obj = this;
		var total_applied = 0;
		for (var i = 0; i < obj.current_payments.length; i++) {
			total_applied += util.money.dollars_float_to_cents_integer( obj.current_payments[ i ].textbox.value );
		}
		var total_payment = 0;
		if (obj.controller.view.bill_payment_amount.value) {
			try {
				total_payment = util.money.dollars_float_to_cents_integer( obj.controller.view.bill_payment_amount.value );
			} catch(E) {
				obj.error.sdump('D_ERROR',E + '\n');
			}
		}
		if ( total_applied > total_payment ) {
			total_payment = total_applied;
			obj.controller.view.bill_payment_amount.value = util.money.cents_as_dollars( total_applied );
		}
		obj.controller.view.bill_payment_applied.value = util.money.cents_as_dollars( total_applied );
		obj.controller.view.bill_payment_applied.setAttribute('value', obj.controller.view.bill_payment_applied.value )
		obj.controller.view.bill_credit_amount.value = '';
		if (total_payment > total_applied ) {
			obj.controller.view.bill_change_amount.value = util.money.cents_as_dollars( total_payment - total_applied);
			obj.controller.view.bill_credit_amount.value = '0.00';
		} else {
			obj.controller.view.bill_change_amount.value = '0.00';
			obj.controller.view.bill_credit_amount.value = '0.00';
		}
		var total_owed = util.money.dollars_float_to_cents_integer( obj.controller.view.bill_total_owed.value );
		obj.controller.view.bill_new_balance.value = util.money.cents_as_dollars( total_owed - total_applied );
	},

	'change_to_credit' : function() {
		JSAN.use('util.money');
		var obj = this;
		var tb = obj.controller.view.bill_change_amount;
		var proposed_change = 0;
		var proposed_credit = util.money.dollars_float_to_cents_integer( tb.value );
		obj.update_payment_applied();
		var real_change = util.money.dollars_float_to_cents_integer( tb.value );
		if ( proposed_change > real_change ) {
			obj.error.sdump('D_ERROR','Someone wanted more money than they deserved\n');
			proposed_change = real_change;
		} else if ( real_change > proposed_change ) {
			proposed_credit = real_change - proposed_change;
		}
		tb.value = util.money.cents_as_dollars( proposed_change );
		tb.setAttribute('value',tb.value);
		obj.controller.view.bill_credit_amount.value = util.money.cents_as_dollars( proposed_credit );
		obj.controller.view.bill_credit_amount.setAttribute('value',obj.controller.view.bill_credit_amount.value);
	},

	'retrieve' : function() {
		var obj = this;
		if (typeof window.bills != 'undefined') {
			obj.bills = window.bills;
		} else {
			obj.bills = obj.network.request(
				api.fm_mobts_having_balance.app,
				api.fm_mobts_having_balance.method,
				[ obj.session, obj.patron_id ]
			);
		}
	},

	'xact_dates_box' : function ( mobts ) {
		var obj = this;
		function getString(s) { return obj.OpenILS.data.entities[s]; }
		var grid = document.createElement('grid');
			var cols = document.createElement('columns');
			grid.appendChild( cols );
				cols.appendChild( document.createElement('column') );
				cols.appendChild( document.createElement('column') );
			var rows = document.createElement('rows');
			grid.appendChild( rows );
				var row0 = document.createElement('row');
				rows.appendChild( row0 );
					var cb_r0_0 = document.createElement('checkbox');
					row0.appendChild( cb_r0_0 );
					cb_r0_0.setAttribute('checked','true');
					var hb_r0_1 = document.createElement('hbox');
					row0.appendChild( hb_r0_1 );
						var label_r0_1 = document.createElement('label');
						hb_r0_1.appendChild( label_r0_1 );
						label_r0_1.setAttribute('value',getString('staff.mbts_id_label'));
						var label_r0_2 = document.createElement('label');
						hb_r0_1.appendChild( label_r0_2 );
						label_r0_2.setAttribute('value',mobts.id());
				var row1 = document.createElement('row');
				rows.appendChild( row1 );
					var label_r1_1 = document.createElement('label');
					row1.appendChild( label_r1_1 );
					label_r1_1.setAttribute('value',getString('staff.mbts_xact_start_label'));
					var label_r1_2 = document.createElement('label');
					row1.appendChild( label_r1_2 );
					label_r1_2.setAttribute('value',mobts.xact_start().toString().substr(0,10));
				var row2 = document.createElement('row');
				rows.appendChild( row2 );
					var label_r2_1 = document.createElement('label');
					row2.appendChild( label_r2_1 );
					label_r2_1.setAttribute('value',getString('staff.mbts_xact_finish_label'));
					var label_r2_2 = document.createElement('label');
					row2.appendChild( label_r2_2 );
					try { label_r2_2.setAttribute('value',mobts.xact_finish().toString().substr(0,10));
					} catch(E) {}

		return grid;
	},

	'money_box' : function ( mobts ) {
		var obj = this;
		function getString(s) { return obj.OpenILS.data.entities[s]; }
		var grid = document.createElement('grid');
			var cols = document.createElement('columns');
			grid.appendChild( cols );
				cols.appendChild( document.createElement('column') );
				cols.appendChild( document.createElement('column') );
			var rows = document.createElement('rows');
			grid.appendChild( rows );
				var row1 = document.createElement('row');
				rows.appendChild( row1 );
					var label_r1_1 = document.createElement('label');
					row1.appendChild( label_r1_1 );
					label_r1_1.setAttribute('value',getString('staff.mbts_total_owed_label'));
					var label_r1_2 = document.createElement('label');
					row1.appendChild( label_r1_2 );
					label_r1_2.setAttribute('value',mobts.total_owed());
				var row2 = document.createElement('row');
				rows.appendChild( row2 );
					var label_r2_1 = document.createElement('label');
					row2.appendChild( label_r2_1 );
					label_r2_1.setAttribute('value',getString('staff.mbts_total_paid_label'));
					var label_r2_2 = document.createElement('label');
					row2.appendChild( label_r2_2 );
					label_r2_2.setAttribute('value',mobts.total_paid());
				var row3 = document.createElement('row');
				rows.appendChild( row3 );
					var label_r3_1 = document.createElement('label');
					row3.appendChild( label_r3_1 );
					label_r3_1.setAttribute('value',getString('staff.mbts_balance_owed_label'));
					label_r3_1.setAttribute('style','font-weight: bold');
					var label_r3_2 = document.createElement('label');
					row3.appendChild( label_r3_2 );
					label_r3_2.setAttribute('value',mobts.balance_owed());
					label_r3_2.setAttribute('style','font-weight: bold');

		return grid;
	},

	'info_box' : function ( mobts ) {
		var obj = this;
		function getString(s) { return obj.OpenILS.data.entities[s]; }
		var vbox = document.createElement('vbox');
			var grid = document.createElement('grid');
				vbox.appendChild( grid );

				var cols = document.createElement('columns');
					grid.appendChild( cols );
					cols.appendChild( document.createElement('column') );
					cols.appendChild( document.createElement('column') );
				var rows = document.createElement('rows');
					grid.appendChild( rows );

			var xact_type = document.createElement('row');
			rows.appendChild( xact_type );

				var xt_label = document.createElement('label');
					xact_type.appendChild( xt_label );
					xt_label.setAttribute( 'value', 'Type' );
				var xt_value = document.createElement('label');
					xact_type.appendChild( xt_value );
					xt_value.setAttribute( 'value', mobts.xact_type() );

			var last_billing = document.createElement('row');
			rows.appendChild( last_billing );

				var lb_label = document.createElement('label');
					last_billing.appendChild( lb_label );
					lb_label.setAttribute( 'value', 'Last Billing:' );

				var lb_value = document.createElement('label');
					last_billing.appendChild( lb_value );
					if (mobts.last_billing_type()) 
						lb_value.setAttribute( 'value', mobts.last_billing_type() );

			var last_payment = document.createElement('row');
			rows.appendChild( last_payment );

				var lp_label = document.createElement('label');
					last_payment.appendChild( lp_label );
					lp_label.setAttribute( 'value', 'Last Payment:' );

				var lp_value = document.createElement('label');
					last_payment.appendChild( lp_value );
					if (mobts.last_payment_type()) 
						lp_value.setAttribute( 'value', mobts.last_payment_type() );

			var btn = document.createElement('button');
				vbox.appendChild( btn );
				btn.setAttribute( 'label', 'Full Details' );
				btn.setAttribute( 'name', 'full_details' );
				btn.setAttribute( 'mobts_id', mobts.id() );	
				btn.addEventListener(
					'command',
					function(ev) {
						JSAN.use('util.window'); var w = new util.window();
						w.open(
							urls.remote_patron_bill_details 
							+ '?session=' + window.escape(obj.session) 
							+ '&mbts_id=' + window.escape(mobts.id()),
							'test' + mobts.id(),
							'modal,chrome,resizable'
						);
					},
					false
				);

		return vbox;
	},

	'payment_box' : function() {
		var vb = document.createElement('vbox');
		var tb = document.createElement('textbox');
		tb.setAttribute('readonly','true');
		vb.appendChild(tb);
		return vb;
	},
	
	'gen_map_row_to_column' : function() {
		var obj = this;

		return function(row,col) {
			// row contains { 'my' : { 'mobts' : ... } }
			// col contains one of the objects listed above in columns

			var my = row.my;
			var value;
			try {
				value = eval( col.render );
			} catch(E) {
				try{obj.error.sdump('D_ERROR','map_row_to_column: ' + E);}
				catch(P){dump('?map_row_to_column: ' + E + '\n');}
				value = '???';
			}
			dump('map_row_to_column: value = ' + value + '\n');
			return value;
		};
	},

}

dump('exiting patron.bills.js\n');
