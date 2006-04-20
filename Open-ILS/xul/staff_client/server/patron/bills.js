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

	'current_payments' : [],

	'SHOW_ME_THE_BILLS' : 'FM_MOBTS_HAVING_BALANCE',

	'refresh' : function(dont_show_me_the_money) {
		var obj = this;
		obj.bills = obj.network.simple_request(
			obj.SHOW_ME_THE_BILLS,
			[ obj.session, obj.patron_id ]
		);

		for (var i = 0; i < obj.bills.length; i++) {
			if (instanceOf(obj.bills[i],mobts)) {
				obj.bills[i] = { 'transaction' : obj.bills[i] }
			} else if (instanceOf(obj.bills[i],mbts)) {
				obj.bills[i] = { 'transaction' : obj.bills[i] }
			}
		}

		if (!dont_show_me_the_money) {
			//alert('dont_show_me_the_money = ' + dont_show_me_the_money);
			if (window.xulG && typeof window.xulG.on_money_change == 'function') {
				try { window.xulG.on_money_change(obj.bills); } catch(E) { this.error.sdump('D_ERROR',E); }
			}
		}

		var tbs = document.getElementsByTagName('textbox');
		for (var i = 0; i < tbs.length; i++) {
			tbs[i].value = ''; tbs[i].setAttribute('value','');
		}
		obj.init();
		obj.controller.view.bill_payment_amount.focus();
	},

	'init' : function( params ) {
	
		var obj = this;

		obj.init_controller( params );

		obj.retrieve();

		var total_owed = 0;

		JSAN.use('util.money');

		obj.current_payments = []; obj.list.clear();
		//FIXME//.bills virtual field
		for (var i = 0; i < obj.bills.length; i++) {
			var rnode = obj.list.append( 
				{ 'row' : 
					{ 'my' : 
						{ 'mobts' : obj.bills[i].transaction, 'circ' : obj.bills[i].circ, 'mvr' : obj.bills[i].record } 
					}, 
					'attributes' : { 'allowevents' : true } 
				} 
			);
			var cb = rnode.getElementsByTagName('checkbox')[0];
			var tb = rnode.getElementsByTagName('textbox')[0];
			var bo = obj.bills[i].transaction.balance_owed();
			total_owed += util.money.dollars_float_to_cents_integer( bo );
			var id = obj.bills[i].transaction.id();
			obj.current_payments.push( { 'mobts_id' : id, 'balance_owed' : bo, 'checkbox' : cb, 'textbox' : tb, } );
		}
		obj.controller.view.bill_total_owed.value = util.money.cents_as_dollars( total_owed );
		obj.controller.view.bill_total_owed.setAttribute('value',obj.controller.view.bill_total_owed.value);
	},

	'init_controller' : function( params ) {

		var obj = this;

		if (obj._controller_inited) return;

		obj.session = obj.session || params['session'];
		obj.patron_id = obj.patron_id || params['patron_id'];

		JSAN.use('util.list'); obj.list = new util.list('bill_list');

		function getString(s) { return obj.OpenILS.data.entities[s]; }
		obj.list.init(
			{
				'columns' : [
				/*
						{
							'id' : 'xact_dates', 'label' : getString('staff.bills_xact_dates_label'), 'flex' : 1,
							'primary' : false, 'hidden' : false, 'render' : 'obj.xact_dates_box(my.mobts)'
						},
				*/
						{
							'id' : 'notes', 'label' : getString('staff.bills_information'), 'flex' : 2,
							'primary' : false, 'hidden' : false, 'render' : 'obj.info_box(my)'
						},
						{
							'id' : 'money', 'label' : 'Money Summary', 'flex' : 1,
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
									urls.XUL_PATRON_BILL_WIZARD
										+ '?session=' + window.escape(obj.session)
										+ '&patron_id=' + window.escape(obj.patron_id),
									'billwizard',
									'chrome,resizable,modal'
								);
								obj.refresh();
							} catch(E) {
								obj.error.sdump('D_ERROR',E);
								alert(E);
							}
						}
					],
					'cmd_bill_history' : [
						['command'],
						function() { 
							try {
								JSAN.use('util.window');
								var win = new util.window();
								obj.OpenILS.data.init({'via':'stash'}); obj.OpenILS.data.temp = ''; obj.OpenILS.data.stash('temp');
								var w = win.open(
									urls.XUL_PATRON_BILL_HISTORY
										+ '?session=' + window.escape(obj.session)
										+ '&patron_id=' + window.escape(obj.patron_id),
									'billhistory',
									'chrome,resizable,modal'
								);
								obj.OpenILS.data.init({'via':'stash'}); if (obj.OpenILS.data.temp == 'refresh') { obj.refresh(); }
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

		obj._controller_inited = true;

	},


	/*****************************************************************************************************************************/

	'apply_payment' : function() {
		var obj = this;
		var payment_blob = {};
		JSAN.use('util.window');
		var win = new util.window();
		switch(obj.controller.view.payment_type.value) {
			case 'credit_card_payment' :
				obj.OpenILS.data.temp = '';
				obj.OpenILS.data.stash('temp');
				var w = win.open(
					urls.XUL_PATRON_BILL_CC_INFO,
					'billccinfo',
					'chrome,resizable,modal'
				);
				obj.OpenILS.data.stash_retrieve();
				/* FIXME -- need unique temp space name */
				payment_blob = JSON2js( obj.OpenILS.data.temp );
			break;
			case 'check_payment' :
				obj.OpenILS.data.temp = '';
				obj.OpenILS.data.stash('temp');
				var w = win.open(
					urls.XUL_PATRON_BILL_CHECK_INFO,
					'billcheckinfo',
					'chrome,resizable,modal'
				);
				obj.OpenILS.data.stash_retrieve();
				/* FIXME -- need unique temp space name */
				payment_blob = JSON2js( obj.OpenILS.data.temp );
			break;
		}
		if (payment_blob=='' || payment_blob.cancelled=='true') { alert('cancelled'); return; }
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
				alert('FIXME: Receipt goes here\n' + js2JSON(payment_blob));

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
				api.BILL_PAY.app,	
				api.BILL_PAY.method,
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
		if (window.xulG && window.xulG.bills) {
			obj.bills = window.xulG.bills;
		} else {
			obj.bills = obj.network.simple_request(
				obj.SHOW_ME_THE_BILLS,	
				[ obj.session, obj.patron_id ]
			);
			for (var i = 0; i < obj.bills.length; i++) {
				if (instanceOf(obj.bills[i],mobts)) {
					obj.bills[i] = { 'transaction' : obj.bills[i] }
				}
			}
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

	'info_box' : function ( my ) {
		var obj = this;
		function getString(s) { return obj.OpenILS.data.entities[s]; }
		var vbox = document.createElement('vbox');

			var hbox = document.createElement('hbox');
				vbox.appendChild( hbox ); hbox.flex = 1;

				var cb = document.createElement('checkbox');
				hbox.appendChild( cb ); 
				if ( my.mobts.balance_owed() == 0 ) { 
					cb.setAttribute('disabled', 'true'); 
				} else { 
					cb.setAttribute('checked', 'true'); 
				}

				try {
					var xt_id = document.createElement('label');
					hbox.appendChild(xt_id); xt_id.setAttribute('value','Bill #' + my.mobts.id());
				} catch(E) { alert(E); }

				try {
					var xt_start = document.createElement('label');
					hbox.appendChild(xt_start); xt_start.setAttribute('value', 'First Billing: ' + (my.mobts.xact_start() ? my.mobts.xact_start().toString().substr(0,10) : '') );
				} catch(E) { alert(E); }

				try {
					var xt_finish = document.createElement('label');
					hbox.appendChild(xt_finish); xt_finish.setAttribute('value', (my.mobts.xact_finish() ? 'Finish: ' + my.mobts.xact_finish().toString().substr(0,10) : '') );
				} catch(E) { alert(E); }

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
				var xt_value = document.createElement('description');
					xact_type.appendChild( xt_value );

			try {
			switch(my.mobts.xact_type()) {
				case 'circulation':
					xt_label.setAttribute( 'value', 'Title' );
					obj.network.simple_request(
						'FM_CIRC_RETRIEVE_VIA_ID',
						[ obj.session, my.mobts.id() ],
						function (req) {
							var r_circ = req.getResultObject();
							if (instanceOf(r_circ,circ)) {
								xt_start.setAttribute('value','Checked Out: ' + r_circ.xact_start().toString().substr(0,10) );
								if (r_circ.checkin_time()) {
									xt_finish.setAttribute('value','Returned: ' + r_circ.checkin_time().toString().substr(0,10) );
								} else {
									xt_finish.setAttribute('value','Due: ' + r_circ.due_date().toString().substr(0,10) );
								}
								obj.network.simple_request(
									'MODS_SLIM_RECORD_RETRIEVE_VIA_COPY',
									[ r_circ.target_copy() ],
									function (rreq) {
										var r_mvr = rreq.getResultObject();
										if (instanceOf(r_mvr,mvr)) {
											xt_value.appendChild( document.createTextNode( r_mvr.title() ) );
										} else {
											obj.network.simple_request(
												'FM_ACP_RETRIEVE',
												[ r_circ.target_copy() ],
												function (rrreq) {
													var r_acp = rrreq.getResultObject();
													if (instanceOf(r_acp,acp)) {
														xt_value.appendChild( document.createTextNode( r_acp.dummy_title() ) );
													}
												}
											);
										}
									}
								);
							}
						}
					);
				break;
				default:
						xt_label.setAttribute( 'value', my.mvr ? 'Title' : 'Type' );
						xt_value.appendChild( document.createTextNode( my.mvr ? my.mvr.title() : my.mobts.xact_type() ) );
				break;
			}
			} catch(E) { alert(E); }

			var last_billing = document.createElement('row');
			rows.appendChild( last_billing );

				var lb_label = document.createElement('label');
					last_billing.appendChild( lb_label );
					lb_label.setAttribute( 'value', 'Last Billing:' );

				var lb_value = document.createElement('label');
					last_billing.appendChild( lb_value );
					if (my.mobts.last_billing_type()) 
						lb_value.setAttribute( 'value', my.mobts.last_billing_type() );
/*
			var last_payment = document.createElement('row');
			rows.appendChild( last_payment );

				var lp_label = document.createElement('label');
					last_payment.appendChild( lp_label );
					lp_label.setAttribute( 'value', 'Last Payment:' );

				var lp_value = document.createElement('label');
					last_payment.appendChild( lp_value );
					if (my.mobts.last_payment_type()) 
						lp_value.setAttribute( 'value', my.mobts.last_payment_type() );
*/
			var btn_box = document.createElement('hbox');
			vbox.appendChild( btn_box ); btn_box.flex = 1;
					var btn = document.createElement('button');
						btn_box.appendChild( btn );
						btn.setAttribute( 'label', 'Full Details' );
						btn.setAttribute( 'name', 'full_details' );
						btn.setAttribute( 'mobts_id', my.mobts.id() );	
						btn.addEventListener(
							'command',
							function(ev) {
								JSAN.use('util.window'); var w = new util.window();
								w.open(
									urls.XUL_PATRON_BILL_DETAILS 
									+ '?session=' + window.escape(obj.session) 
									+ '&patron_id=' + window.escape(obj.patron_id)
									+ '&mbts_id=' + window.escape(my.mobts.id()),
									'test' + my.mobts.id(),
									'modal,chrome,resizable'
								);
								obj.OpenILS.data.init({'via':'stash'}); 
								if (obj.OpenILS.data.temp == 'refresh') {
									obj.refresh();
								}

							},
							false
						);
					var btn2 = document.createElement('button');
						btn_box.appendChild( btn2 );
						btn2.setAttribute( 'label', 'Add Billing' );
						btn2.setAttribute( 'mobts_id', my.mobts.id() );	
						btn2.addEventListener(
							'command',
							function(ev) {
								JSAN.use('util.window');
								var win = new util.window();
								var w = win.open(
									urls.XUL_PATRON_BILL_WIZARD
										+ '?session=' + window.escape(obj.session)
										+ '&patron_id=' + window.escape(obj.patron_id)
										+ '&xact_id=' + window.escape( my.mobts.id() ),
									'billwizard',
									'chrome,resizable,modal'
								);
								obj.refresh();
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
			//dump('map_row_to_column: value = ' + value + '\n');
			return value;
		};
	},

}

dump('exiting patron.bills.js\n');
