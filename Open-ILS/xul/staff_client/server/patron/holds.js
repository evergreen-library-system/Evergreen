dump('entering patron.holds.js\n');

if (typeof patron == 'undefined') patron = {};
patron.holds = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
}

patron.holds.prototype = {

	'foreign_shelf' : null,

	'retrieve_ids' : [],

	'holds_map' : {},

    'flatten_copy' : function(hold) {
        try { if ( hold.current_copy() && typeof hold.current_copy() == 'object') hold.current_copy( hold.current_copy().id() ); } catch(E) { alert('FIXME: Error flattening hold before hold update: ' + E); }
        return hold;
    },

	'init' : function( params ) {

		var obj = this;

		obj.patron_id = params['patron_id'];
		obj.docid = params['docid'];
		obj.shelf = params['shelf'];
		obj.tree_id = params['tree_id'];

		JSAN.use('circ.util');
		var columns = circ.util.hold_columns( 
			{ 
				'title' : { 'hidden' : false, 'flex' : '3' },
				'request_time' : { 'hidden' : false },
				'pickup_lib_shortname' : { 'hidden' : false },
				'hold_type' : { 'hidden' : false },
				'current_copy' : { 'hidden' : false },
				'capture_time' : { 'hidden' : false },
				'notify_time' : { 'hidden' : false },
				'notify_count' : { 'hidden' : false },
			} 
		);

		JSAN.use('util.list'); obj.list = new util.list( obj.tree_id || 'holds_list');
		obj.list.init(
			{
				'columns' : columns,
				'map_row_to_columns' : circ.util.std_map_row_to_columns(),
				'retrieve_row' : function(params) {
					var row = params.row;
					try {
						obj.network.simple_request('FM_AHR_BLOB_RETRIEVE', [ ses(), row.my.hold_id ],
							function(blob_req) {
								try {
									var blob = blob_req.getResultObject();
									if (typeof blob.ilsevent != 'undefined') throw(blob);
									row.my.ahr = blob.hold;
									row.my.status = blob.status;
                                    row.my.ahr.status( blob.status );
									row.my.acp = blob.copy;
									row.my.acn = blob.volume;
									row.my.mvr = blob.mvr;
									row.my.patron_family_name = blob.patron_last;
									row.my.patron_first_given_name = blob.patron_first;
									row.my.patron_barcode = blob.patron_barcode;

									var copy_id = row.my.ahr.current_copy();
									if (typeof copy_id == 'object') {
										if (copy_id == null) {
											if (typeof row.my.acp == 'object' && row.my.acp != null) copy_id = row.my.acp.id();
										} else {
											copy_id = copy_id.id();
										}
									} else {
										copy_id = row.my.acp.id();
									}

									obj.holds_map[ row.my.ahr.id() ] = row.my.ahr;
									params.row_node.setAttribute('retrieve_id', 
										js2JSON({
											'copy_id':copy_id,
                                            'barcode':row.my.acp ? row.my.acp.barcode() : null,
											'id':row.my.ahr.id(),
											'type':row.my.ahr.hold_type(),
											'target':row.my.ahr.target(),
											'usr':row.my.ahr.usr(),
										})
									);
									if (typeof params.on_retrieve == 'function') { params.on_retrieve(row); }

								} catch(E) {
									obj.error.standard_unexpected_error_alert('Error retrieving details for hold #' + row.my.hold_id, E);
								}
							}
						);
						/*
						obj.network.simple_request('FM_AHR_RETRIEVE', [ ses(), row.my.hold_id ],
							function(ahr_req) {
								try {
									var ahr_robj = ahr_req.getResultObject();
									if (typeof ahr_robj.ilsevent != 'undefined') throw(ahr_robj);
									row.my.ahr = ahr_robj[0];
									obj.holds_map[ row.my.ahr.id() ] = row.my.ahr;
									params.row_node.setAttribute('retrieve_id', 
										js2JSON({
											'copy_id':row.my.ahr.current_copy(),
											'id':row.my.ahr.id(),
											'type':row.my.ahr.hold_type(),
											'target':row.my.ahr.target(),
											'usr':row.my.ahr.usr(),
										})
									);

									obj.network.simple_request('FM_AHR_STATUS',[ ses(), row.my.ahr.id() ],
										function(status_req) {
											try {
												var status_robj = status_req.getResultObject();
												row.my.status = status_robj;
												switch(row.my.ahr.hold_type()) {
													case 'M' :
														obj.network.request(
															api.MODS_SLIM_METARECORD_RETRIEVE.app,
															api.MODS_SLIM_METARECORD_RETRIEVE.method,
															[ row.my.ahr.target() ],
															function(mvr_req) {
																row.my.mvr = mvr_req.getResultObject();
																if ( row.my.ahr.current_copy() && ! row.my.acp) {
																	obj.network.simple_request( 'FM_ACP_RETRIEVE', [ row.my.ahr.current_copy() ],
																		function(acp_req) {
																			row.my.acp = acp_req.getResultObject();
																			if (typeof params.on_retrieve == 'function') { params.on_retrieve(row); }
																		}
																	);
																} else {
																	if (typeof params.on_retrieve == 'function') { params.on_retrieve(row); }
																}
															}
														);
													break;
													case 'T' :
														obj.network.request(
															api.MODS_SLIM_RECORD_RETRIEVE.app,
															api.MODS_SLIM_RECORD_RETRIEVE.method,
															[ row.my.ahr.target() ],
															function(mvr_req) {
																row.my.mvr = mvr_req.getResultObject();
																if ( row.my.ahr.current_copy() && ! row.my.acp) {
																	obj.network.simple_request( 'FM_ACP_RETRIEVE', [ row.my.ahr.current_copy() ],
																		function(acp_req) {
																			row.my.acp = acp_req.getResultObject();
																			if (typeof params.on_retrieve == 'function') { params.on_retrieve(row); }
																		}
																	);
																} else {
																	if (typeof params.on_retrieve == 'function') { params.on_retrieve(row); }
																}
	
															}
														);
													break;
													case 'V' :
														row.my.acn = obj.network.simple_request( 'FM_ACN_RETRIEVE', [ row.my.ahr.target() ],
															function(acn_req) {
																row.my.acn = acn_req.getResultObject();
																obj.network.request(
																	api.MODS_SLIM_RECORD_RETRIEVE.app,
																	api.MODS_SLIM_RECORD_RETRIEVE.method,
																	[ row.my.acn.record() ],
																	function(mvr_req) {
																		try { row.my.mvr = mvr_req.getResultObject(); } catch(E) {}
																		if ( row.my.ahr.current_copy() && ! row.my.acp) {
																			obj.network.simple_request( 'FM_ACP_RETRIEVE', [ row.my.ahr.current_copy() ],
																				function(acp_req) {
																					row.my.acp = acp_req.getResultObject();
																					if (typeof params.on_retrieve == 'function') { params.on_retrieve(row); }
																				}
																			);
																		} else {
																			if (typeof params.on_retrieve == 'function') { params.on_retrieve(row); }
																		}
																	}
																);
															}
														);
													break;
													case 'C' :
														obj.network.simple_request( 'FM_ACP_RETRIEVE', [ row.my.ahr.target() ],
															function(acp_req) {
																row.my.acp = acp_req.getResultObject();
																obj.network.simple_request( 'FM_ACN_RETRIEVE', [ typeof row.my.acp.call_number() == 'object' ? row.my.acp.call_number().id() : row.my.acp.call_number() ],
																	function(acn_req) {
																		row.my.acn = acn_req.getResultObject();
																		obj.network.request(
																			api.MODS_SLIM_RECORD_RETRIEVE.app,
																			api.MODS_SLIM_RECORD_RETRIEVE.method,
																			[ row.my.acn.record() ],
																			function(mvr_req) {
																				try { row.my.mvr = mvr_req.getResultObject(); } catch(E) {}
																				if (typeof params.on_retrieve == 'function') { params.on_retrieve(row); }
																			}
																		);
																	}
																);
															}
														);
													break;
												}
											} catch(E) {
												obj.error.standard_unexpected_error_alert('Error retrieving status for hold #' + row.my.hold_id, E);
											}
										}
									);
								} catch(E) {
									obj.error.standard_unexpected_error_alert('Error retrieving hold #' + row.my.hold_id, E);
								}
							}
						);
						*/
					} catch(E) {
						obj.error.sdump('D_ERROR','retrieve_row: ' + E );
					}
					return row;
				},
				'on_select' : function(ev) {
					JSAN.use('util.functional');
					var sel = obj.list.retrieve_selection();
					obj.controller.view.sel_clip.setAttribute('disabled',sel.length < 1);
					obj.retrieve_ids = util.functional.map_list(
						sel,
						function(o) { return JSON2js( o.getAttribute('retrieve_id') ); }
					);
					if (obj.retrieve_ids.length > 0) {
						obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','false');
						obj.controller.view.sel_mark_items_missing.setAttribute('disabled','false');
						obj.controller.view.sel_copy_details.setAttribute('disabled','false');
						obj.controller.view.sel_patron.setAttribute('disabled','false');
						obj.controller.view.cmd_retrieve_patron.setAttribute('disabled','false');
						obj.controller.view.cmd_holds_edit_pickup_lib.setAttribute('disabled','false');
						obj.controller.view.cmd_holds_edit_phone_notify.setAttribute('disabled','false');
						obj.controller.view.cmd_holds_edit_email_notify.setAttribute('disabled','false');
						obj.controller.view.cmd_holds_edit_selection_depth.setAttribute('disabled','false');
						obj.controller.view.cmd_holds_edit_thaw_date.setAttribute('disabled','false');
						obj.controller.view.cmd_holds_activate.setAttribute('disabled','false');
						obj.controller.view.cmd_holds_suspend.setAttribute('disabled','false');
						obj.controller.view.cmd_show_notifications.setAttribute('disabled','false');
						obj.controller.view.cmd_holds_retarget.setAttribute('disabled','false');
						obj.controller.view.cmd_holds_cancel.setAttribute('disabled','false');
						obj.controller.view.cmd_show_catalog.setAttribute('disabled','false');
					} else {
						obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','true');
						obj.controller.view.sel_mark_items_missing.setAttribute('disabled','true');
						obj.controller.view.sel_copy_details.setAttribute('disabled','true');
						obj.controller.view.sel_patron.setAttribute('disabled','true');
						obj.controller.view.cmd_retrieve_patron.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_edit_pickup_lib.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_edit_phone_notify.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_edit_email_notify.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_edit_selection_depth.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_edit_thaw_date.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_activate.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_suspend.setAttribute('disabled','true');
						obj.controller.view.cmd_show_notifications.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_retarget.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_cancel.setAttribute('disabled','true');
						obj.controller.view.cmd_show_catalog.setAttribute('disabled','true');
					}
				},

			}
		);
		
		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				'control_map' : {
					'save_columns' : [ [ 'command' ], function() { obj.list.save_columns(); } ],
					'sel_clip' : [
						['command'],
						function() { obj.list.clipboard(); }
					],
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'sel_patron' : [
						['command'],
						function() {
							JSAN.use('circ.util');
							circ.util.show_last_few_circs(obj.retrieve_ids);
						}
					],
					'sel_mark_items_damaged' : [
						['command'],
						function() {
							JSAN.use('cat.util'); JSAN.use('util.functional');
							cat.util.mark_item_damaged( util.functional.map_list( obj.retrieve_ids, function(o) { return o.copy_id; } ) );
						}
					],
					'sel_mark_items_missing' : [
						['command'],
						function() {
							JSAN.use('cat.util'); JSAN.use('util.functional');
							cat.util.mark_item_missing( util.functional.map_list( obj.retrieve_ids, function(o) { return o.copy_id; } ) );
						}
					],
					'sel_copy_details' : [
						['command'],
						function() {
							JSAN.use('circ.util');
							for (var i = 0; i < obj.retrieve_ids.length; i++) {
								if (obj.retrieve_ids[i].copy_id) circ.util.show_copy_details( obj.retrieve_ids[i].copy_id );
							}
						}
					],
					'cmd_holds_print' : [
						['command'],
						function() {
							try {
								JSAN.use('patron.util');
								var params = { 
									'patron' : patron.util.retrieve_au_via_id(ses(),obj.patron_id), 
									'template' : 'holds'
								};
								obj.list.print(params);
							} catch(E) {
								obj.error.standard_unexpected_error_alert('print 1',E);
							}
						}
					],
					'cmd_holds_export' : [
						['command'],
						function() {
							try {
								obj.list.dump_csv_to_clipboard();
							} catch(E) {
								obj.error.standard_unexpected_error_alert('export 1',E);
							}
						}
					],

					'cmd_show_notifications' : [
						['command'],
						function() {
							try {
								JSAN.use('util.window'); var win = new util.window();
								for (var i = 0; i < obj.retrieve_ids.length; i++) {
									netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
									win.open(
										xulG.url_prefix(urls.XUL_HOLD_NOTICES), // + '?ahr_id=' + obj.retrieve_ids[i].id,
										'hold_notices_' + obj.retrieve_ids[i].id,
										'chrome,resizable',
										{ 'ahr_id' : obj.retrieve_ids[i].id }
									);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Error rendering/retrieving hold notifications.',E);
							}
						}
					],
					'cmd_holds_edit_selection_depth' : [
						['command'],
						function() {
							try {
								JSAN.use('util.widgets'); JSAN.use('util.functional'); 
								var ws_type = obj.data.hash.aout[ obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ].ou_type() ];
								var list = util.functional.map_list(
									util.functional.filter_list(	
										obj.data.list.aout,
										function(o) {
											if (o.depth() > ws_type.depth()) return false;
											if (o.depth() < ws_type.depth()) return true;
											return (o.id() == ws_type.id());
										}
									),
									function(o) { 
										return [
											o.opac_label(),
											o.id(),
											false,
											( o.depth() * 2),
										]; 
									}
								);
								ml = util.widgets.make_menulist( list, obj.data.list.au[0].ws_ou() );
								ml.setAttribute('id','selection');
								ml.setAttribute('name','fancy_data');
								var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								xml += '<description>Please choose a Hold Range:</description>';
								xml += util.widgets.serialize_node(ml);
								xml += '</vbox>';
								var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								bot_xml += '<spacer flex="1"/><button label="Done" accesskey="D" name="fancy_submit"/>';
								bot_xml += '<button label="Cancel" accesskey="C" name="fancy_cancel"/></hbox>';
								netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
								//obj.data.temp_mid = xml; obj.data.stash('temp_mid');
								//obj.data.temp_bot = bot_xml; obj.data.stash('temp_bot');
								JSAN.use('util.window'); var win = new util.window();
								var fancy_prompt_data = win.open(
									urls.XUL_FANCY_PROMPT,
									//+ '?xml_in_stash=temp_mid'
									//+ '&bottom_xml_in_stash=temp_bot'
									//+ '&title=' + window.escape('Choose a Pick Up Library'),
									'fancy_prompt', 'chrome,resizable,modal',
									{ 'xml' : xml, 'bottom_xml' : bot_xml, 'title' : 'Choose a Pick Up Library' }
								);
								if (fancy_prompt_data.fancy_status == 'incomplete') { return; }
								var selection = fancy_prompt_data.selection;
								var msg = 'Are you sure you would like to change the Hold Range for hold' + ( obj.retrieve_ids.length > 1 ? 's ' : ' ') + util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ') + ' to "' + obj.data.hash.aout[selection].opac_label() + '"?';
								var r = obj.error.yns_alert(msg,'Modifying Holds','Yes','No',null,'Check here to confirm this message');
								if (r == 0) {
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
										hold.selection_depth( obj.data.hash.aout[selection].depth() ); hold.ischanged('1');
                                        hold = obj.flatten_copy(hold);
										var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
									obj.retrieve(true);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Holds not likely modified.',E);
							}
						}
					],

					'cmd_holds_edit_pickup_lib' : [
						['command'],
						function() {
							try {
								JSAN.use('util.widgets'); JSAN.use('util.functional'); 

                                var deny_edit_because_of_transit = false;
                                for (var i = 0; i < obj.retrieve_ids.length; i++) {
                                    var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
                                    if (hold.status() > 2 /* Which means holds that are In-Transit or Ready for Pickup */) deny_edit_because_of_transit = true;
                                }
                                if (deny_edit_because_of_transit) {
                                    alert('You may not edit the pickup library for holds that are in-transit or ready for pickup.');
                                    return;
                                }

								var list = util.functional.map_list(
									obj.data.list.aou,
									function(o) { 
										var sname = o.shortname(); for (i = sname.length; i < 20; i++) sname += ' ';
										return [
											o.name() ? sname + ' ' + o.name() : o.shortname(),
											o.id(),
											( obj.data.hash.aout[ o.ou_type() ].can_have_users() == 0),
											( obj.data.hash.aout[ o.ou_type() ].depth() * 2),
										]; 
									}
								);
								ml = util.widgets.make_menulist( list, obj.data.list.au[0].ws_ou() );
								ml.setAttribute('id','lib');
								ml.setAttribute('name','fancy_data');
								var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								xml += '<description>Please choose a new Pickup Library:</description>';
								xml += util.widgets.serialize_node(ml);
								xml += '</vbox>';
								var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								bot_xml += '<spacer flex="1"/><button label="Done" accesskey="D" name="fancy_submit"/>';
								bot_xml += '<button label="Cancel" accesskey="C" name="fancy_cancel"/></hbox>';
								netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
								//obj.data.temp_mid = xml; obj.data.stash('temp_mid');
								//obj.data.temp_bot = bot_xml; obj.data.stash('temp_bot');
								JSAN.use('util.window'); var win = new util.window();
								var fancy_prompt_data = win.open(
									urls.XUL_FANCY_PROMPT,
									//+ '?xml_in_stash=temp_mid'
									//+ '&bottom_xml_in_stash=temp_bot'
									//+ '&title=' + window.escape('Choose a Pick Up Library'),
									'fancy_prompt', 'chrome,resizable,modal',
									{ 'xml' : xml, 'bottom_xml' : bot_xml, 'title' : 'Choose a Pick Up Library' }
								);
								if (fancy_prompt_data.fancy_status == 'incomplete') { return; }
								var pickup_lib = fancy_prompt_data.lib;
								var msg = 'Are you sure you would like to change the Pick Up Lib for hold' + ( obj.retrieve_ids.length > 1 ? 's ' : ' ') + util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ') + ' to ' + obj.data.hash.aou[pickup_lib].shortname() + '?';
								var r = obj.error.yns_alert(msg,'Modifying Holds','Yes','No',null,'Check here to confirm this message');
								if (r == 0) {
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
										hold.pickup_lib(  pickup_lib ); hold.ischanged('1');
                                        hold = obj.flatten_copy(hold);
										var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
									obj.retrieve(true);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Holds not likely modified.',E);
							}
						}
					],
					'cmd_holds_edit_phone_notify' : [
						['command'],
						function() {
							try {
								var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								xml += '<description>Please enter a new phone number for hold notification (leave the field empty to disable phone notification):</description>';
								xml += '<textbox id="phone" name="fancy_data"/>';
								xml += '</vbox>';
								var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								bot_xml += '<spacer flex="1"/><button label="Done" accesskey="D" name="fancy_submit"/>';
								bot_xml += '<button label="Cancel" accesskey="C" name="fancy_cancel"/></hbox>';
								netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
								//obj.data.temp_mid = xml; obj.data.stash('temp_mid');
								//obj.data.temp_bot = bot_xml; obj.data.stash('temp_bot');
								JSAN.use('util.window'); var win = new util.window();
								var fancy_prompt_data = win.open(
									urls.XUL_FANCY_PROMPT,
									//+ '?xml_in_stash=temp_mid'
									//+ '&bottom_xml_in_stash=temp_bot'
									//+ '&title=' + window.escape('Choose a Hold Notification Phone Number')
									//+ '&focus=phone',
									'fancy_prompt', 'chrome,resizable,modal',
									{ 'xml' : xml, 'bottom_xml' : bot_xml, 'title' : 'Choose a Hold Notification Phone Number', 'focus' : 'phone' }
								);
								if (fancy_prompt_data.fancy_status == 'incomplete') { return; }
								var phone = fancy_prompt_data.phone;
								var msg = 'Are you sure you would like to change the Notification Phone Number for hold' + ( obj.retrieve_ids.length > 1 ? 's ' : ' ') + util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ') + ' to "' + phone + '"?';
								var r = obj.error.yns_alert(msg,'Modifying Holds','Yes','No',null,'Check here to confirm this message');
								if (r == 0) {
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
										hold.phone_notify(  phone ); hold.ischanged('1');
                                        hold = obj.flatten_copy(hold);
										var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
									obj.retrieve(true);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Holds not likely modified.',E);
							}
						}
					],
					'cmd_holds_edit_email_notify' : [
						['command'],
						function() {
							try {
								var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								xml += '<description>Send email notifications (when appropriate)?  The email address used is found in the hold recipient account.</description>';
								xml += '<hbox><button value="email" label="Email" accesskey="E" name="fancy_submit"/>';
								xml += '<button value="noemail" label="No Email" accesskey="N" name="fancy_submit"/></hbox>';
								xml += '</vbox>';
								var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								bot_xml += '<spacer flex="1"/><button label="Cancel" accesskey="C" name="fancy_cancel"/></hbox>';
								netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
								//obj.data.temp_mid = xml; obj.data.stash('temp_mid');
								//obj.data.temp_bot = bot_xml; obj.data.stash('temp_bot');
								JSAN.use('util.window'); var win = new util.window();
								var fancy_prompt_data = win.open(
									urls.XUL_FANCY_PROMPT,
									//+ '?xml_in_stash=temp_mid'
									//+ '&bottom_xml_in_stash=temp_bot'
									//+ '&title=' + window.escape('Set Email Notification for Holds'),
									'fancy_prompt', 'chrome,resizable,modal',
									{ 'xml' : xml, 'bottom_xml' : bot_xml, 'title' : 'Set Email Notification for Holds' }
								);
								if (fancy_prompt_data.fancy_status == 'incomplete') { return; }
								var email = fancy_prompt_data.fancy_submit == 'email' ? get_db_true() : get_db_false();
								var msg = 'Are you sure you would like ' + ( get_bool( email ) ? 'enable' : 'disable' ) + ' email notification for hold' + ( obj.retrieve_ids.length > 1 ? 's ' : ' ') + util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ') + '?';
								var r = obj.error.yns_alert(msg,'Modifying Holds','Yes','No',null,'Check here to confirm this message');
								if (r == 0) {
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
										hold.email_notify(  email ); hold.ischanged('1');
                                        hold = obj.flatten_copy(hold);
										var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
									obj.retrieve(true);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Holds not likely modified.',E);
							}
						}
					],
                    'cmd_holds_suspend' : [
						['command'],
						function() {
							try {
                                var hold_list = util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', '); 
								var r = obj.error.yns_alert(
                                    obj.retrieve_ids.length > 1 ?
                                    'Are you sure you would like to suspend holds ' + hold_list + '?' :
                                    'Are you sure you would like to suspend hold ' + hold_list + '?',
                                    'Modifying Holds',
                                    'Yes',
                                    'No',
                                    null,
                                    'Check here to confirm this message.'
                                );
								if (r == 0) {
                                    var already_suspended = [];
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
                                        if ( get_bool( hold.frozen() ) ) {
                                            already_suspended.push( hold.id() );
                                            continue; 
                                        }
										hold.frozen('t'); 
										hold.thaw_date(null);
										hold.ischanged('1');
                                        hold = obj.flatten_copy(hold);
										var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
                                    if (already_suspended.length == 1) {
                                        alert( 'Hold ' + already_suspended[0] + ' is already suspended.' );
                                    } else if (already_suspended.length > 1) {
                                        alert( 'Holds ' + already_suspended.join(', ') + ' are already suspended.' );
                                    }
									obj.retrieve(true);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Holds not likely suspended.',E);
							}
						}
					],
                    'cmd_holds_activate' : [
						['command'],
						function() {
							try {
                                var hold_list = util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', '); 
								var r = obj.error.yns_alert(
                                    obj.retrieve_ids.length > 1 ?
                                    'Are you sure you would like to activate holds ' + hold_list + '?' :
                                    'Are you sure you would like to activate hold ' + hold_list + '?',
                                    'Modifying Holds',
                                    'Yes',
                                    'No',
                                    null,
                                    'Check here to confirm this message.'
                                );
								if (r == 0) {
                                    var already_activated = [];
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
                                        if ( ! get_bool( hold.frozen() ) ) {
                                            already_activated.push( hold.id() );
                                            continue; 
                                        }
										hold.frozen('f'); 
										hold.thaw_date(null);
										hold.ischanged('1');
                                        hold = obj.flatten_copy(hold);
										var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
                                    if (already_activated.length == 1) {
                                        alert( 'Hold ' + already_activated[0] + ' is already activated.' );
                                    } else if (already_activated.length > 1) {
                                        alert( 'Holds ' + already_activated.join(', ') + ' are already activated.' );
                                    }
									obj.retrieve(true);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Holds not likely activated.',E);
							}
						}
					],
                    'cmd_holds_edit_thaw_date' : [
						['command'],
						function() {
							try {
                                JSAN.use('util.date');
                                function check_date(value) {
                                    try {
                                        if (! util.date.check('YYYY-MM-DD',value) ) { throw('Invalid Date'); }
                                        if (util.date.check_past('YYYY-MM-DD',value) || util.date.formatted_date(new Date(),'%F') == value ) { 
                                            throw('Activation date for suspended holds needs to be after today.'); 
                                        }
                                        return true;
                                    } catch(E) {
                                        alert(E);
                                        return false;
                                    }
                                }

								var msg = 'Please enter an activation date for hold' + ( obj.retrieve_ids.length > 1 ? 's ' : ' ') + util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ') + '\nOr set to blank to unset the activation date for these holds.  Suspended holds without an activation date will remain suspended until manually activated, otherwise they activate on the activation date.';
                                var value = 'YYYY-MM-DD';
                                var title = 'Modifying Holds';
								var thaw_date; var invalid = true;
                                while(invalid) {
                                    thaw_date = window.prompt(msg,value,title);
                                    if (thaw_date) {
                                        invalid = ! check_date(thaw_date);
                                    } else { 
                                        invalid = false;
                                    }
                                }
                                if (thaw_date || thaw_date == '') {
                                    for (var i = 0; i < obj.retrieve_ids.length; i++) {
                                        var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
                                        hold.thaw_date(  thaw_date == '' ? null : util.date.formatted_date(thaw_date + ' 00:00:00','%{iso8601}') ); 
                                        hold.frozen('t');
                                        hold.ischanged('1');
                                        hold = obj.flatten_copy(hold);
                                        var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
                                        if (typeof robj.ilsevent != 'undefined') throw(robj);
                                    }
									obj.retrieve(true);
                                }
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Holds not likely modified.',E);
							}
						}
					],

					'cmd_holds_retarget' : [
						['command'],
						function() {
							try {
								JSAN.use('util.functional');
								var msg = 'Are you sure you would like to reset hold' + ( obj.retrieve_ids.length > 1 ? 's ' : ' ') + util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ') + '?';
								var r = obj.error.yns_alert(msg,'Resetting Holds','Yes','No',null,'Check here to confirm this message');
								if (r == 0) {
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var robj = obj.network.simple_request('FM_AHR_RESET',[ ses(), obj.retrieve_ids[i].id]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
									obj.retrieve();
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Holds not likely reset.',E);
							}

						}
					],

					'cmd_holds_cancel' : [
						['command'],
						function() {
							try {
								JSAN.use('util.functional');
								var msg = 'Are you sure you would like to cancel hold' + ( obj.retrieve_ids.length > 1 ? 's ' : ' ') + util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ') + '?';
								var r = obj.error.yns_alert(msg,'Cancelling Holds','Yes','No',null,'Check here to confirm this message');
								if (r == 0) {
                                    var transits = [];
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
                                        if (obj.holds_map[ obj.retrieve_ids[i].id ].transit()) {
                                            transits.push( obj.retrieve_ids[i].barcode );
                                        }
										var robj = obj.network.simple_request('FM_AHR_CANCEL',[ ses(), obj.retrieve_ids[i].id]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
                                    if (transits.length > 0) {
                                        var msg2 = 'For barcodes ' + transits.join(', ') + ' cancel the transits as well?';
                                        var r2 = obj.error.yns_alert(msg2,'Cancelling Transits','Yes','No',null,'Check here to confirm this message');
                                        if (r2 == 0) {
                                            try {
                                                for (var i = 0; i < transits.length; i++) {
                                                    var robj = obj.network.simple_request('FM_ATC_VOID',[ ses(), { 'barcode' : transits[i] } ]);
                                                    if (typeof robj.ilsevent != 'undefined') {
                                                        switch(robj.ilsevent) {
                                                            case 1225 /* TRANSIT_ABORT_NOT_ALLOWED */ :
                                                                alert(robj.desc);
                                                            break;
                                                            case 5000 /* PERM_FAILURE */ :
                                                            break;
                                                            default:
                                                                throw(robj);
                                                            break;
                                                        }
										            }
                                                }
                                            } catch(E) {
    								            obj.error.standard_unexpected_error_alert('Hold-transits not likely cancelled.',E);
                                            }
                                        }
                                    }
									obj.retrieve();
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Holds not likely cancelled.',E);
							}
						}
					],
					'cmd_retrieve_patron' : [
						['command'],
						function() {
							try {
								var seen = {};
								for (var i = 0; i < obj.retrieve_ids.length; i++) {
									var patron_id = obj.retrieve_ids[i].usr;
									if (seen[patron_id]) continue; seen[patron_id] = true;
									xulG.new_tab(
										xulG.url_prefix(urls.XUL_PATRON_DISPLAY), // + '?id=' + patron_id, 
										{}, 
										{ 'id' : patron_id }
									);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('',E);
							}
						}
					],
					'cmd_show_catalog' : [
						['command'],
						function() {
							try {
								for (var i = 0; i < obj.retrieve_ids.length; i++) {
									var htarget = obj.retrieve_ids[i].target;
									var htype = obj.retrieve_ids[i].type;
									var opac_url;
									switch(htype) {
										case 'M' :
											opac_url = xulG.url_prefix( urls.opac_rresult ) + '?m=' + htarget;
										break;
										case 'T' : 
											opac_url = xulG.url_prefix( urls.opac_rdetail ) + '?r=' + htarget;
										break;
										case 'V' :
											var my_acn = obj.network.simple_request( 'FM_ACN_RETRIEVE', [ htarget ]);
											opac_url = xulG.url_prefix( urls.opac_rdetail) + '?r=' + my_acn.record();
										break;
										case 'C' :
											var my_acp = obj.network.simple_request( 'FM_ACP_RETRIEVE', [ htarget ]);
											var my_acn;
											if (typeof my_acp.call_number() == 'object') {
												my_acn = my.acp.call_number();
											} else {
												my_acn = obj.network.simple_request( 'FM_ACN_RETRIEVE', 
													[ my_acp.call_number() ]);
											}
											opac_url = xulG.url_prefix( urls.opac_rdetail) + '?r=' + my_acn.record();
										break;
										default:
											obj.error.standard_unexpected_error_alert("I don't understand the hold type of " + htype + ", so I can't jump to the appropriate record in the catalog.", obj.retrieve_ids[i]);
											continue;
										break;
									}
									var content_params = { 
										'session' : ses(),
										'authtime' : ses('authtime'),
										'opac_url' : opac_url,
									};
									xulG.new_tab(
										xulG.url_prefix(urls.XUL_OPAC_WRAPPER), 
										{'tab_name': htype == 'M' ? 'Catalog' : 'Retrieving title...'}, 
										content_params
									);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('',E);
							}
						}
					],
				}
			}
		);
		obj.controller.render();

		obj.retrieve();

		obj.controller.view.cmd_retrieve_patron.setAttribute('disabled','true');
		obj.controller.view.cmd_holds_edit_pickup_lib.setAttribute('disabled','true');
		obj.controller.view.cmd_holds_edit_phone_notify.setAttribute('disabled','true');
		obj.controller.view.cmd_holds_edit_email_notify.setAttribute('disabled','true');
		obj.controller.view.cmd_holds_edit_selection_depth.setAttribute('disabled','true');
		obj.controller.view.cmd_holds_edit_thaw_date.setAttribute('disabled','true');
        obj.controller.view.cmd_holds_activate.setAttribute('disabled','true');
        obj.controller.view.cmd_holds_suspend.setAttribute('disabled','true');
		obj.controller.view.cmd_show_notifications.setAttribute('disabled','true');
		obj.controller.view.cmd_holds_retarget.setAttribute('disabled','true');
		obj.controller.view.cmd_holds_cancel.setAttribute('disabled','true');
		obj.controller.view.cmd_show_catalog.setAttribute('disabled','true');
	},

	'retrieve' : function(dont_show_me_the_list_change) {
		var obj = this;
		if (window.xulG && window.xulG.holds) {
			obj.holds = window.xulG.holds;
		} else {
			var method; var params = [ ses() ];
			if (obj.patron_id) {                 /*************************************************** PATRON ******************************/
				method = 'FM_AHR_ID_LIST_RETRIEVE_VIA_AU'; 
				params.push( obj.patron_id ); 
				obj.controller.view.cmd_retrieve_patron.setAttribute('hidden','true');
			} else if (obj.docid) {                 /*************************************************** RECORD ******************************/
				method = 'FM_AHR_RETRIEVE_ALL_VIA_BRE'; 
				params.push( obj.docid ); 
				obj.controller.view.cmd_retrieve_patron.setAttribute('hidden','false');
			} else if (obj.pull) {                 /*************************************************** PULL ******************************/
				method = 'FM_AHR_ID_LIST_PULL_LIST'; 
				params.push( 100 ); params.push( 0 );
			} else if (obj.shelf) {
				method = 'FM_AHR_ID_LIST_ONSHELF_RETRIEVE';                  /*************************************************** HOLD SHELF ******************************/
				params.push( obj.foreign_shelf || obj.data.list.au[0].ws_ou() ); 
				obj.controller.view.cmd_retrieve_patron.setAttribute('hidden','false');
				obj.render_lib_menu();
			} else {
				//method = 'FM_AHR_RETRIEVE_VIA_PICKUP_AOU'; 
				method = 'FM_AHR_ID_LIST_PULL_LIST';                  /*************************************************** PULL ******************************/
				params.push( 100 ); params.push( 0 );
				obj.controller.view.cmd_retrieve_patron.setAttribute('hidden','false');
			}
			var robj = obj.network.simple_request( method, params );
			if (typeof robj.ilsevent != 'undefined') throw(robj);
			if (method == 'FM_AHR_RETRIEVE_ALL_VIA_BRE') {
				obj.holds = [];
				obj.holds = obj.holds.concat( robj.copy_holds );
				obj.holds = obj.holds.concat( robj.volume_holds );
				obj.holds = obj.holds.concat( robj.title_holds );
				obj.holds = obj.holds.sort();
			} else {
				obj.holds = robj;
			}
			//alert('method = ' + method + ' params = ' + js2JSON(params));
		}

		function list_append(hold_id) {
			obj.list.append(
				{
					'row' : {
						'my' : {
							'hold_id' : hold_id,
						}
					}
				}
			);
		}

		function gen_list_append(hold) {
			return function() {
				if (typeof obj.controller.view.lib_menu == 'undefined') {
					list_append(typeof hold == 'object' ? hold.id() : hold);
				} else {
					/*
					var pickup_lib = hold.pickup_lib();
					if (typeof pickup_lib == 'object') pickup_lib = pickup_lib.id();
					if (pickup_lib == obj.controller.view.lib_menu.value) {
					*/
						list_append(typeof hold == 'object' ? hold.id() : hold);
					/*
					}
					*/
				}
			};
		}

		obj.list.clear();

		//alert('obj.holds = ' + js2JSON(obj.holds));
		JSAN.use('util.exec'); var exec = new util.exec(2);
		var rows = [];
		for (var i in obj.holds) {
			rows.push( gen_list_append(obj.holds[i]) );
		}
		exec.chain( rows );
	
		if (!dont_show_me_the_list_change) {
			if (window.xulG && typeof window.xulG.on_list_change == 'function') {
				try { window.xulG.on_list_change(obj.holds); } catch(E) { this.error.sdump('D_ERROR',E); }
			}
		}
	},

	'render_lib_menu' : function() {
		try {
			var obj = this;
			JSAN.use('util.widgets'); JSAN.use('util.functional'); JSAN.use('util.fm_utils');
			var x = document.getElementById('menu_placeholder');
			if (x.firstChild) return;
			util.widgets.remove_children( x );
	
			var ml = util.widgets.make_menulist( 
				util.functional.map_list( 
					obj.data.list.my_aou.concat(
						util.functional.filter_list(
							util.fm_utils.find_ou(
								obj.data.tree.aou,
								obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ].parent_ou() ?  obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ].parent_ou() : obj.data.list.au[0].ws_ou()
							).children(),
							function(o) {
								return o.id() != obj.data.list.au[0].ws_ou();
							}
						)
					),
					function(o) { return [ 
						o.shortname(), 
						o.id(), 
						( ! get_bool( obj.data.hash.aout[ o.ou_type() ].can_have_users() ) ),
						( obj.data.hash.aout[ o.ou_type() ].depth() ),
					]; }
				).sort(
					function( a, b ) {
						var A = obj.data.hash.aou[ a[1] ];
						var B = obj.data.hash.aou[ b[1] ];
						var X = obj.data.hash.aout[ A.ou_type() ];
						var Y = obj.data.hash.aout[ B.ou_type() ];
						if (X.depth() < Y.depth()) return -1;
						if (X.depth() > Y.depth()) return 1;
						if (A.shortname() < B.shortname()) return -1;
						if (A.shortname() > B.shortname()) return 1;
						return 0;
					}
				),
				obj.data.list.au[0].ws_ou()
			);
			x.appendChild( ml );
			ml.addEventListener(
				'command',
				function(ev) {
					/*
					obj.list.on_all_fleshed = function() {
						obj.list.clear();
						obj.foreign_shelf = ev.target.value;
						obj.retrieve();
						setTimeout( function() { obj.list.on_all_fleshed = null; }, 0);
					};
					obj.list.full_retrieve();
					*/
					obj.list.clear();
					obj.foreign_shelf = ev.target.value;
					obj.retrieve();
				},
				false
			);
			obj.controller.view.lib_menu = ml;
		} catch(E) {
			this.error.standard_unexpected_error_alert('rendering lib menu',E);
		}
	},
}

dump('exiting patron.holds.js\n');
