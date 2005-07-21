sdump('D_TRACE','Loading patron_bills.js\n');

function patron_bills_init(p) {
	sdump('D_PATRON_BILLS',"TESTING: patron_bills.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	patron_bills_list_box_init( p );

	patron_bills_control_box_init( p );

	p.current_payments = [];

	p.update_payment_applied = function () {
		sdump('D_PATRON_BILLS','p.update_payment_applied()\n');
		var total_applied = 0;
		for (var i = 0; i < p.current_payments.length; i++) {
			total_applied += dollars_float_to_cents_integer( p.current_payments[ i ].textbox.value );
		}
		var total_payment = 0;
		if (p.control_box.bill_payment_amount.value) {
			try {
				total_payment = dollars_float_to_cents_integer( p.control_box.bill_payment_amount.value );
			} catch(E) {
				sdump('D_ERROR',E + '\n');
			}
		}
		if ( total_applied > total_payment ) {
			total_payment = total_applied;
			p.control_box.bill_payment_amount.value = cents_as_dollars( total_applied );
		}
		p.control_box.bill_payment_applied.setAttribute('value', cents_as_dollars( total_applied ));
		p.control_box.bill_payment_applied.value = cents_as_dollars( total_applied );
		p.control_box.bill_credit_amount.value = '';
		if (total_payment > total_applied ) {
			p.control_box.bill_change_amount.value = cents_as_dollars( total_payment - total_applied);
			p.control_box.bill_credit_amount.value = '0.00';
		} else {
			p.control_box.bill_change_amount.value = '0.00';
			p.control_box.bill_credit_amount.value = '0.00';
		}
		var total_owed = dollars_float_to_cents_integer( p.control_box.bill_total_owed.value );
		p.control_box.bill_new_balance.value = cents_as_dollars( total_owed - total_applied );
	}

	p.list_box.apply_to_each_listitem = function (idx, listitem) {
		sdump('D_PATRON_BILLS','p.list_box.apply_to_each_listitem()\n');
		p.current_payments[ idx ] = {};
		p.current_payments[ idx ].listitem = listitem;
		p.current_payments[ idx ].checkbox = listitem.getElementsByTagName('checkbox')[0];
		p.current_payments[ idx ].textbox = listitem.getElementsByTagName('textbox')[0];
		p.current_payments[ idx ].mbts_id = listitem.getAttribute('record_id');
		p.current_payments[ idx ].balance_owed = listitem.getAttribute('balance_owed');

		p.current_payments[ idx ].textbox.addEventListener(
			'change',
			function () {
				sdump('D_PATRON_BILLS','listitem textbox onchange handler()\n');
				var tb = p.current_payments[ idx ].textbox;
				var bo = p.current_payments[ idx ].balance_owed;
				tb.value = cents_as_dollars( dollars_float_to_cents_integer( tb.value ) ); // show user what we think the number is
				sdump('D_PATRON_BILLS','bo = ' + bo + '\ntb.value = ' + tb.value + '\n');
				if ( dollars_float_to_cents_integer( tb.value ) > dollars_float_to_cents_integer( bo ) ) {
					sdump('D_PATRON_BILLS','Tried to overpay bill\n');
					tb.value = bo;
				}
				p.update_payment_applied();
			},
			false
		);
	}

	p.control_box.bill_payment_amount.addEventListener(
		'change',
		function () {
			var tb = p.control_box.bill_payment_amount;
			tb.value = cents_as_dollars( dollars_float_to_cents_integer( tb.value ) );
			var total = dollars_float_to_cents_integer( tb.value );
			for (var i = 0; i < p.current_payments.length; i++) {
				var bill = p.current_payments[i];
				if (bill.checkbox.checked) {
					var bo = dollars_float_to_cents_integer( bill.balance_owed );
					if ( bo > total ) {
						bill.textbox.value = cents_as_dollars( total );
						total = 0;
					} else {
						bill.textbox.value = cents_as_dollars( bo );
						total = total - bo;
					}
				} else {
					bill.textbox.value = '0.00';
				}
			}
			p.update_payment_applied();
		},
		false
	);

	p.control_box.bill_change_amount.addEventListener(
		'change',
		function() {
			var tb = p.control_box.bill_change_amount;
			var proposed_change = dollars_float_to_cents_integer( tb.value );
			var proposed_credit = 0;
			p.update_payment_applied();
			var real_change = dollars_float_to_cents_integer( tb.value );
			if ( proposed_change > real_change ) {
				sdump('D_ERROR','Someone wanted more money than they deserved\n');
				proposed_change = real_change;
			} else if ( real_change > proposed_change ) {
				proposed_credit = real_change - proposed_change;
			}
			tb.value = cents_as_dollars( proposed_change );
			p.control_box.bill_credit_amount.value = cents_as_dollars( proposed_credit );
		},
		false
	);

	p.control_box.bill_apply_payment.addEventListener(
		'command',
		function() { 
			//alert(p.control_box.payment_type.value);	
			var payment_blob = {};
			payment_blob.payment_type = p.control_box.payment_type.value;
			payment_blob.payments = [];
			for (var i = 0; i < p.current_payments.length; i++) {
				var tb = p.current_payments[ i ].textbox;
				if ( !(tb.value == '0.00' || tb.value == '') ) {
					payment_blob.payments.push( 
						[
							p.current_payments[ i ].mbts_id,
							tb.value
						]
					);
				}
			}
			try {
				if ( patron_pay_bills( payment_blob ) ) {

					if (p.refresh) p.refresh();

				}

			} catch(E) {

				handle_error(E);
			}
		},
		false
	);

	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return p;
}

function patron_bills_control_box_init( p ) {
	p.control_box = {};
	p.control_box.node = p.node.previousSibling;
	p.control_box.node2 = p.node.nextSibling;
	p.control_box.bill_total_owed = p.control_box.node.getElementsByAttribute('id','bill_total_owed')[0];
	p.control_box.payment_type = p.control_box.node.getElementsByAttribute('id','payment_type_menulist')[0];
	p.control_box.bill_payment_amount = p.control_box.node.getElementsByAttribute('id','bill_payment_amount_textbox')[0];
	p.control_box.bill_payment_applied = p.control_box.node.getElementsByAttribute('id','bill_payment_applied_textbox')[0];
	p.control_box.bill_change_amount = p.control_box.node.getElementsByAttribute('id','bill_change_amount_textbox')[0];
	p.control_box.bill_credit_amount = p.control_box.node.getElementsByAttribute('id','bill_credit_amount_textbox')[0];
	p.control_box.bill_apply_payment = p.control_box.node.getElementsByAttribute('id','bill_apply_payment')[0];
	p.control_box.bill_new_balance = p.control_box.node.getElementsByAttribute('id','bill_new_balance_textbox')[0];
}

function patron_bills_list_box_init( p ) {
	p.patron_bills_cols = [
		{
			'id' : 'checkbox', 'label' : '', 'flex' : 0, 'primary' : false, 'hidden' : false,
			'render_xul' : 'checkbox'
		},
		{
			'id' : 'xact_dates', 'label' : getString('bills_xact_dates_label'), 'flex' : 0,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mbts', 
			'fm_field_render' : 'xact_dates_box($$)'
		},
		{
			'id' : 'notes', 'label' : getString('bills_information'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mbts',
			'fm_field_render' : '.last_billing_note()'
		},
		{
			'id' : 'money', 'label' : getString('bills_money_label'), 'flex' : 0,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mbts', 
			'fm_field_render' : 'money_box($$)'
		},
		{
			'id' : 'current_pay', 'label' : getString('bills_current_payment_label'), 'flex' : 0, 
			'render_xul' : 'textbox'
		}
	];

	p.list_box = list_box_init( { 'w' : p.w, 'node' : p.node, 'cols' : p.patron_bills_cols, 'debug' : p.app } );
	p.clear_patron_bills = function () { 
		p.current_payments = []; 
		p.control_box.bill_total_owed.setAttribute('value', 'Calculating...');
		p.control_box.bill_total_owed.value = 'Calculating...';
		p.control_box.bill_payment_amount.setAttribute('value', '');
		p.control_box.bill_payment_amount.value = '';
		p.control_box.bill_payment_applied.setAttribute('value', '0.00');
		p.control_box.bill_payment_applied.value = '0.00';
		p.control_box.bill_change_amount.setAttribute('value', '0.00');
		p.control_box.bill_change_amount.value = '0.00';
		p.control_box.bill_credit_amount.setAttribute('value', '0.00');
		p.control_box.bill_credit_amount.value = '0.00';
		p.control_box.bill_new_balance.setAttribute('value', 'Calculating...');
		p.control_box.bill_new_balance.value = 'Calculating...';
		p.list_box.clear_rows(); 
	};
	p.add_patron_bills = function (bills) {
		sdump('D_PATRON_BILLS','p.add_patron_bills(' + bills + ')\n');
		return patron_bills_add_patron_bills(p,bills);
	}
}

function patron_bills_add_patron_bills(p, bills) {
	sdump('D_PATRON_BILLS',arg_dump(arguments,{1:true}));

	p.control_box.bill_total_owed.setAttribute('value',get_bills_total( bills ));
	p.control_box.bill_total_owed.value = get_bills_total( bills );
	p.control_box.bill_new_balance.setAttribute('value',get_bills_total( bills ));
	p.control_box.bill_new_balance.value = get_bills_total( bills );

	function xact_dates_box( mbts ) {
		var grid = p.w.document.createElement('grid');
			var cols = p.w.document.createElement('columns');
			grid.appendChild( cols );
				cols.appendChild( p.w.document.createElement('column') );
				cols.appendChild( p.w.document.createElement('column') );
			var rows = p.w.document.createElement('rows');
			grid.appendChild( rows );
				var row0 = p.w.document.createElement('row');
				rows.appendChild( row0 );
					var label_r0_1 = p.w.document.createElement('label');
					row0.appendChild( label_r0_1 );
					label_r0_1.setAttribute('value',getString('mbts_id_label'));
					var label_r0_2 = p.w.document.createElement('label');
					row0.appendChild( label_r0_2 );
					label_r0_2.setAttribute('value',mbts.id());
				var row1 = p.w.document.createElement('row');
				rows.appendChild( row1 );
					var label_r1_1 = p.w.document.createElement('label');
					row1.appendChild( label_r1_1 );
					label_r1_1.setAttribute('value',getString('mbts_xact_start_label'));
					var label_r1_2 = p.w.document.createElement('label');
					row1.appendChild( label_r1_2 );
					label_r1_2.setAttribute('value',mbts.xact_start().toString().substr(0,10));
				var row2 = p.w.document.createElement('row');
				rows.appendChild( row2 );
					var label_r2_1 = p.w.document.createElement('label');
					row2.appendChild( label_r2_1 );
					label_r2_1.setAttribute('value',getString('mbts_xact_finish_label'));
					var label_r2_2 = p.w.document.createElement('label');
					row2.appendChild( label_r2_2 );
					try { label_r2_2.setAttribute('value',mbts.xact_finish().toString().substr(0,10));
					} catch(E) {}

		return grid;
	}

	function money_box( mbts ) {
		var grid = p.w.document.createElement('grid');
			var cols = p.w.document.createElement('columns');
			grid.appendChild( cols );
				cols.appendChild( p.w.document.createElement('column') );
				cols.appendChild( p.w.document.createElement('column') );
			var rows = p.w.document.createElement('rows');
			grid.appendChild( rows );
				var row1 = p.w.document.createElement('row');
				rows.appendChild( row1 );
					var label_r1_1 = p.w.document.createElement('label');
					row1.appendChild( label_r1_1 );
					label_r1_1.setAttribute('value',getString('mbts_total_owed_label'));
					var label_r1_2 = p.w.document.createElement('label');
					row1.appendChild( label_r1_2 );
					label_r1_2.setAttribute('value',mbts.total_owed());
				var row2 = p.w.document.createElement('row');
				rows.appendChild( row2 );
					var label_r2_1 = p.w.document.createElement('label');
					row2.appendChild( label_r2_1 );
					label_r2_1.setAttribute('value',getString('mbts_total_paid_label'));
					var label_r2_2 = p.w.document.createElement('label');
					row2.appendChild( label_r2_2 );
					label_r2_2.setAttribute('value',mbts.total_paid());
				var row3 = p.w.document.createElement('row');
				rows.appendChild( row3 );
					var label_r3_1 = p.w.document.createElement('label');
					row3.appendChild( label_r3_1 );
					label_r3_1.setAttribute('value',getString('mbts_balance_owed_label'));
					label_r3_1.setAttribute('style','font-weight: bold');
					var label_r3_2 = p.w.document.createElement('label');
					row3.appendChild( label_r3_2 );
					label_r3_2.setAttribute('value',mbts.balance_owed());
					label_r3_2.setAttribute('style','font-weight: bold');

		return grid;
	}

	var obj_string ='mbts';

	setTimeout(
		function() {
			//p.list_box.clear_rows();

			for (var i = 0; i < bills.length; i++) {

				var mbts = bills[i];

				var cols = [];

				for (var j = 0; j < p.patron_bills_cols.length; j++) {
					var hash = p.patron_bills_cols[j];
					sdump('D_PATRON_BILLS','Considering ' + js2JSON(hash) + '\n');
					var listcell = p.w.document.createElement('listcell');
					listcell.setAttribute('pack','start');
					listcell.setAttribute('align','start');
					listcell.setAttribute('style','border-left: black solid thin');
					var col = '';
					if (hash.fm_field_render) {

						var obj = 'mbts';
						switch( hash.fm_class ) {
							case 'mvr' : obj_string = 'mvr'; break;
						}
						var cmd = parse_render_string( obj_string, hash.fm_field_render );
						sdump('D_PATRON_BILLS','cmd = ' + cmd + '\n');
						try {
							col = eval( cmd );
							sdump('D_PATRON_BILLS','eval = ' + col + '\n');
						} catch(E) {
							sdump('D_ERROR',E + '\n');
						}
						if (typeof(col) == 'string') {
							listcell.setAttribute('label',col);
						} else {
							listcell.appendChild( col );
						}
					}
					if (hash.render_xul) {
						var xul = p.w.document.createElement( hash.render_xul );
						listcell.appendChild( xul );
						if (hash.render_xul == 'checkbox') xul.setAttribute('checked', 'true');
					}
					cols.push( listcell );
				}

				var listitem = p.list_box.add_row( 
					cols, { 
						'record_id' : mbts.id(),
						'balance_owed' : mbts.balance_owed()
					} 
				); 
				if (p.list_box.apply_to_each_listitem) {
					p.list_box.apply_to_each_listitem( i, listitem );
				}
			}
		}, 0
	);
}
