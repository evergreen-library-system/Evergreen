dump('entering patron/util.js\n');

if (typeof patron == 'undefined') var patron = {};
patron.util = {};

patron.util.EXPORT_OK	= [ 
	'columns', 'std_map_row_to_column', 'retrieve_au_by_id'
];
patron.util.EXPORT_TAGS	= { ':all' : patron.util.EXPORT_OK };

patron.util.columns = function(modify) {
	
	JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});

	function getString(s) { return data.entities[s]; }

	var c = [];
	for (var i = 0; i < c.length; i++) {
		if (modify[ c[i].id ]) {
			for (var j in modify[ c[i].id ]) {
				c[i][j] = modify[ c[i].id ][j];
			}
		}
	}
	return c;
}

patron.util.std_map_row_to_column = function() {
	return function(row,col) {
		// row contains { 'my' : { 'acp' : {}, 'patron' : {}, 'mvr' : {} } }
		// col contains one of the objects listed above in columns
		
		var obj = {}; obj.OpenILS = {}; 
		JSAN.use('util.error'); obj.error = new util.error();
		JSAN.use('OpenILS.data'); obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'});

		var my = row.my;
		var value;
		try { 
			value = eval( col.render );
		} catch(E) {
			obj.error.sdump('D_ERROR','map_row_to_column: ' + E);
			value = '???';
		}
		return value;
	}
}

patron.util.retrieve_au_by_id = function(session, id) {
}

dump('exiting patron/util.js\n');
