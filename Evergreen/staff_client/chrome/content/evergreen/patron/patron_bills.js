sdump('D_TRACE','Loading patron_bills.js\n');

function patron_bills_init(p) {
	sdump('D_PATRON_BILLS',"TESTING: patron_bills.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	p.patron_bills_cols = [
		{
			'id' : 'xact_dates', 'label' : getString('bills_xact_dates_label'), 'flex' : 0,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mbts', 
			'fm_field_render' : 'xact_dates_box($$)'
		},
		{
			'id' : 'notes', 'label' : getString('mbts_xact_type_label'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'mbts',
			'fm_field_render' : '.xact_type()'
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
	listbox.setAttribute('seltype','multiple');

		var listhead = p.w.document.createElement('listhead');
		listbox.appendChild( listhead );

		var listcols = p.w.document.createElement('listcols');
		listbox.appendChild( listcols );

			if (window.navigator.userAgent.match( /Firefox/ ))  {
				var listheader = p.w.document.createElement('listheader');
				listhead.appendChild( listheader );
				listheader.setAttribute('label', '');
				var listcol = p.w.document.createElement('listcol');
				listcols.appendChild( listcol );
			}

			for (var i = 0; i < p.cols.length; i++ ) {

				var listheader = p.w.document.createElement('listheader');
				listhead.appendChild( listheader );
				listheader.setAttribute('label', p.cols[i].label);

				var listcol = p.w.document.createElement('listcol');
				listcols.appendChild( listcol );
				listcol.setAttribute('flex', p.cols[i].flex);
			}

	p.add_row = function (cols, params) {

		var listitem = p.w.document.createElement('listitem');
		listbox.appendChild( listitem );
		listitem.setAttribute('allowevents','true');
		listitem.setAttribute('style','border-bottom: black solid thin');
		for (var i in params) {
			listitem.setAttribute( i, params[i] );
		}

		if (window.navigator.userAgent.match( /Firefox/ ))  {
			listitem.setAttribute('label','');
		}

		for (var i = 0; i < cols.length; i++) {

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
			}
			cols.push( listcell );
		}
		p.list_box.add_row( cols, { 'record_id' : mbts.id() } );
	}
}
