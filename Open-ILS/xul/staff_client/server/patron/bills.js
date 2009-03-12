dump('entering patron.bills.js\n');

function $(id) { return document.getElementById(id); }

if (typeof patron == 'undefined') patron = {};
patron.bills = function (params) {

	var obj = this;
	try { JSAN.use('util.error'); obj.error = new util.error(); } catch(E) { alert(E); }
	try { JSAN.use('util.network'); obj.network = new util.network(); } catch(E) { alert(E); }
	try { 
		obj.OpenILS = {}; JSAN.use('OpenILS.data'); obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'}); 
		obj.data = obj.OpenILS.data;
		obj.data.voided_billings = []; obj.data.stash('voided_billings');
	} catch(E) { 
		alert(E); 
	}
}

patron.bills.prototype = {

	'bill_map' : {},

	'current_payments' : [],

	'SHOW_ME_THE_BILLS' : 'FM_MBTS_IDS_RETRIEVE_ALL_HAVING_BALANCE.authoritative',
	//'SHOW_ME_THE_BILLS' : 'FM_MBTS_IDS_RETRIEVE_ALL_STILL_OPEN',
	//'SHOW_ME_THE_BILLS' : 'FM_MOBTS_HAVING_BALANCE',
	/*'SHOW_ME_THE_BILLS' : 'FM_MOBTS_OPEN',*/

	'refresh' : function(dont_show_me_the_money) {
		var obj = this;
		try {
                if (document.getElementById('circulating_hint')) {
                    document.getElementById('circulating_hint').hidden = true;
                }

				obj.bills = obj.network.simple_request(
					obj.SHOW_ME_THE_BILLS,
					[ ses(), obj.patron_id ]
				);
				//alert('obj.bills = ' + js2JSON(obj.bills));

				for (var i = 0; i < obj.bills.length; i++) {
					if (instanceOf(obj.bills[i],mobts)) {
						obj.bills[i] = { 'transaction' : obj.bills[i] }
					} else if (instanceOf(obj.bills[i],mbts)) {
						obj.bills[i] = { 'transaction' : obj.bills[i] }
					} else {
						var robj = obj.network.simple_request('FM_MBTS_RETRIEVE.authoritative',[ses(),obj.bills[i]]);
						//alert('refresh robj = ' + js2JSON(robj));
						obj.bills[i] = { 'transaction' : robj }
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
				obj.distribute_payment(obj.controller.view.bill_payment_amount);
				obj.tally_selected();
				obj.tally_voided();
		} catch(E) {
			obj.error.standard_unexpected_error_alert('bills -> refresh',E);	
		}
	},

	'init' : function( params ) {
	
		var obj = this;

		try {
				obj.init_controller( params );

				obj.retrieve();

				var total_owed = 0;

				JSAN.use('util.money');

				obj.current_payments = []; obj.list.clear();
				//FIXME//.bills virtual field
				for (var i = 0; i < obj.bills.length; i++) {
					var rparams = obj.list.append( 
						{ 'row' : 
							{ 'my' : 
								{ 'mobts' : obj.bills[i].transaction, 'circ' : obj.bills[i].circ, 'mvr' : obj.bills[i].record } 
							}, 
							'attributes' : { 'allowevents' : true } 
						} 
					);
					var rnode = rparams.my_node;
					obj.bill_map[ obj.bills[i].transaction.id() ] = obj.bills[i];
					var cb = rnode.getElementsByTagName('checkbox')[0];
					var tb = rnode.getElementsByTagName('textbox')[0];
					var bo = obj.bills[i].transaction.balance_owed();
					total_owed += util.money.dollars_float_to_cents_integer( bo );
					var id = obj.bills[i].transaction.id();
					obj.current_payments.push( { 'mobts_id' : id, 'balance_owed' : bo, 'checkbox' : cb, 'textbox' : tb } );
				}
				obj.controller.view.bill_total_owed.value = util.money.cents_as_dollars( total_owed );
				obj.controller.view.bill_total_owed.setAttribute('value',obj.controller.view.bill_total_owed.value);
				obj.distribute_payment(obj.controller.view.bill_payment_amount);
				obj.controller.view.bill_payment_amount.select();
				obj.tally_selected();
				obj.tally_voided();
		} catch(E) {
			obj.error.standard_unexpected_error_alert('bills -> init',E);	
		}
	},

	'init_controller' : function( params ) {

		var obj = this;

		try {
				if (obj._controller_inited) return;

				obj.patron_id = obj.patron_id || params['patron_id'];

				JSAN.use('util.list'); obj.list = new util.list('bill_list');

				obj.list.init(
					{
						'columns' : [
						/*
								{
									'id' : 'xact_dates', 'label' : document.getElementById('commonStrings').getString('staff.bills_xact_dates_label'), 'flex' : 1,
									'primary' : false, 'hidden' : false, 'render' : 'obj.xact_dates_box(my.mobts)'
								},
						*/
								{
									'id' : 'notes', 'label' : document.getElementById('commonStrings').getString('staff.bills_information'), 'flex' : 2,
									'primary' : false, 'hidden' : false, 'render' : 'obj.info_box(my)'
								},
								{
									'id' : 'money', 'label' : $('patronStrings').getString('staff.patron.bills.init_controller.money_summary_label'), 'flex' : 1,
									'primary' : false, 'hidden' : false, 'render' : 'obj.money_box(my.mobts)'
								},
								{
									'id' : 'current_pay', 'label' : document.getElementById('commonStrings').getString('staff.bills_current_payment_label'), 'flex' : 0, 
									'render' : 'obj.payment_box()'
								}
						],
						'map_row_to_column' : obj.gen_map_row_to_column()
					}
				);

				JSAN.use('util.controller'); obj.controller = new util.controller();
				obj.controller.init(
					{
						'control_map' : {
							'cmd_broken' : [
								['command'],
								function() { alert($("commonStrings").getString('common.unimplemented')); }
							],
							'cmd_bill_wizard' : [
								['command'],
								function() { 
									try {
										JSAN.use('util.window');
										var win = new util.window();
										var my_xulG = win.open(
											urls.XUL_PATRON_BILL_WIZARD,
												//+ '?patron_id=' + window.escape(obj.patron_id),
											'billwizard',
											'chrome,resizable,modal',
											{ 'patron_id' : obj.patron_id }
										);
										obj.refresh();
									} catch(E) {
										obj.error.standard_unexpected_error_alert('bills -> cmd_bill_wizard',E);	
									}
								}
							],
							'cmd_bill_history' : [
								['command'],
								function() { 
									try {
										JSAN.use('util.window');
										var win = new util.window();
										//obj.OpenILS.data.init({'via':'stash'}); obj.OpenILS.data.temp = ''; obj.OpenILS.data.stash('temp');
										var my_xulG = win.open(
											urls.XUL_PATRON_BILL_HISTORY,
												//+ '?patron_id=' + window.escape(obj.patron_id),
											'billhistory',
											//'chrome,resizable,modal'
											'chrome,resizable',
											{
												'patron_id' : obj.patron_id,
												'refresh' : function() { obj.refresh(); }
											}
										);
									} catch(E) {
										obj.error.standard_unexpected_error_alert('bills -> cmd_bill_history',E);	
									}
								}
							],
							'cmd_alternate_view' : [
								['command'],
								function() { 
									try {
										JSAN.use('util.window');
										var win = new util.window();
										//obj.OpenILS.data.init({'via':'stash'}); obj.OpenILS.data.temp = ''; obj.OpenILS.data.stash('temp');
										var my_xulG = win.open(
											urls.XUL_PATRON_BILL_HISTORY,
												//+ '?current=1&patron_id=' + window.escape(obj.patron_id),
											'billhistory',
											//'chrome,resizable,modal'
											'chrome,resizable',
											{
												'current' : 1,
												'patron_id' : obj.patron_id,
												'refresh' : function() { obj.refresh(); }
											}
										);
									} catch(E) {
										obj.error.standard_unexpected_error_alert('bills -> cmd_alternate_view',E);	
									}
								}
							],
                            'cmd_print_bills' : [
                                ['command'],
                                function() {
									try {
										obj.print_bills();
									} catch(E) {
										obj.error.standard_unexpected_error_alert('bills -> cmd_print_bills',E);	
									}

                                }
                            ],
							'cmd_change_to_credit' : [
								['command'],
								function() {
									try {
										obj.change_to_credit();
									} catch(E) {
										obj.error.standard_unexpected_error_alert('bills -> cmd_change_to_credit',E);	
									}
								}
							],
							'cmd_bill_apply_payment' : [
								['command'],
								function() {
									try { 
										obj.apply_payment(); 
									} catch(E) { 
										obj.error.standard_unexpected_error_alert('bills -> cmd_bill_apply_payment',E);	
									}
								}
							],
							'cmd_check_all' : [
								['command'],
								function() {
									for (var i = 0; i < obj.current_payments.length; i++) {
										obj.current_payments[i].checkbox.setAttribute('checked',true); //checked = true;
									}
									obj.distribute_payment(obj.controller.view.bill_payment_amount);
									obj.tally_selected();
								}
							],
							'cmd_uncheck_all' : [
								['command'],
								function() {
									for (var i = 0; i < obj.current_payments.length; i++) {
										obj.current_payments[i].checkbox.setAttribute('checked',false); //checked = false;
									}
									obj.distribute_payment(obj.controller.view.bill_payment_amount);
									obj.tally_selected();
								}
							],
							'voided_balance' : [
								['render'],
								function(e) { return function() {}; }
							],
							'selected_balance' : [
								['render'],
								function(e) { return function() {}; }
							],
							'unselected_balance' : [
								['render'],
								function(e) { return function() {}; }
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
								['change','keypress'],
								function(ev) {
									try {
											if (ev.type == 'keypress') {
												if (! (ev.keyCode == 13 /* enter */ || ev.keyCode == 77 /* mac enter */) ) {
													return;	
												}
											}
											if (ev.type == 'change' && obj.controller.view.payment_type.value == 'credit_payment') {
												JSAN.use('util.money');
												JSAN.use('patron.util'); var au_obj = patron.util.retrieve_au_via_id(ses(),obj.patron_id);
												var proposed = util.money.dollars_float_to_cents_integer(ev.target.value);
												var available = util.money.dollars_float_to_cents_integer(au_obj.credit_forward_balance());
												if (proposed > available) {
													alert($("patronStrings").getFormattedString('staff.patron.bills.bill_payment_amount.credit_amount', [au_obj.credit_forward_balance()]));
													ev.target.value = util.money.cents_as_dollars( available );
													ev.target.setAttribute('value',ev.target.value);
												}
											}
											obj.distribute_payment(ev.target);
											ev.target.select();
											obj.tally_selected();
									} catch(E) {
										obj.error.standard_unexpected_error_alert('bills -> bill_payment_amount',E);	
									}
								} 
							],
							'bill_payment_applied' : [
								['render'],
								function(e) { return function() {}; }
							],
							'bill_change_amount' : [
								['change'],
								function(ev) {
									try {
											JSAN.use('util.money');
											var tb = ev.target;
											var proposed_change = util.money.dollars_float_to_cents_integer( tb.value );
											var proposed_credit = 0;
											obj.update_payment_applied();
											var real_change = util.money.dollars_float_to_cents_integer( tb.value );
											if ( proposed_change > real_change ) {
												obj.error.sdump('D_ERROR',$("patronStrings").getString('staff.patron.bills.bill_change_amount.greedy'));
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
									} catch(E) {
										obj.error.standard_unexpected_error_alert('bills -> bill_change_amount',E);	
									}
								}
							],
							'bill_credit_amount' : [
								['render'],
								function(e) { return function() {}; }
							],
							'bill_new_balance' : [
								['render'],
								function(e) { return function() {}; }
							]
						}
					}
				);

				obj.controller.render();
				obj._controller_inited = true;
		} catch(E) {
			obj.error.standard_unexpected_error_alert('bills -> init_controller',E);	
		}

	},

	/*****************************************************************************************************************************/

	'distribute_payment' : function(node) {
		try {
			var obj = this;
			JSAN.use('util.money');
			var tb = node;
			tb.value = util.money.cents_as_dollars( util.money.dollars_float_to_cents_integer( tb.value ) );
			tb.setAttribute('value', tb.value );
			var total = util.money.dollars_float_to_cents_integer( tb.value );
			if (total < 0) { tb.value = '0.00'; tb.setAttribute('value','0.00'); total = 0; }
			for (var i = 0; i < obj.current_payments.length; i++) {
					var bill = obj.current_payments[i];
					if (bill.checkbox.checked || bill.checkbox.getAttribute('checked') == 'true') {
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
		} catch(E) {
			obj.error.standard_unexpected_error_alert('bills -> distribute payment',E);
		}
	},

	/*****************************************************************************************************************************/

	'tally_selected' : function() {

			var obj = this;
			JSAN.use('util.money');
			var selected_total = 0;
			var unselected_total = 0;
			//var s = '';

			for (var i = 0; i < obj.current_payments.length; i++) {
				var bill = obj.current_payments[i];
				if (bill.checkbox.checked || bill.checkbox.getAttribute('checked') == 'true') {
					var bo = util.money.dollars_float_to_cents_integer( bill.balance_owed );
					selected_total += bo;
					//s += ('tallying ' + i + ' : checked, bo = ' + bo + '  total = ' + selected_total + '\n');
				} else {
					var bo = util.money.dollars_float_to_cents_integer( bill.balance_owed );
					unselected_total += bo;
					//s += ('tallying ' + i + ' : not checked, total = ' + selected_total + '\n');
				}
			}
			obj.controller.view.selected_balance.setAttribute('value', '$' + util.money.cents_as_dollars( selected_total ) );
			obj.controller.view.unselected_balance.setAttribute('value', '$' + util.money.cents_as_dollars( unselected_total ) );
			//dump(s); alert(s);
	},

	/*****************************************************************************************************************************/

	'tally_voided' : function() {

			var obj = this;
			JSAN.use('util.money');
			var voided_total = 0;

			obj.data.stash_retrieve();

			for (var i = 0; i < obj.data.voided_billings.length; i++) {
				var billing = obj.data.voided_billings[i];
				var bv = util.money.dollars_float_to_cents_integer( billing.amount() );
				voided_total += bv;
			}
			obj.controller.view.voided_balance.setAttribute('value', '$' + util.money.cents_as_dollars( voided_total ) );
	},

	/*****************************************************************************************************************************/

	'apply_payment' : function() {

		var obj = this;
		try {
				var payment_blob = {};
				JSAN.use('util.window');
				var win = new util.window();
				switch(obj.controller.view.payment_type.value) {
					case 'credit_card_payment' :
						obj.OpenILS.data.temp = '';
						obj.OpenILS.data.stash('temp');
						var my_xulG = win.open(
							urls.XUL_PATRON_BILL_CC_INFO,
							'billccinfo',
							'chrome,resizable,modal'
						);
						obj.OpenILS.data.stash_retrieve();
						//payment_blob = my_xulG.payment_blob; //JSON2js( obj.OpenILS.data.temp );
						payment_blob = JSON2js( obj.OpenILS.data.temp );
					break;
					case 'check_payment' :
						obj.OpenILS.data.temp = '';
						obj.OpenILS.data.stash('temp');
						var my_xulG = win.open(
							urls.XUL_PATRON_BILL_CHECK_INFO,
							'billcheckinfo',
							'chrome,resizable,modal'
						);
						obj.OpenILS.data.stash_retrieve();
						//payment_blob = my_xulG.payment_blob; //JSON2js( obj.OpenILS.data.temp );
						payment_blob = JSON2js( obj.OpenILS.data.temp );
					break;
				}
				if ((typeof payment_blob == 'undefined') || payment_blob=='' || payment_blob.cancelled=='true') { alert('cancelled'); return; }
				payment_blob.userid = obj.patron_id;
				payment_blob.note = payment_blob.note || '';
				//payment_blob.cash_drawer = 1; // FIXME: get new Config() to work
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
                if ( payment_blob.payments.length == 0 && payment_blob.patron_credit == '0.00' ) {
                    alert($("patronStrings").getString('staff.patron.bills.apply_payment.nothing_applied'));
                    return;
                }
				if ( obj.pay( payment_blob ) ) {

					obj.data.voided_billings = []; obj.data.stash('voided_billings');
					obj.refresh();
					try {
						netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
						obj.data.stash_retrieve();
						var template = 'bill_payment';
						JSAN.use('patron.util'); JSAN.use('util.functional');
						var params = { 
							'patron' : patron.util.retrieve_fleshed_au_via_id(ses(),obj.patron_id), 
							'lib' : obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ],
							'staff' : obj.data.list.au[0],
							'header' : obj.data.print_list_templates[template].header,
							'line_item' : obj.data.print_list_templates[template].line_item,
							'footer' : obj.data.print_list_templates[template].footer,
							'type' : obj.data.print_list_templates[template].type,
							'list' : util.functional.map_list(
								payment_blob.payments,
								function(o) {
									return {
										'bill_id' : o[0],
										'payment' : o[1],
										'last_billing_type' : obj.bill_map[ o[0] ].transaction.last_billing_type(),
										'last_billing_note' : obj.bill_map[ o[0] ].transaction.last_billing_note(),
										'title' : typeof obj.bill_map[ o[0] ].title != 'undefined' ? obj.bill_map[ o[0] ].title : '', 
										'barcode' : typeof obj.bill_map[ o[0] ].barcode != 'undefined' ? obj.bill_map[ o[0] ].barcode : ''
									};
								}
							),
							'data' : obj.previous_summary
						};
						obj.error.sdump('D_DEBUG',js2JSON(params));
						if (document.getElementById('auto_print').checked) params.no_prompt = true;
						JSAN.use('util.print'); var print = new util.print();
						print.tree_list( params );
					} catch(E) {
						obj.error.standard_unexpected_error_alert('bill receipt', E);
					}
				}
		} catch(E) {
			obj.error.standard_unexpected_error_alert('bills -> apply_payment',E);	
		}
	},

	'pay' : function(payment_blob) {
		var obj = this;
		try {
            var x = document.getElementById('annotate_payment');
            if (x && x.checked && (! payment_blob.note)) {
                payment_blob.note = window.prompt($("patronStrings").getString('staff.patron.bills.pay.annotate_payment'),'', $("patronStrings").getString('staff.patron.bills.pay.annotate_payment.title'));
            }
			obj.previous_summary = {
				original_balance : obj.controller.view.bill_total_owed.value,
				voided_balance : obj.controller.view.voided_balance.value,
				payment_received : obj.controller.view.bill_payment_amount.value,
				payment_applied : obj.controller.view.bill_payment_applied.value,
				change_given : obj.controller.view.bill_change_amount.value,
				credit_given : obj.controller.view.bill_credit_amount.value,
				new_balance : obj.controller.view.bill_new_balance.value,
				payment_type : obj.controller.view.payment_type.getAttribute('label'),
				note : payment_blob.note
			}
			var robj = obj.network.request(
				api.BILL_PAY.app,	
				api.BILL_PAY.method,
				[ ses(), payment_blob ]
			);
			if (robj == 1) { return true; } 
			if (typeof robj.ilsevent != 'undefined') {
				switch(Number(robj.ilsevent)) {
					case 0 /* SUCCESS */ : return true; break;
					case 1226 /* REFUND_EXCEEDS_DESK_PAYMENTS */ : alert($("patronStrings").getFormattedString('staff.patron.bills.pay.refund_exceeds_desk_payment', [robj.desc])); return false; break;
					default: throw(robj); break;
				}
			}
		} catch(E) {
			obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.bills.pay.payment_failed'),E);
			return false;
		}
	},

	'update_payment_applied' : function() {
		var obj = this;
		try {
				JSAN.use('util.money');
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
		} catch(E) {
			obj.error.standard_unexpected_error_alert('bills -> update_payment_applied',E);	
		}
	},

	'change_to_credit' : function() {
		var obj = this;
		try {
				JSAN.use('util.money');
				var tb = obj.controller.view.bill_change_amount;
				var proposed_change = 0;
				var proposed_credit = util.money.dollars_float_to_cents_integer( tb.value );
				obj.update_payment_applied();
				var real_change = util.money.dollars_float_to_cents_integer( tb.value );
				if ( proposed_change > real_change ) {
					obj.error.sdump('D_ERROR',$("patronStrings").getString('staff.patron.bills.bill_change_amount.greedy'));
					proposed_change = real_change;
				} else if ( real_change > proposed_change ) {
					proposed_credit = real_change - proposed_change;
				}
				tb.value = util.money.cents_as_dollars( proposed_change );
				tb.setAttribute('value',tb.value);
				obj.controller.view.bill_credit_amount.value = util.money.cents_as_dollars( proposed_credit );
				obj.controller.view.bill_credit_amount.setAttribute('value',obj.controller.view.bill_credit_amount.value);
		} catch(E) {
			obj.error.standard_unexpected_error_alert('bills -> change_to_credit',E);	
		}
	},

	'retrieve' : function() {
		var obj = this;
		try {
				if (window.xulG && window.xulG.bills) {
					obj.bills = window.xulG.bills;
				} else {
					obj.bills = obj.network.simple_request(
						obj.SHOW_ME_THE_BILLS,	
						[ ses(), obj.patron_id ]
					);
					for (var i = 0; i < obj.bills.length; i++) {
						if (instanceOf(obj.bills[i],mobts)) {
							obj.bills[i] = { 'transaction' : obj.bills[i] }
						} else if (instanceOf(obj.bills[i],mbts)) {
							obj.bills[i] = { 'transaction' : obj.bills[i] }
						} else {
							var robj = obj.network.simple_request('FM_MBTS_RETRIEVE.authoritative',[ses(),obj.bills[i]]);
							//alert('robj = ' + js2JSON(robj));
							obj.bills[i] = { 'transaction' : robj }
						}
					}
				}
		} catch(E) {
			obj.error.standard_unexpected_error_alert('bills -> retrieve',E);	
		}
	},

    'print_bills' : function() {
        var obj = this;
        try {
            JSAN.use('util.functional'); JSAN.use('patron.util');
            var columns = patron.util.mbts_columns({});
            var template = 'bills_main_view';
            var params = { 
                'patron' : patron.util.retrieve_fleshed_au_via_id(ses(),obj.patron_id), 
                'lib' : obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ],
                'staff' : obj.data.list.au[0],
                'header' : obj.data.print_list_templates[template].header,
                'line_item' : obj.data.print_list_templates[template].line_item,
                'footer' : obj.data.print_list_templates[template].footer,
                'type' : obj.data.print_list_templates[template].type,
				'list' : util.functional.map_list(
                    obj.bills,
                    function(o) {
                        var id = o.transaction.id();
                        var hash = {
                            'title' : typeof obj.bill_map[ id ].title != 'undefined' ? obj.bill_map[ id ].title : '', 
                            'barcode' : typeof obj.bill_map[ id ].barcode != 'undefined' ? obj.bill_map[ id ].barcode : ''
                        };
                        for (var i = 0; i < columns.length; i++) {
                            var v = columns[i].render( { 'mbts' : o.transaction } );
                            hash[ columns[i].id ] = v == null ? '' : v;
                        }
                        return hash;
                    }
                )
            };
            JSAN.use('util.print'); var print = new util.print();
            print.tree_list( params );

        } catch(E) {
			obj.error.standard_unexpected_error_alert('bills -> print_bills',E);	
        }
    },

	'xact_dates_box' : function ( mobts ) {
		var obj = this;
		try {
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
							cb_r0_0.setAttribute('checked',true);
							var hb_r0_1 = document.createElement('hbox');
							row0.appendChild( hb_r0_1 );
								var label_r0_1 = document.createElement('label');
								hb_r0_1.appendChild( label_r0_1 );
								label_r0_1.setAttribute('value',document.getElementById('commonStrings').getString('staff.mbts_id_label'));
								var label_r0_2 = document.createElement('label');
								hb_r0_1.appendChild( label_r0_2 );
								label_r0_2.setAttribute('value',mobts.id());
						var row1 = document.createElement('row');
						rows.appendChild( row1 );
							var label_r1_1 = document.createElement('label');
							row1.appendChild( label_r1_1 );
							label_r1_1.setAttribute('value',document.getElementById('commonStrings').getString('staff.mbts_xact_start_label'));
							var label_r1_2 = document.createElement('label');
							row1.appendChild( label_r1_2 );
							label_r1_2.setAttribute('value',mobts.xact_start().toString().substr(0,10));
						var row2 = document.createElement('row');
						rows.appendChild( row2 );
							var label_r2_1 = document.createElement('label');
							row2.appendChild( label_r2_1 );
							label_r2_1.setAttribute('value',document.getElementById('commonStrings').getString('staff.mbts_xact_finish_label'));
							var label_r2_2 = document.createElement('label');
							row2.appendChild( label_r2_2 );
							try { label_r2_2.setAttribute('value',mobts.xact_finish().toString().substr(0,10));
							} catch(E) {}

				return grid;
		} catch(E) {
			obj.error.standard_unexpected_error_alert('bills -> xact_dates_box',E);	
		}
	},

	'money_box' : function ( mobts ) {
		var obj = this;
		try {
				JSAN.use('util.money');
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
							label_r1_1.setAttribute('value',document.getElementById('commonStrings').getString('staff.mbts_total_owed_label'));
							var label_r1_2 = document.createElement('label');
							row1.appendChild( label_r1_2 );
							label_r1_2.setAttribute('value','$' + util.money.sanitize(mobts.total_owed() || '0') );
						var row2 = document.createElement('row');
						rows.appendChild( row2 );
							var label_r2_1 = document.createElement('label');
							row2.appendChild( label_r2_1 );
							label_r2_1.setAttribute('value',document.getElementById('commonStrings').getString('staff.mbts_total_paid_label'));
							var label_r2_2 = document.createElement('label');
							row2.appendChild( label_r2_2 );
							label_r2_2.setAttribute('value','$' + util.money.sanitize(mobts.total_paid() || '0') );
						var row3 = document.createElement('row');
						rows.appendChild( row3 );
							var label_r3_1 = document.createElement('label');
							row3.appendChild( label_r3_1 );
							label_r3_1.setAttribute('value',document.getElementById('commonStrings').getString('staff.mbts_balance_owed_label'));
							label_r3_1.setAttribute('style','font-weight: bold');
							var label_r3_2 = document.createElement('label');
							row3.appendChild( label_r3_2 );
							label_r3_2.setAttribute('value','$' + util.money.sanitize(mobts.balance_owed() || '0') );
							label_r3_2.setAttribute('style','font-weight: bold');

				return grid;
		} catch(E) {
			obj.error.standard_unexpected_error_alert('bills -> money_box',E);	
		}
	},

	'info_box' : function ( my ) {
		var obj = this;
		try {
				var vbox = document.createElement('vbox');

					var hbox = document.createElement('hbox');
						vbox.appendChild( hbox ); hbox.flex = 1;

						var cb = document.createElement('checkbox');
						hbox.appendChild( cb ); 
						if ( my.mobts.balance_owed() == 0 ) { 
							cb.setAttribute('disabled', 'true'); 
						} else { 
							if (my.mobts.balance_owed() > 0) {
								cb.setAttribute('checked', true); 
							}
						}
						cb.addEventListener(
							'command',
							function() {
								setTimeout(
									function() {
										obj.distribute_payment(obj.controller.view.bill_payment_amount);
										obj.tally_selected();
									}, 0
								);
							},
							false
						);


					var grid = document.createElement('grid');
						hbox.appendChild( grid );

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
							xt_label.setAttribute( 'value', $("patronStrings").getString('staff.patron.bills.info_box.label_value.title') );
							obj.network.simple_request(
								'FM_CIRC_RETRIEVE_VIA_ID',
								[ ses(), my.mobts.id() ],
								function (req) {
									var r_circ = req.getResultObject();
									if (instanceOf(r_circ,circ)) {
										/*
										xt_start.setAttribute('value','Checked Out: ' + r_circ.xact_start().toString().substr(0,10) );
										if (r_circ.checkin_time()) {
											xt_finish.setAttribute('value','Returned: ' + r_circ.checkin_time().toString().substr(0,10) );
										} else {
											xt_finish.setAttribute('value','Due: ' + r_circ.due_date().toString().substr(0,10) );
										}
										*/
										if (! r_circ.checkin_time()) {
											xt_value.setAttribute('style','background: red; color: white');
											if (document.getElementById('circulating_hint')) {
												document.getElementById('circulating_hint').hidden = false;
											}
										}
										obj.network.simple_request(
											'MODS_SLIM_RECORD_RETRIEVE_VIA_COPY',
											[ r_circ.target_copy() ],
											function (rreq) {
												var r_mvr = rreq.getResultObject();
												if (instanceOf(r_mvr,mvr)) {
													xt_value.appendChild( document.createTextNode( String( r_mvr.title() ).substr(0,50) ) );
													obj.bill_map[ my.mobts.id() ].title = r_mvr.title();
												}
											}
										);
										obj.network.simple_request(
											'FM_ACP_RETRIEVE',
											[ r_circ.target_copy() ],
											function (rrreq) {
												var r_acp = rrreq.getResultObject();
												if (instanceOf(r_acp,acp)) {
													xt_value.appendChild( document.createTextNode( r_acp.dummy_title() ) );
													if (r_acp.dummy_title()) obj.bill_map[ my.mobts.id() ].title = r_acp.dummy_title();
													obj.bill_map[ my.mobts.id() ].barcode = r_acp.barcode();
												}
											}
										);
									}
								}
							);
						break;
						default:
								xt_label.setAttribute( 'value',
									my.mvr ? $("patronStrings").getString('staff.patron.bills.info_box.label_value.title') : $("patronStrings").getString('staff.patron.bills.info_box.label_value.type') );
								xt_value.appendChild( document.createTextNode( my.mvr ? my.mvr.title() : my.mobts.xact_type() ) );
						break;
					}
					} catch(E) { alert(E); }

					var last_billing = document.createElement('row');
					rows.appendChild( last_billing );

						var lb_label = document.createElement('label');
							last_billing.appendChild( lb_label );
							lb_label.setAttribute( 'value', $("patronStrings").getString('staff.patron.bills.info_box.label_value.last_billing') );

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
								btn.setAttribute( 'label', $("patronStrings").getString('staff.patron.bills.info_box.label_value.full_details') );
								btn.setAttribute( 'name', 'full_details' );
								btn.setAttribute( 'mobts_id', my.mobts.id() );	
								btn.addEventListener(
									'command',
									function(ev) {
										JSAN.use('util.window'); var win = new util.window();
										var my_xulG = win.open(
											urls.XUL_PATRON_BILL_DETAILS,
											//+ '?patron_id=' + window.escape(obj.patron_id)
											//+ '&mbts_id=' + window.escape(my.mobts.id()),
											'test' + my.mobts.id(),
											'chrome,resizable',
											{
												'patron_id' : obj.patron_id,
												'mbts_id' : my.mobts.id(),
												'refresh' : function() { obj.refresh(); },
											}
										);
									},
									false
								);
							var btn2 = document.createElement('button');
								btn_box.appendChild( btn2 );
								btn2.setAttribute( 'label', $("patronStrings").getString('staff.patron.bills.info_box.label_value.add_billing') );
								btn2.setAttribute( 'mobts_id', my.mobts.id() );	
								btn2.addEventListener(
									'command',
									function(ev) {
										JSAN.use('util.window');
										var win = new util.window();
										var my_xulG = win.open(
											urls.XUL_PATRON_BILL_WIZARD,
												//+ '?patron_id=' + window.escape(obj.patron_id)
												//+ '&xact_id=' + window.escape( my.mobts.id() ),
											'billwizard',
											'chrome,resizable,modal',
											{
												'patron_id' : obj.patron_id,
												'xact_id' : my.mobts.id(),
											}
										);
										obj.refresh();
									},
									false
								);
				if (my.mobts.balance_owed() < 0) {
					var btn3 = document.createElement('button');
					btn_box.appendChild( btn3 );
					btn3.setAttribute( 'label', $("patronStrings").getString('staff.patron.bills.info_box.label_value.refund') );
					btn3.setAttribute( 'mobts_id', my.mobts.id() );	
					btn3.addEventListener(
						'command',
						function(ev) {
							cb.setAttribute('checked',true);
							obj.distribute_payment(obj.controller.view.bill_payment_amount);
							obj.tally_selected();
						},
						false
					);
				}

				var btn4 = document.createElement('button');
				btn_box.appendChild( btn4 );
				btn4.setAttribute( 'label', $("patronStrings").getString('staff.patron.bills.info_box.label_value.void_all_billings') );
				btn4.setAttribute( 'mobts_id', my.mobts.id() );
				btn4.addEventListener(
					'command',
					function(ev) {
						obj.void_all_billings( my.mobts.id() );
					},
					false
				);

				return vbox;
		} catch(E) {
			obj.error.standard_unexpected_error_alert('bills -> info_box',E);	
		}
	},

	'payment_box' : function() {
		try {
			var vb = document.createElement('vbox');
			var tb = document.createElement('textbox');
			tb.setAttribute('readonly','true');
			vb.appendChild(tb);
			return vb;
		} catch(E) {
			this.error.standard_unexpected_error_alert('bills -> payment_box',E);	
		}
	},

	'void_all_billings' : function(mobts_id) {
		try {
			var obj = this;
			JSAN.use('util.functional');
			
			var mb_list = obj.network.simple_request( 'FM_MB_RETRIEVE_VIA_MBTS_ID.authoritative', [ ses(), mobts_id ] );
			if (typeof mb_list.ilsevent != 'undefined') throw(mb_list);

			mb_list = util.functional.filter_list( mb_list, function(o) { return ! get_bool( o.voided() ) });

			if (mb_list.length == 0) { alert($("patronStrings").getString('staff.patron.bills.void_all_billings.all_voided')); return; }

			var sum = 0;
			for (var i = 0; i < mb_list.length; i++) sum += util.money.dollars_float_to_cents_integer( mb_list[i].amount() );
			sum = util.money.cents_as_dollars( sum );

			var msg = $("patronStrings").getFormattedString('staff.patron.bills.void_all_billings.void.message', [sum]);
			var r = obj.error.yns_alert(msg,
				$("patronStrings").getString('staff.patron.bills.void_all_billings.void.title'),
				$("patronStrings").getString('staff.patron.bills.void_all_billings.void.yes'),
				$("patronStrings").getString('staff.patron.bills.void_all_billings.void.no'), null,
				$("patronStrings").getString('staff.patron.bills.void_all_billings.void.confirm_message'));
			if (r == 0) {
				var robj = obj.network.simple_request('FM_MB_VOID',[ses()].concat(util.functional.map_list(mb_list,function(o){return o.id();})));
				if (robj.ilsevent) {
					switch(Number(robj.ilsevent)) {
						default: 
							obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.bills.void_all_billings.error_voiding_bills'),robj); 
							obj.refresh(); return; 
						break;
					}
				}

				obj.data.stash_retrieve(); if (! obj.data.voided_billings ) obj.data.voided_billings = []; 
				for (var i = 0; i < mb_list.length; i++) {
						obj.data.voided_billings.push( mb_list[i] );
				}
				obj.data.stash('voided_billings');
				alert($("patronStrings").getString('staff.patron.bills.void_all_billings.billings_voided'));
				obj.refresh();
			}
		} catch(E) {
			try { obj.error.standard_unexpected_error_alert('bills.js, void_all_billings():',E); } catch(F) { alert(E); }
		}

	},
	
	'gen_map_row_to_column' : function() {
		var obj = this;

		try {

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

		} catch(E) {
			obj.error.standard_unexpected_error_alert('bills -> gen_map_row_to_column',E);	
		}
	},

}

dump('exiting patron.bills.js\n');
