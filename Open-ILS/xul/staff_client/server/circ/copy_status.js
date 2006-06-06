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

		JSAN.use('circ.util');
		var columns = circ.util.columns( 
			{ 
				'barcode' : { 'hidden' : false },
				'title' : { 'hidden' : false },
				'location' : { 'hidden' : false },
				'call_number' : { 'hidden' : false },
				'status' : { 'hidden' : false },
				'alert_message' : { 'hidden' : false },
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
							obj.controller.view.sel_checkin.setAttribute('disabled','true');
							obj.controller.view.sel_edit.setAttribute('disabled','true');
							obj.controller.view.sel_opac.setAttribute('disabled','true');
							obj.controller.view.sel_patron.setAttribute('disabled','true');
							obj.controller.view.sel_bucket.setAttribute('disabled','true');
							obj.controller.view.sel_spine.setAttribute('disabled','true');
							obj.controller.view.sel_transit_abort.setAttribute('disabled','true');
						} else {
							obj.controller.view.sel_checkin.setAttribute('disabled','false');
							obj.controller.view.sel_edit.setAttribute('disabled','false');
							obj.controller.view.sel_opac.setAttribute('disabled','false');
							obj.controller.view.sel_patron.setAttribute('disabled','false');
							obj.controller.view.sel_bucket.setAttribute('disabled','false');
							obj.controller.view.sel_spine.setAttribute('disabled','false');
							obj.controller.view.sel_transit_abort.setAttribute('disabled','false');
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
							try {
								JSAN.use('circ.util');
								for (var i = 0; i < obj.selection_list.length; i++) {
									var barcode = obj.selection_list[i].barcode;
									var checkin = circ.util.checkin_via_barcode( ses(), barcode );
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Checkin did not likely happen.',E);
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
					'sel_spine' : [
						['command'],
						function() {
							try {
								JSAN.use('util.functional');
								xulG.new_tab(
									xulG.url_prefix( urls.XUL_SPINE_LABEL ) + '?barcodes=' 
									+ js2JSON( util.functional.map_list(obj.selection_list,function(o){return o.barcode;}) ),
									{ 'tab_name' : 'Spine Labels' },
									{}
								);
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Spine Labels',E);
							}
						}
					],
					'sel_opac' : [
						['command'],
						function() {
							try {
								for (var i = 0; i < obj.selection_list.length; i++) {
									var doc_id = obj.selection_list[i].doc_id;
									if (!doc_id) {
										alert(obj.selection_list[i].barcode + ' is not cataloged');
										continue;
									}
									var opac_url = xulG.url_prefix( urls.opac_rdetail ) + '?r=' + doc_id;
									var content_params = { 
										'session' : ses(),
										'authtime' : ses('authtime'),
										'opac_url' : opac_url,
									};
									xulG.new_tab(
										xulG.url_prefix(urls.XUL_OPAC_WRAPPER), 
										{'tab_name':'Retrieving title...'}, 
										content_params
									);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('',E);
							}
						}
					],
					'sel_transit_abort' : [
						['command'],
						function() {
							JSAN.use('util.functional');
							var msg = 'Are you sure you would like to abort transits for copies:' + util.functional.map_list( obj.selection_list, function(o){return o.copy_id;}).join(', ') + '?';
							var r = obj.error.yns_alert(msg,'Aborting Transits','Yes','No',null,'Check here to confirm this action');
							if (r == 0) {
								try {
									for (var i = 0; i < obj.selection_list.length; i++) {
										var copy_id = obj.selection_list[i].copy_id;
										var robj = obj.network.simple_request('FM_ATC_VOID',[ ses(), { 'copyid' : copy_id } ]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
								} catch(E) {
									obj.error.standard_unexpected_error_alert('Transit not likely aborted.',E);
								}
							}
						}
					],
					'sel_patron' : [
						['command'],
						function() {
							var count = 5;
							for (var i = 0; i < obj.selection_list.length; i++) {
								try {
									var circs = obj.network.simple_request('FM_CIRC_RETRIEVE_VIA_COPY',
										[ ses(), obj.selection_list[i].copy_id, count ]);
									if (circs == null || typeof circs.ilsevent != 'undefined') throw(circs);
									if (circs.length == 0) { alert('There are no circs for item with barcode ' + obj.selection_list[i].barcode); continue; }
									netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
									var top_xml = '<description xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: auto">';
									top_xml += 'These are the last ' + circs.length + ' circulations for item ';
									top_xml += obj.selection_list[i].barcode + '</description>';

									var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
									for (var j = 0; j < circs.length; j++) {
										xml += '<iframe style="min-height: 100px" flex="1" src="' + xulG.url_prefix( urls.XUL_CIRC_BRIEF );
										xml += '?circ_id=' + circs[j].id() + '"/>';
									}
									xml += '</vbox>';
									
									var bot_xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: auto"><hbox>';
									bot_xml += '<button id="retrieve_last" value="last" label="Retrieve Last Patron" accesskey="L" name="fancy_submit"/>';
									bot_xml += '<button id="retrieve_all" value="all" label="Retrieve All Patrons" accesskey="A" name="fancy_submit"/>';
									bot_xml += '<button label="Done" accesskey="D" name="fancy_cancel"/></hbox></vbox>';

									obj.data.temp_top = top_xml; obj.data.stash('temp_top');
									obj.data.temp_mid = xml; obj.data.stash('temp_mid');
									obj.data.temp_bot = bot_xml; obj.data.stash('temp_bot');
									window.open(
										urls.XUL_FANCY_PROMPT
										+ '?xml_in_stash=temp_mid'
										+ '&top_xml_in_stash=temp_top'
										+ '&bottom_xml_in_stash=temp_bot'
										+ '&title=' + window.escape('Brief Circulation History'),
										'fancy_prompt', 'chrome,resizable,modal,width=700,height=500'
									);
									JSAN.use('OpenILS.data');
									var data = new OpenILS.data(); data.init({'via':'stash'});
									if (data.fancy_prompt_data == '') { continue; }
									var patron_hash = {};
									for (var j = 0; j < (data.fancy_prompt_data.fancy_submit == 'all' ? circs.length : 1); j++) {
										if (typeof patron_hash[circs[j].usr()] != 'undefined') {
											continue;
										} else {
											patron_hash[circs[j].usr()] = true;
										}
										if (typeof window.xulG == 'object' && typeof window.xulG.new_tab == 'function') {
											try {
												var url = urls.XUL_PATRON_DISPLAY 
													+ '?id=' + window.escape( circs[j].usr() );
												window.xulG.new_tab( url );
											} catch(E) {
												obj.error.standard_unexpected_error_alert('Problem retrieving patron.',E);
											}
										}

									}

								} catch(E) {
									obj.error.standard_unexpected_error_alert('Problem retrieving circulations.',E);
								}
							}
							//FM_CIRC_RETRIEVE_VIA_COPY
						}
					],
					'sel_bucket' : [
						['command'],
						function() {
							JSAN.use('util.functional');
							JSAN.use('util.window'); var win = new util.window();
							win.open( 
								xulG.url_prefix(urls.XUL_COPY_BUCKETS) 
								+ '?copy_ids=' + js2JSON(
									util.functional.map_list(
										obj.selection_list,
										function (o) {
											return o.copy_id;
										}
									)
								),
								'sel_bucket_win' + win.window_name_increment(),
								'chrome,resizable,modal,center'
							);
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
							try {
							dump( js2JSON( obj.list.dump() ) + '\n' );
							obj.data.stash_retrieve();
							var lib = obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ];
							lib.children(null);
							var p = { 
								'lib' : lib,
								'staff' : obj.data.list.au[0],
								'header' : obj.data.print_list_templates.item_status.header,
								'line_item' : obj.data.print_list_templates.item_status.line_item,
								'footer' : obj.data.print_list_templates.item_status.footer,
								'type' : obj.data.print_list_templates.item_status.type,
								'list' : obj.list.dump(),
							};
							JSAN.use('util.print'); var print = new util.print();
							print.tree_list( p );
							} catch(E) {
								alert(E); 
							}
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

	'copy_status' : function(barcode) {
		var obj = this;
		try {
			if (!barcode) barcode = obj.controller.view.copy_status_barcode_entry_textbox.value;
			JSAN.use('circ.util');
			var copy = obj.network.simple_request( 'FM_ACP_RETRIEVE_VIA_BARCODE', [ barcode ]);
			if (copy == null) {
				throw('Something weird happened.  null result');
			} else if (copy.ilsevent) {
				switch(copy.ilsevent) {
					case -1: 
						obj.error.standard_network_error_alert(); 
						obj.controller.view.copy_status_barcode_entry_textbox.select();
						obj.controller.view.copy_status_barcode_entry_textbox.focus();
					break;
					case 1502 /* ASSET_COPY_NOT_FOUND */ :
						obj.error.yns_alert(barcode + ' was either mis-scanned or is not cataloged.','Not Cataloged','OK',null,null,'Check here to confirm this message');
						obj.controller.view.copy_status_barcode_entry_textbox.select();
						obj.controller.view.copy_status_barcode_entry_textbox.focus();
					break;
					default: 
						throw(copy); 
					break;
				}
			} else {
				var my_mvr = obj.network.simple_request('MODS_SLIM_RECORD_RETRIEVE_VIA_COPY', [ copy.id() ]);
				obj.list.append(
					{
						'retrieve_id' : js2JSON( { 'copy_id' : copy.id(), 'barcode' : barcode, 'doc_id' : (typeof my_mvr.ilsevent == 'undefined' ? my_mvr.doc_id() : null ) } ),
						'row' : {
							'my' : {
								'mvr' : my_mvr,
								'acp' : copy,
							}
						}
					}
				);
				obj.controller.view.copy_status_barcode_entry_textbox.value = '';
				obj.controller.view.copy_status_barcode_entry_textbox.focus();
			}
		} catch(E) {
			obj.error.standard_unexpected_error_alert('',E);
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
			function (o) {
				return o.copy_id;
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
					ses(), 
					obj.data.list.au[0].id(), 
					util.functional.map_list(
						copies,
						function (o) {
							return obj.network.simple_request('FM_ACN_RETRIEVE',[o.call_number()]).owning_lib();
						}
					),
					[ 'UPDATE_COPY', 'UPDATE_BATCH_COPY' ]
				]
			).length == 0 ? 1 : 0;
		} catch(E) {
			obj.error.sdump('D_ERROR','batch permission check: ' + E);
		}

		JSAN.use('cat.util'); cat.util.spawn_copy_editor(list,edit);

	},

}

dump('exiting circ.copy_status.js\n');
