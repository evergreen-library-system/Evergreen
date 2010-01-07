dump('entering circ/util.js\n');

if (typeof circ == 'undefined') var circ = {};
circ.util = {};

circ.util.EXPORT_OK	= [ 
	'offline_checkout_columns', 
	'offline_checkin_columns', 
	'offline_renew_columns', 
	'offline_inhouse_use_columns', 
	'hold_columns', 'CHECKIN_VIA_BARCODE', 'std_map_row_to_column', 'hold_capture_via_copy_barcode'
];
circ.util.EXPORT_TAGS	= { ':all' : circ.util.EXPORT_OK };

circ.util.offline_checkout_columns = function(modify,params) {
	
	var c = [
		{ 
			'id' : 'timestamp', 
			'label' : 'Timestamp', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : 'my.timestamp' 
		},
		{ 
			'id' : 'checkout_time', 
			'label' : 'Check Out Time', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : 'my.checkout_time' 
		},
		{ 
			'id' : 'type', 
			'label' : 'Transaction Type', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : 'my.type' 
		},
		{
			'id' : 'noncat',
			'label' : 'Non-Cataloged?',
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : 'my.noncat'
		},
		{
			'id' : 'noncat_type',
			'label' : 'Non-Cat Type ID',
			'flex' : 1, 'primary' : false, 'hidden' : true,
			'render' : 'my.noncat_type'
		},
		{
			'id' : 'noncat_count',
			'label' : 'Count',
			'flex' : 1, 'primary' : false, 'hidden' : false,
			'render' : 'my.noncat_count'
		},
		{ 
			'id' : 'patron_barcode', 
			'label' : 'Patron Barcode', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : 'my.patron_barcode' 
		},
		{ 
			'id' : 'barcode', 
			'label' : 'Item Barcode', 
			'flex' : 2, 'primary' : true, 'hidden' : false, 
			'render' : 'my.barcode' 
		},
		{ 
			'id' : 'due_date', 
			'label' : 'Due Date', 
			'flex' : 1, 'primary' : false, 'hidden' : false, 
			'render' : 'my.due_date' 
		},
	];
	if (modify) for (var i = 0; i < c.length; i++) {
		if (modify[ c[i].id ]) {
			for (var j in modify[ c[i].id ]) {
				c[i][j] = modify[ c[i].id ][j];
			}
		}
	}
	if (params) {
		if (params.just_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < params.just_these.length; i++) {
				var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
				new_c.push( function(y){ return y; }( x ) );
			}
			return new_c;
		}
	}
	return c;
}

circ.util.offline_checkin_columns = function(modify,params) {
	
	var c = [
		{ 
			'id' : 'timestamp', 
			'label' : 'Timestamp', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : 'my.timestamp' 
		},
		{ 
			'id' : 'backdate', 
			'label' : 'Back Date', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : 'my.backdate' 
		},
		{ 
			'id' : 'type', 
			'label' : 'Transaction Type', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : 'my.type' 
		},
		{ 
			'id' : 'barcode', 
			'label' : 'Item Barcode', 
			'flex' : 2, 'primary' : true, 'hidden' : false, 
			'render' : 'my.barcode' 
		},
	];
	if (modify) for (var i = 0; i < c.length; i++) {
		if (modify[ c[i].id ]) {
			for (var j in modify[ c[i].id ]) {
				c[i][j] = modify[ c[i].id ][j];
			}
		}
	}
	if (params) {
		if (params.just_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < params.just_these.length; i++) {
				var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
				new_c.push( function(y){ return y; }( x ) );
			}
			return new_c;
		}
	}
	return c;
}

circ.util.offline_renew_columns = function(modify,params) {
	
	var c = [
		{ 
			'id' : 'timestamp', 
			'label' : 'Timestamp', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : 'my.timestamp' 
		},
		{ 
			'id' : 'checkout_time', 
			'label' : 'Check Out Time', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : 'my.checkout_time' 
		},
		{ 
			'id' : 'type', 
			'label' : 'Transaction Type', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : 'my.type' 
		},
		{ 
			'id' : 'patron_barcode', 
			'label' : 'Patron Barcode', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : 'my.patron_barcode' 
		},
		{ 
			'id' : 'barcode', 
			'label' : 'Item Barcode', 
			'flex' : 2, 'primary' : true, 'hidden' : false, 
			'render' : 'my.barcode' 
		},
		{ 
			'id' : 'due_date', 
			'label' : 'Due Date', 
			'flex' : 1, 'primary' : false, 'hidden' : false, 
			'render' : 'my.due_date' 
		},
	];
	if (modify) for (var i = 0; i < c.length; i++) {
		if (modify[ c[i].id ]) {
			for (var j in modify[ c[i].id ]) {
				c[i][j] = modify[ c[i].id ][j];
			}
		}
	}
	if (params) {
		if (params.just_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < params.just_these.length; i++) {
				var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
				new_c.push( function(y){ return y; }( x ) );
			}
			return new_c;
		}
	}
	return c;
}

circ.util.offline_inhouse_use_columns = function(modify,params) {
	
	var c = [
		{ 
			'id' : 'timestamp', 
			'label' : 'Timestamp', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : 'my.timestamp' 
		},
		{ 
			'id' : 'use_time', 
			'label' : 'Use Time', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : 'my.use_time' 
		},
		{ 
			'id' : 'type', 
			'label' : 'Transaction Type', 
			'flex' : 1, 'primary' : false, 'hidden' : true, 
			'render' : 'my.type' 
		},
		{
			'id' : 'count',
			'label' : 'Count',
			'flex' : 1, 'primary' : false, 'hidden' : false,
			'render' : 'my.count'
		},
		{ 
			'id' : 'barcode', 
			'label' : 'Item Barcode', 
			'flex' : 2, 'primary' : true, 'hidden' : false, 
			'render' : 'my.barcode' 
		},
	];
	if (modify) for (var i = 0; i < c.length; i++) {
		if (modify[ c[i].id ]) {
			for (var j in modify[ c[i].id ]) {
				c[i][j] = modify[ c[i].id ][j];
			}
		}
	}
	if (params) {
		if (params.just_these) {
			JSAN.use('util.functional');
			var new_c = [];
			for (var i = 0; i < params.just_these.length; i++) {
				var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
				new_c.push( function(y){ return y; }( x ) );
			}
			return new_c;
		}
	}
	return c;
}



circ.util.std_map_row_to_column = function(error_value) {
	return function(row,col) {
		// row contains { 'my' : { 'barcode' : xxx, 'duedate' : xxx } }
		// col contains one of the objects listed above in columns

		var my = row.my;
		var value;
		try {
			value = eval( col.render );
			if (typeof value == 'undefined') value = '';

		} catch(E) {
			JSAN.use('util.error'); var error = new util.error();
			error.sdump('D_WARN','map_row_to_column: ' + E);
			if (error_value) value = error_value; else value = '???';
		}
		return value;
	}
}


dump('exiting circ/util.js\n');
