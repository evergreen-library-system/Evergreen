dump('entering patron/search_result.js\n');

if (typeof patron == 'undefined') patron = {};
patron.search_result = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	this.w = window;
}

patron.search_result.prototype = {

	'init' : function( params ) {

		var obj = this;

		obj.session = params['session'];
		obj.query = params['query'];

		JSAN.use('OpenILS.data'); this.OpenILS = {}; 
		obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'});

		JSAN.use('util.list'); obj.list = new util.list('patron_list');
		function getString(s) { return obj.OpenILS.data.entities[s]; }

		JSAN.use('patron.util');
		var columns = patron.util.columns(
			{
				'standing' : { 'hidden' : 'false' },
				'active' : { 'hidden' : 'false' },
				'family_name' : { 'hidden' : 'false' },
				'first_given_name' : { 'hidden' : 'false' },
				'second_given_name' : { 'hidden' : 'false' },
				'dob' : { 'hidden' : 'false' },
			}
		);
		obj.list.init(
			{
				'columns' : columns,
				'map_row_to_column' : patron.util.std_map_row_to_column(),
				'retrieve_row' : function(params) {
					var id = params.retrieve_id;
					var au_obj = patron.util.retrieve_au_via_id( obj.session, id );

					var row = params.row;
					if (typeof row.my == 'undefined') row.my = {};
					row.my.au = au_obj;
					if (typeof params.on_retrieve == 'function') {
						params.on_retrieve(row);
					}
					return row;
				},
				'on_select' : function(ev) {
					JSAN.use('util.functional');
					var sel = obj.list.retrieve_selection();
					var list = util.functional.map_list(
						sel,
						function(o) { return o.getAttribute('retrieve_id'); }
					);
					if (typeof obj.on_select == 'function') {
						obj.on_select(list);
					}
					if (typeof window.xulG == 'object' && typeof window.xulG.on_select == 'function') {
						obj.error.sdump('D_PATRON','patron.search_result: Calling external .on_select()\n');
						window.xulG.on_select(list);
					} else {
						obj.error.sdump('D_PATRON','patron.search_result: No external .on_select()\n');
					}
				}
			}
		);
		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				control_map : {
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_search_print' : [
						['command'],
						function() {
							dump( js2JSON( obj.list.dump() ) );
							alert( js2JSON( obj.list.dump() ) );
						}
					],
				}
			}
		);

		if (obj.query) obj.search(obj.query);
	},

	'search' : function(query) {
		var obj = this;
		var search_hash = {};
		for (var i in query) {
			switch( i ) {
				case 'phone': case 'ident': 
				
					search_hash[ i ] = {};
					search_hash[ i ].value = query[i];
					search_hash[i].group = 2; 
				break;

				case 'street1': case 'street2': case 'city': case 'state': case 'post_code': 
				
					search_hash[ i ] = {};
					search_hash[ i ].value = query[i];
					search_hash[i].group = 1; 
				break;

				case 'family_name': case 'first_given_name': case 'second_given_name': case 'email':

					search_hash[ i ] = {};
					search_hash[ i ].value = query[i];
					search_hash[i].group = 0; 
				break;
			}
		}
		try {
			var results = this.network.request(
				api.FM_AU_IDS_RETRIEVE_VIA_HASH.app,
				api.FM_AU_IDS_RETRIEVE_VIA_HASH.method,
				[ this.session, search_hash ]
			);
			//this.list.append( { 'retrieve_id' : results[i], 'row' : {} } );
			var funcs = [];

				function gen_func(r) {
					return function() {
						obj.list.append( { 'retrieve_id' : r, 'row' : {} } );
					}
				}

			for (var i = 0; i < results.length; i++) {
				funcs.push( gen_func(results[i]) );
			}
			JSAN.use('util.exec'); var exec = new util.exec();
			exec.chain( funcs );

		} catch(E) {
			this.error.sdump('D_ERROR','patron.search_result.search: ' + js2JSON(E));
			alert(E);
		}
	}

}

dump('exiting patron/search_result.js\n');
