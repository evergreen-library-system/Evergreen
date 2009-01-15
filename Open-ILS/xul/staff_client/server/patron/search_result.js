dump('entering patron/search_result.js\n');

function $(id) { return document.getElementById(id); }

if (typeof patron == 'undefined') patron = {};
patron.search_result = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	this.w = window;
}

patron.search_result.prototype = {

	'result_cap' : 50,

	'init' : function( params ) {

		var obj = this;

		obj.query = params['query'];

		JSAN.use('OpenILS.data'); this.OpenILS = {}; 
		obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'});

		JSAN.use('util.list'); obj.list = new util.list('patron_list');

		JSAN.use('patron.util');
		var columns = patron.util.columns(
			{
				/* 'active' : { 'hidden' : 'false' }, */
				'barred' : { 'hidden' : 'false' },
				'family_name' : { 'hidden' : 'false' },
				'first_given_name' : { 'hidden' : 'false' },
				'second_given_name' : { 'hidden' : 'false' },
				'dob' : { 'hidden' : 'false' }
			},
			{
				'except_these' : [
					'barcode',
				]
			}
		);
		obj.list.init(
			{
				'columns' : columns,
				'map_row_to_columns' : patron.util.std_map_row_to_columns(),
				'retrieve_row' : function(params) {
					var id = params.retrieve_id;
					var au_obj = patron.util.retrieve_au_via_id( ses(), id,
						function(req) {
							try {
								var row = params.row;
								if (typeof row.my == 'undefined') row.my = {};
								row.my.au = req.getResultObject();
								if (typeof params.on_retrieve == 'function') {
									params.on_retrieve(row);
								} else {
									alert($("patronStrings").getFormattedString('staff.patron.search_result.init.typeof_params', [typeof params.on_retrieve]));
								}
							} catch(E) {
								alert('error: ' + E);
							}
						}
					);
				},
				'on_select' : function(ev) {
					JSAN.use('util.functional');
					var sel = obj.list.retrieve_selection();
					var list = util.functional.map_list(
						sel,
						function(o) { return o.getAttribute('retrieve_id'); }
					);
					obj.controller.view.cmd_sel_clip.setAttribute('disabled', list.length < 1 );
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
						function() { alert($("commonStrings").getString('common.unimplemented')); }
					],
					'cmd_search_print' : [
						['command'],
						function() {
                            try {
								var p = { 
									'template' : 'patron'
								};
								obj.list.print( p );
                            } catch(E) {
								obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.search_result.init.search_print'),E);
                            }
						}
					],
					'cmd_sel_clip' : [
						['command'],
						function() {
							try {
								obj.list.clipboard();
							} catch(E) {
								obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.search_result.init.search_clipboard'),E);
							}
						}
					],
					'cmd_save_cols' : [
						['command'],
						function() {
							try {
								obj.list.save_columns();
							} catch(E) {
								obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.search_result.init.search_saving_columns'),E);
							}
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
		obj.search_term_count = 0;
		var inactive = false;
        var search_depth = 0;
		for (var i in query) {
			switch( i ) {
                case 'card':
					search_hash[ i ] = {};
					search_hash[ i ].value = query[i];
					search_hash[i].group = 3; 
					obj.search_term_count++;
				break;

				case 'phone': case 'ident': 
				
					search_hash[ i ] = {};
					search_hash[ i ].value = query[i];
					search_hash[i].group = 2; 
					obj.search_term_count++;
				break;

				case 'street1': case 'street2': case 'city': case 'state': case 'post_code': 
				
					search_hash[ i ] = {};
					search_hash[ i ].value = query[i];
					search_hash[i].group = 1; 
					obj.search_term_count++;
				break;

				case 'family_name': case 'first_given_name': case 'second_given_name': case 'email': case 'alias': case 'usrname':

					search_hash[ i ] = {};
					search_hash[ i ].value = query[i];
					search_hash[i].group = 0; 
					obj.search_term_count++;
				break;

				case 'inactive':
					if (query[i] == 'checked' || query[i] == 'true') inactive = true;
				break;

                case 'search_depth':
                    search_depth = function(a){return a;}(query[i]);
                break;
			}
		}
		try {
			var results = [];

			var params = [ ses(), search_hash, obj.result_cap + 1, [ 'family_name ASC', 'first_given_name ASC', 'second_given_name ASC', 'dob DESC' ] ];
			if (inactive) {
				params.push(1);
				if (document.getElementById('active')) {
					document.getElementById('active').setAttribute('hidden','false');
					document.getElementById('active').hidden = false;
				}
			} else {
                params.push(0);
            }
            params.push(search_depth);
			if (obj.search_term_count > 0) {
				//alert('search params = ' + obj.error.pretty_print( js2JSON( params ) ) );
				results = this.network.simple_request( 'FM_AU_IDS_RETRIEVE_VIA_HASH', params );
				if ( (results == null) || (typeof results.ilsevent != 'undefined') ) throw(results);
				if (results.length == 0) {
					alert($("patronStrings").getString('staff.patron.search_result.search.no_patrons_found'));
					return;
				}
				if (results.length == obj.result_cap+1) {
					results.pop();
					alert($("patronStrings").getFormattedString('staff.patron.search_result.search.capped_results', [obj.result_cap]));
				}
			} else {
				alert($("patronStrings").getString('staff.patron.search_result.search.enter_search_terms'));
				return;
			}

            obj.list.clear();
			//this.list.append( { 'retrieve_id' : results[i], 'row' : {} } );
			var funcs = [];

				function gen_func(r) {
					return function() {
						obj.list.append( { 'retrieve_id' : r, 'row' : {}, 'to_bottom' : true, 'no_auto_select' : true } );
					}
				}

			for (var i = 0; i < results.length; i++) {
				funcs.push( gen_func(results[i]) );
			}
			JSAN.use('util.exec'); var exec = new util.exec(4);
			exec.chain( funcs );

		} catch(E) {
			this.error.standard_unexpected_error_alert('patron.search_result.search',E);
		}
	}

}

dump('exiting patron/search_result.js\n');
