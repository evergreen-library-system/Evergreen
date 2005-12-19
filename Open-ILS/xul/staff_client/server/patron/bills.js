dump('entering patron.bills.js\n');

if (typeof patron == 'undefined') patron = {};
patron.bills = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	this.OpenILS = {}; JSAN.use('OpenILS.data'); this.OpenILS.data = new OpenILS.data(); this.OpenILS.data.init({'via':'stash'});
}

patron.bills.prototype = {

	'current_payments' : [],

	'init' : function( params ) {

		var obj = this;

		obj.session = params['session'];
		obj.patron_id = params['patron_id'];

		JSAN.use('util.list'); obj.list = new util.list('bill_list');

		function getString(s) { return obj.OpenILS.data.entities[s]; }
		obj.list.init(
			{
				'columns' : [
				/*
						{
							'id' : 'checkbox', 'label' : '', 'flex' : 1, 'primary' : false, 'hidden' : false,
							'render' : 'document.createElement("checkbox")'
						},
				*/
						{
							'id' : 'xact_dates', 'label' : getString('staff.bills_xact_dates_label'), 'flex' : 1,
							'primary' : false, 'hidden' : false, 'render' : 'xact_dates_box(my.mbts)'
						},
						{
							'id' : 'notes', 'label' : getString('staff.bills_information'), 'flex' : 1,
							'primary' : false, 'hidden' : false, 'render' : 'info_box(my.mbts)'
						},
						{
							'id' : 'money', 'label' : getString('staff.bills_money_label'), 'flex' : 1,
							'primary' : false, 'hidden' : false, 'render' : 'money_box(my.mbts)'
						},
						{
							'id' : 'current_pay', 'label' : getString('staff.bills_current_payment_label'), 'flex' : 1, 
							'render' : 'document.createElement("textbox")'
						}
				],
				'map_row_to_column' : function(row,col) {
					// row contains { 'my' : { 'mbts' : ... } }
					// col contains one of the objects listed above in columns

					var obj = {}; obj.OpenILS = {}; 
					JSAN.use('util.error'); obj.error = new util.error();
					//JSAN.use('OpenILS.data'); obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'});

					var my = row.my;
					var value;
					try {
						value = eval( col.render );
					} catch(E) {
						obj.error.sdump('D_ERROR','map_row_to_column: ' + E);
						value = '???';
					}
					dump('map_row_to_column: value = ' + value + '\n');
					return value;
				},
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
						function() { alert('Not Yet Implemented'); }
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
							obj.apply_payment();
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
							obj.controller.view.bill_credit_amount.value = util.money.cents_as_dollars( proposed_credit );
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

		//FIXME//.bills virtual field
		for (var i = 0; i < obj.bills.length; i++) {
			obj.list.append( { 'row' : { 'mobts' : obj.bills[i] } } );
		}
	},

	'apply_payment' : function() {
		var obj = this;
		var payment_blob = {};
		payment_blob.userid = obj.patron_id;
		payment_blob.note = '';
		payment_blob.cash_drawer = 1; // FIXME: get new Config() to work
		payment_blob.payment_type = obj.controller.view.payment_type.value;
		payment_blob.payments = [];
		payment_blob.patron_credit = obj.controller.view.bill_credit_amount.value;
		for (var i = 0; i < obj.current_payments.length; i++) {
			var tb = obj.current_payments[ i ].textbox;
			if ( !(tb.value == '0.00' || tb.value == '') ) {
				payment_blob.payments.push( 
					[
						obj.current_payments[ i ].mbts_id,
						tb.value
					]
				);
			}
		}
		try {
			if ( obj.pay( payment_blob ) ) {

				//FIXME//Refresh

			}

		} catch(E) {

			obj.error.sdump('D_ERROR',E);
		}
	},

	'pay' : function(payment_blob) {
		try {
			var robj = this.network.retrieve(
				api.bill_pay.app,	
				api.bill_pay.method,
				[ this.session, payment_blob ]
			);
			if (robj && robj.ilsevent && robj.ilsevent == 0) {
				return true;
			} else {
				throw robj;
			}
		} catch(E) {
			this.error.sdump('D_ERROR','patron.bills.pay: ' + E);
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
		obj.controller.view.bill_credit_amount.value = util.money.cents_as_dollars( proposed_credit );
	},

	'retrieve' : function() {
		var obj = this;
		obj.bills = obj.network.request(
			api.fm_mobts_having_balance.app,
			api.fm_mobts_having_balance.method,
			[ obj.session, obj.patron_id ]
		);
	}
}

dump('exiting patron.bills.js\n');
