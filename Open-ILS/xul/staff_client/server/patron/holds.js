dump('entering patron.holds.js\n');

if (typeof patron == 'undefined') patron = {};
patron.holds = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	this.OpenILS = {}; JSAN.use('OpenILS.data'); this.OpenILS.data = new OpenILS.data(); this.OpenILS.data.init({'via':'stash'});
}

patron.holds.prototype = {

	'init' : function( params ) {

		var obj = this;

		obj.session = params['session'];
		obj.patron_id = params['patron_id'];

		JSAN.use('circ.util');
		var columns = circ.util.hold_columns( 
			{ 
				'title' : { 'hidden' : false, 'flex' : '3' },
				'request_time' : { 'hidden' : false },
				'pickup_lib_shortname' : { 'hidden' : false },
				'hold_type' : { 'hidden' : false },
				'current_copy' : { 'hidden' : false },
				'capture_time' : { 'hidden' : false },
			} 
		);

		JSAN.use('util.list'); obj.list = new util.list('holds_list');
		obj.list.init(
			{
				'columns' : columns,
				'map_row_to_column' : circ.util.std_map_row_to_column(),
                                'retrieve_row' : function(params) {
                                        var row = params.row;
					try {
						switch(row.my.ahr.hold_type()) {
							case 'M' :
								row.my.mvr = obj.network.request(
									api.MODS_SLIM_METARECORD_RETRIEVE.app,
									api.MODS_SLIM_METARECORD_RETRIEVE.method,
									[ row.my.ahr.target() ]
								);
							break;
							default:
								row.my.mvr = obj.network.request(
									api.MODS_SLIM_RECORD_RETRIEVE.app,
									api.MODS_SLIM_RECORD_RETRIEVE.method,
									[ row.my.ahr.target() ]
								);
								row.my.acp = obj.network.simple_request(
									'FM_ACP_RETRIEVE', [ row.my.ahr.current_copy() ]
								);
							break;
						}
					} catch(E) {
						obj.error.sdump('D_ERROR','retrieve_row: ' + E );
					}
					if (typeof params.on_retrieve == 'function') {
						params.on_retrieve(row);
					}
                                        return row;
				}
			}
		);
		
		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				'control_map' : {
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_holds_print' : [
						['command'],
						function() {
							dump( js2JSON( obj.list.dump() ) + '\n');
							alert( js2JSON( obj.list.dump() ) + '\n');
						}
					],
					'cmd_holds_edit' : [
						['command'],
						function() {
						}
					],
					'cmd_holds_cancel' : [
						['command'],
						function() {
						}
					],
					'cmd_show_catalog' : [
						['command'],
						function() {
						}
					],
				}
			}
		);

		obj.retrieve();

	},

	'retrieve' : function() {
		var obj = this;
		if (window.xulG && window.xulG.holds) {
			obj.holds = window.xulG.holds;
		} else {
			obj.holds = obj.network.request(
				api.FM_AHR_RETRIEVE.app,
				api.FM_AHR_RETRIEVE.method,
				[ obj.session, obj.patron_id ]
			);
				
		}

		function gen_list_append(hold) {
			return function() {
				obj.list.append(
					{
						'row' : {
							'my' : {
								'ahr' : hold,
							}
						}
					}
				);
			};
		}

		JSAN.use('util.exec'); var exec = new util.exec();
		var rows = [];
		for (var i in obj.holds) {
			rows.push( gen_list_append(obj.holds[i]) );
		}
		exec.chain( rows );
	},
}

dump('exiting patron.holds.js\n');
