dump('entering circ.copy_status.js\n');

if (typeof circ == 'undefined') circ = {};
circ.copy_status = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('util.date');
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
}

circ.copy_status.prototype = {
	'selection_list' : [],

	'init' : function( params ) {

		var obj = this;

		obj.session = params['session'];

		JSAN.use('circ.util');
		var columns = circ.util.columns( 
			{ 
				'barcode' : { 'hidden' : false },
				'title' : { 'hidden' : false },
				'location' : { 'hidden' : false },
				'call_number' : { 'hidden' : false },
				'status' : { 'hidden' : false },
			} 
		);

		JSAN.use('util.list'); obj.list = new util.list('copy_status_list');
		obj.list.init(
			{
				'columns' : columns,
				'map_row_to_column' : circ.util.std_map_row_to_column(),
				'on_select' : function(ev) {
					try {
						JSAN.use('util.functional');
						var sel = obj.list.retrieve_selection();
						obj.selection_list = util.functional.map_list(
							sel,
							function(o) { return JSON2js(o.getAttribute('retrieve_id')); }
						);
						obj.error.sdump('D_TRACE','circ/copy_status: selection list = ' + js2JSON(obj.selection_list) );
						if (obj.selection_list.length == 0) {
							obj.controller.view.sel_checkin.disabled = true;
							obj.controller.view.sel_edit.disabled = true;
							obj.controller.view.sel_opac.disabled = true;
							obj.controller.view.sel_patron.disabled = true;
							obj.controller.view.sel_bucket.disabled = true;
						} else {
							obj.controller.view.sel_checkin.disabled = false;
							obj.controller.view.sel_edit.disabled = false;
							obj.controller.view.sel_opac.disabled = false;
							obj.controller.view.sel_patron.disabled = false;
							obj.controller.view.sel_bucket.disabled = false;
						}
					} catch(E) {
						alert('FIXME: ' + E);
					}
				},
			}
		);
		
		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				'control_map' : {
					'sel_checkin' : [
						['command'],
						function() {
                                                        JSAN.use('circ.util');
                                                        for (var i = 0; i < obj.selection_list.length; i++) {
                                                                var barcode = obj.selection_list[i][1];
                                                                var checkin = circ.util.checkin_via_barcode(
                                                                        obj.session, barcode
                                                                );
                                                        }
						}
					],
					'sel_edit' : [
						['command'],
						function() {
							try {
								obj.spawn_copy_editor();
							} catch(E) {
								alert(E);
							}
						}
					],
					'sel_opac' : [
						['command'],
						function() {
							alert('Not Yet Implemented');
						}
					],
					'sel_patron' : [
						['command'],
						function() {
							alert('Not Yet Implemented');
						}
					],
					'sel_bucket' : [
						['command'],
						function() {
							alert('Not Yet Implemented');
						}
					],
					'copy_status_barcode_entry_textbox' : [
						['keypress'],
						function(ev) {
							if (ev.keyCode && ev.keyCode == 13) {
								obj.copy_status();
							}
						}
					],
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_copy_status_submit_barcode' : [
						['command'],
						function() {
							obj.copy_status();
						}
					],
					'cmd_copy_status_print' : [
						['command'],
						function() {
							dump( js2JSON( obj.list.dump() ) );
							alert( js2JSON( obj.list.dump() ) );
						}
					],
					'cmd_copy_status_reprint' : [
						['command'],
						function() {
						}
					],
					'cmd_copy_status_done' : [
						['command'],
						function() {
						}
					],
				}
			}
		);
		this.controller.render();
		this.controller.view.copy_status_barcode_entry_textbox.focus();

	},

	'copy_status' : function() {
		var obj = this;
		try {
			var barcode = obj.controller.view.copy_status_barcode_entry_textbox.value;
			JSAN.use('circ.util');
			var copy = obj.network.simple_request( 'FM_ACP_RETRIEVE_VIA_BARCODE', [ barcode ]);
			if (copy == null) {
				throw('COPY NOT FOUND');
			} else {
				obj.list.append(
					{
						'retrieve_id' : js2JSON( [ copy.id(), barcode ] ),
						'row' : {
							'my' : {
								'mvr' : obj.network.simple_request('MODS_SLIM_RECORD_RETRIEVE_VIA_COPY', [ copy.id() ]),
								'acp' : copy,
							}
						}
					}
				);
			}
			obj.controller.view.copy_status_barcode_entry_textbox.value = '';
			obj.controller.view.copy_status_barcode_entry_textbox.focus();
		} catch(E) {
			alert('FIXME: need special alert and error handling\n'
				+ js2JSON(E));
			obj.controller.view.copy_status_barcode_entry_textbox.select();
			obj.controller.view.copy_status_barcode_entry_textbox.focus();
		}

	},
	
	'spawn_copy_editor' : function() {

		/* FIXME -  a lot of redundant calls here */

		var obj = this;

		JSAN.use('util.widgets'); JSAN.use('util.functional');

		var list = obj.selection_list;

		list = util.functional.map_list(
			list,
			function (obj) {
				return obj[0];
			}
		);

		var copies = util.functional.map_list(
			list,
			function (acp_id) {
				return obj.network.simple_request('FM_ACP_RETRIEVE',[acp_id]);
			}
		);

		var edit = 0;
		try {
			edit = obj.network.request(
				api.PERM_MULTI_ORG_CHECK.app,
				api.PERM_MULTI_ORG_CHECK.method,
				[ 
					obj.session, 
					obj.data.list.au[0].id(), 
					util.functional.map_list(
						copies,
						function (obj) {
							return obj.network.simple_request('FM_ACN_RETRIEVE',[obj.call_number()]).owning_lib();
						}
					),
					[ 'UPDATE_COPY', 'UPDATE_BATCH_COPY' ]
				]
			).length == 0 ? 1 : 0;
		} catch(E) {
			obj.error.sdump('D_ERROR','batch permission check: ' + E);
		}

		var title = list.length == 1 ? 'Copy' : 'Copies';

		JSAN.use('util.window'); var win = new util.window();
		obj.data.temp = '';
		obj.data.stash('temp');
		var w = win.open(
			window.xulG.url_prefix(urls.XUL_COPY_EDITOR)
				+'?session='+window.escape(obj.session)
				+'&copy_ids='+window.escape(js2JSON(list))
				+'&edit='+edit,
			title,
			'chrome,modal,resizable'
		);
		/* FIXME -- need to unique the temp space, and not rely on modalness of window */
		obj.data.stash_retrieve();
		copies = JSON2js( obj.data.temp );
		obj.error.sdump('D_CAT','in circ/copy_status, copy editor, copies =\n<<' + copies + '>>');
		if (edit=='1' && copies!='' && typeof copies != 'undefined') {
			try {
				var r = obj.network.request(
					api.FM_ACP_FLESHED_BATCH_UPDATE.app,
					api.FM_ACP_FLESHED_BATCH_UPDATE.method,
					[ obj.session, copies ]
				);
				/* FIXME -- revisit the return value here */
			} catch(E) {
				alert('copy update error: ' + js2JSON(E));
			}
		}
	},

}

dump('exiting circ.copy_status.js\n');
