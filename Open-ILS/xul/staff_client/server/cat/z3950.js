dump('entering cat.z3950.js\n');

if (typeof cat == 'undefined') cat = {};
cat.z3950 = function (params) {
	try {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		JSAN.use('util.error'); this.error = new util.error();
		JSAN.use('util.network'); this.network = new util.network();
	} catch(E) {
		dump('cat.z3950: ' + E + '\n');
	}
}

cat.z3950.prototype = {

	'init' : function( params ) {

		try {
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			JSAN.use('util.widgets');

			var obj = this;

			obj.session = params['session'];

			JSAN.use('circ.util');
			var columns = circ.util.columns(
				{
					'tcn' : { 'hidden' : false },
					'isbn' : { 'hidden' : false },
					'title' : { 'hidden' : false, 'flex' : '1' },
					'author' : { 'hidden' : false },
					'edition' : { 'hidden' : false },
					'pubdate' : { 'hidden' : false },
					'publisher' : { 'hidden' : false },
				}
			);

			JSAN.use('util.list'); obj.list = new util.list('results');
			obj.list.init(
				{
					'columns' : columns,
					'map_row_to_column' : circ.util.std_map_row_to_column(),
					'on_select' : function(ev) {
						JSAN.use('util.functional');
						var sel = obj.list.retrieve_selection();
						var list = util.functional.map_list(
							sel,
							function(o) { return o.getAttribute('retrieve_id'); }
						);
						obj.sdump('D_TRACE','cat/z3950: selection list = ' + js2JSON(list) );
					},
				}
			);


			document.getAnonymousNodes(document.getElementById('c1'))[0].addEventListener(
				'mouseup',
				function() {
					util.widgets.click(
						document.getAnonymousNodes(document.getElementById('c2'))[0]
					);
				}, false
			);
			document.getAnonymousNodes(document.getElementById('c2'))[0].addEventListener(
				'mouseup',
				function() {
					util.widgets.click(
						document.getAnonymousNodes(document.getElementById('c1'))[0]
					);
				}, false
			);

			JSAN.use('util.controller'); obj.controller = new util.controller();
			obj.controller.init(
				{
					control_map : {
						'cmd_broken' : [
							['command'],
							function() { alert('Not Yet Implemented'); }
						],
						'result_message' : [['render'],function(e){return function(){};}],
						'server' : [['render'],function(e){return function(){};}],
						'database' : [['render'],function(e){return function(){};}],
						'port' : [['render'],function(e){return function(){};}],
						'username' : [['render'],function(e){return function(){};}],
						'password' : [['render'],function(e){return function(){};}],
						'asc_id' : [
							['render'],
							function(e){
								return function(){
									e.addEventListener(
										'keypress',
										function(ev) {
											if (ev.keyCode && ev.keyCode == 13) {
												obj.asc_search_async();
											}
										},
										false
									);
								};
							}
						],
						'import' : [
							['command'],
							function() {
							},
						],
						'asc_search' : [
							['command'],
							function() {
								obj.asc_search_async();
							},
						],
						'raw_string' : [
							['render'],
							function(e){
								return function(){
									e.addEventListener(
										'keypress',
										function(ev) {
											if (ev.keyCode && ev.keyCode == 13) {
												obj.raw_search_async();
											}
										},
										false
									);
								};
							}
						],
						'raw_search' : [
							['command'],
							function() {
								obj.raw_search_async();
							},
						],
						'menu_placeholder' : [
							['render'],
							function(e) {
								return function() {
									util.widgets.remove_children(e);
									var ml = util.widgets.make_menulist( [
										[ 'System Defaults', 0 ],
										[ 'Custom', 1 ],
									] );
									ml.setAttribute('flex','1');
									e.appendChild(ml);
									/* An experiment with virtual events.  I could just use a named function
									   instead of defining one inline, and then call that once to set things
									   up, and let the event handler call it the rest of the time. */
									ml.addEventListener(
										'set_server_details',
										function(ev) { 
											/* FIXME - get these values from server */
											switch(ev.target.value) {
												case 0: case '0':
													obj.controller.view.server.value = 'zcat.oclc.org';
													obj.controller.view.server.disabled = true;
													obj.controller.view.database.value = 'OLUCWorldCat';
													obj.controller.view.database.disabled = true;
													obj.controller.view.port.value = '210';
													obj.controller.view.port.disabled = true;
													obj.controller.view.username.value = '****';
													obj.controller.view.username.disabled = true;
													obj.controller.view.password.value = '****';
													obj.controller.view.password.disabled = true;
													obj.controller.view.raw_string.value = 'DISABLED';
													obj.controller.view.raw_string.disabled = true;
													obj.controller.view.raw_search.disabled = true;
													obj.controller.view.asc_id.value = '';
													obj.controller.view.asc_id.disabled = false;
													obj.controller.view.asc_search.disabled = false;
												break;
												default:
													obj.controller.view.server.disabled = false;
													obj.controller.view.database.disabled = false;
													obj.controller.view.server.disabled = false;
													obj.controller.view.port.disabled = false;
													obj.controller.view.username.value = '';
													obj.controller.view.username.disabled = false;
													obj.controller.view.password.value = '';
													obj.controller.view.password.disabled = false;
													obj.controller.view.raw_string.value = '';
													obj.controller.view.raw_string.disabled = false;
													obj.controller.view.raw_search.disabled = false;
													obj.controller.view.asc_id.value = 'DISABLED';
													obj.controller.view.asc_id.disabled = true;
													obj.controller.view.asc_search.disabled = true;
												break;
											}
										},
										false
									);
									ml.addEventListener(
										'command',
										function(ev) { util.widgets.dispatch('set_server_details', ev.target); },
										false
									);
									setTimeout( function() { util.widgets.dispatch('set_server_details',ml); }, 0 );
								}
							}
						],
					}
				}
			);

			obj.controller.render();

		} catch(E) {
			this.error.sdump('D_ERROR','cat.z3950.init: ' + E + '\n');
		}
	},

	'store_disable_search_buttons' : function() {
		var obj = this;
		JSAN.use('util.widgets');
		util.widgets.store_disable(
			obj.controller.view.asc_search,
			obj.controller.view.raw_search
		);
		util.widgets.disable(
			obj.controller.view.asc_search,
			obj.controller.view.raw_search
		);
	},

	'restore_enable_search_buttons' : function() {
		var obj = this;
		JSAN.use('util.widgets');
		util.widgets.restore_disable(
			obj.controller.view.asc_search,
			obj.controller.view.raw_search
		);
	},

	'asc_search_async' : function() {
		try {
			var obj = this;
			var search = obj.controller.view.asc_id.value;
			obj.error.sdump('D_TRACE','search string: ' + search);
			JSAN.use('util.widgets');
			util.widgets.remove_children( obj.controller.view.result_message );
			obj.controller.view.result_message.appendChild(
				document.createTextNode( 'Searching...' )
			);
			obj.store_disable_search_buttons();
			obj.network.simple_request(
				'FM_BRN_RETRIEVE_VIA_Z3950_TCN',
				[ obj.session, search ],
				function(req) {
					obj.handle_results(req.getResultObject())
					obj.restore_enable_search_buttons();
				}
			);
		} catch(E) {
			this.error.sdump('D_ERROR',E);
			alert(E);
		}

	},

	'raw_search_async' : function() {
		try {
			var obj = this;
			var search = obj.controller.view.raw_string.value;
			obj.error.sdump('D_TRACE','search string: ' + search);
			JSAN.use('util.widgets');
			util.widgets.remove_children( obj.controller.view.result_message );
			obj.controller.view.result_message.appendChild(
				document.createTextNode( 'Searching...' )
			);
			obj.store_disable_search_buttons();
			obj.network.simple_request(
				'FM_BRN_RETRIEVE_VIA_Z3950_RAW',
				[ 
					obj.session, 
					obj.controller.view.server.value, 
					obj.controller.view.port.value, 
					obj.controller.view.database.value, 
					search, 
					obj.controller.view.username.value, 
					obj.controller.view.password.value 
				],
				function(req) {
					obj.handle_results(req.getResultObject())
					obj.restore_enable_search_buttons();
				}
			);
		} catch(E) {
			this.error.sdump('D_ERROR',E);
			alert(E);
		}
	},

	'handle_results' : function(results) {
		var obj = this;
		JSAN.use('util.widgets');
		util.widgets.remove_children( obj.controller.view.result_message );
		if (results == null) {
			obj.controller.view.result_message.appendChild(
				document.createTextNode( 'Server Error: ' + api.FM_BRN_RETRIEVE_VIA_Z3950_TCN.method + ' returned null' )
			);
			return;
		}
		if (results.count) {
			obj.controller.view.result_message.appendChild(
				document.createTextNode( results.count + (results.count == 1 ? ' result ' : ' results ') + 'found. ' )
			);
		}
		if (results.records) {
			obj.controller.view.result_message.appendChild(
				document.createTextNode( results.records.length + (results.records.length == 1 ? ' result' : ' results') + ' retrieved. ')
			);
			obj.results = results;
			obj.list.clear(); 
			for (var i = 0; i < obj.results.records.length; i++) {
				obj.list.append(
					{
						'retrieve_id' : i,
						'row' : {
							'my' : {
								'mvr' : function(a){return a;}(obj.results.records[i].mvr),
							}
						}
					}
				);
			}
		} else {
			obj.controller.view.result_message.appendChild(
				document.createTextNode( 'Too many results to retrieve. ')
			);
		}
	},

}

dump('exiting cat.z3950.js\n');
