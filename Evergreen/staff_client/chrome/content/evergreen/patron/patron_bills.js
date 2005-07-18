sdump('D_TRACE','Loading patron_bills.js\n');

function patron_bills_init(p) {
	sdump('D_PATRON_BILLS',"TESTING: patron_bills.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	p.patron_bills_cols = [
		{
			'id' : 'checkbox', 'label' : ' ', 'flex' : 0, 'render_xul' : 'checkbox'
		},
		{
			'id' : 'id', 'label' : getString('mbts_id_label'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mbts', 'fm_field_render' : '.id()'
		},
		{
			'id' : 'xact_start', 'label' : getString('mbts_xact_start_label'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mbts', 'fm_field_render' : '.xact_start().toString().substr(0,10);'
		},
		{
			'id' : 'xact_finish', 'label' : getString('mbts_xact_finish_label'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mbts', 'fm_field_render' : '.xact_finish().toString().substr(0,10);'
		},
		{
			'id' : 'total_owed', 'label' : getString('mbts_total_owed_label'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mbts', 'fm_field_render' : '.total_owed()'
		},
		{
			'id' : 'total_paid', 'label' : getString('mbts_total_paid_label'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mbts', 'fm_field_render' : '.total_paid()'
		},
		{
			'id' : 'balance_owed', 'label' : getString('mbts_balance_owed_label'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mbts', 'fm_field_render' : '.balance_owed()'
		},
		{
			'id' : 'current_pay', 'label' : getString('bills_current_payment_label'), 'flex' : 1, 'render_xul' : 'textbox'
		}
	];

	p.grid_list = grid_list_init( { 'w' : p.w, 'node' : p.node, 'cols' : p.patron_bills_cols, 'debug' : p.app } );
	p.add_patron_bills = function (bills) {
		sdump('D_PATRON_BILLS','p.add_patron_bills(' + bills + ')\n');
		return patron_bills_add_patron_bills(p,bills);
	}
	p.clear_patron_bills = p.grid_list.clear_grid;

	p.register_bill_context_builder = function (f) {
		sdump('D_PATRON_BILLS','p.register_context_builder(' + f + ')\n');
		p.grid_list.register_context_builder( f );
	}

	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return p;
}

function cols() {
	sdump('D_PATRON_BILLS',arg_dump(arguments,{1:true}));
	for (var i = 0; i < p.mbts_cols.length; i++) {
                var hash = p.mbts_cols[i];
                var obj_string = 'mbts';
                var cmd = parse_render_string( obj_string, hash.fm_field_render );
                var col = '';
                try {
                        col = eval( cmd );
                } catch(E) {
                        sdump('D_ERROR',js2JSON(E) + '\n');
                }
		var label = p.w.document.createElement('label');
		row.appendChild( label );
		label.setAttribute('value',col);
	}	
}

function patron_bills_add_patron_bills(p, bills) {
	sdump('D_PATRON_BILLS',arg_dump(arguments,{1:true}));
	// grid_columns: checkbox, line item, bill amount, payment

	var obj_string ='mbts';

	for (var i = 0; i < bills.length; i++) {

		var mbts = bills[i];

		var row = p.w.document.createElement('row');
		p.grid_list.add_rows( [ row ] );

		for (var j = 0; j < p.patron_bills_cols.length; i++) {
			var hash = p.patron_bills_cols[j];
			if (hash.fm_field_render) {
			}
		}
	}
}
