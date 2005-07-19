sdump('D_TRACE','Loading patron_bills.js\n');

function patron_bills_init(p) {
	sdump('D_PATRON_BILLS',"TESTING: patron_bills.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	p.patron_bills_cols = [
	/*
		{
			'id' : 'checkbox', 'label' : ' ', 'flex' : 0, 'render_xul' : 'checkbox'
		},
	*/
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

	p.list_box = list_box_init( { 'w' : p.w, 'node' : p.node, 'cols' : p.patron_bills_cols, 'debug' : p.app } );


	p.add_patron_bills = function (bills) {
		sdump('D_PATRON_BILLS','p.add_patron_bills(' + bills + ')\n');
		return patron_bills_add_patron_bills(p,bills);
	}
	p.clear_patron_bills = p.list_box.clear_rows;

	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return p;
}

function list_box_init( p ) {
	var listbox = p.w.document.createElement('listbox');
	p.node.appendChild( listbox );
	listbox.setAttribute('flex','1');

		var listhead = p.w.document.createElement('listhead');
		listbox.appendChild( listhead );

		var listcols = p.w.document.createElement('listcols');
		listbox.appendChild( listcols );

			for (var i = 0; i < p.cols.length; i++ ) {

				var listheader = p.w.document.createElement('listheader');
				listhead.appendChild( listheader );
				listheader.setAttribute('label', p.cols[i].label);

				var listcol = p.w.document.createElement('listcol');
				listcols.appendChild( listcol );
				listcol.setAttribute('flex', p.cols[i].flex);
			}

	p.add_row = function (cols) {

		var listitem = p.w.document.createElement('listitem');
		listbox.appendChild( listitem );
		listitem.setAttribute('allowevents','true');
		var idx = 0;
		if (typeof(cols[0]) == 'string') {

			listitem.setAttribute('label',cols[0]);
			idx = 1;
		}
		for (var i = idx; i < cols.length; i++) {

			try {
				listitem.appendChild( cols[i] );
			} catch(E) {
				sdump('D_ERROR', cols[i] + '\n' + E + '\n');
			}
		}
	}

	p.clear_rows = function () {
		var nl = listbox.getElementsByTagName('listitem');
		for (var i = 0; i < nl.length; i++) {
			listbox.removeChild(nl[i]);
		}

	}

	return p;
}

function patron_bills_add_patron_bills(p, bills) {
	sdump('D_PATRON_BILLS',arg_dump(arguments,{1:true}));

	var obj_string ='mbts';

	for (var i = 0; i < bills.length; i++) {

		var mbts = bills[i];

		var cols = [];

		for (var j = 0; j < p.patron_bills_cols.length; j++) {
			var hash = p.patron_bills_cols[j];
			sdump('D_PATRON_BILLS','Considering ' + js2JSON(hash) + '\n');
			var listcell = p.w.document.createElement('listcell');
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
					sdump('D_ERROR',js2JSON(E) + '\n');
				}
				listcell.setAttribute('label',col);
			}
			if (hash.render_xul) {
				var xul = p.w.document.createElement( hash.render_xul );
				listcell.appendChild( xul );
			}
			if ( (j == 0) && (window.navigator.userAgent.match( /Firefox/ )) ) {
				cols.push( col );
			} else {
				cols.push( listcell );
			}
		}
		p.list_box.add_row( cols );
	}
}
