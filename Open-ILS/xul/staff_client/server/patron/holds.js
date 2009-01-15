dump('entering patron.holds.js\n');

function $(id) { return document.getElementById(id); }

if (typeof patron == 'undefined') patron = {};
patron.holds = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
}

patron.holds.prototype = {

    'hold_interface_type' : null,

    'pull_from_shelf_interface' : {
        '_default' : { 'limit' : 50, 'offset' : 0 },
        'current' : { 'limit' : 50, 'offset' : 0 }
    },

	'filter_lib' : null,

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
				'notify_count' : { 'hidden' : false }
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
						obj.network.simple_request('FM_AHR_BLOB_RETRIEVE.authoritative', [ ses(), row.my.hold_id ],
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
											'usr':row.my.ahr.usr()
										})
									);
									if (typeof params.on_retrieve == 'function') { params.on_retrieve(row); }

								} catch(E) {
									obj.error.standard_unexpected_error_alert($("patronStrings").getFormattedString('staff.patron.holds.init.hold_num_error', [row.my.hold_id]), E);
								}
							}
						);
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
						obj.controller.view.cmd_holds_edit_expire_time.setAttribute('disabled','false');
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
						obj.controller.view.cmd_holds_edit_expire_time.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_edit_thaw_date.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_activate.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_suspend.setAttribute('disabled','true');
						obj.controller.view.cmd_show_notifications.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_retarget.setAttribute('disabled','true');
						obj.controller.view.cmd_holds_cancel.setAttribute('disabled','true');
						obj.controller.view.cmd_show_catalog.setAttribute('disabled','true');
					}
				}
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
						function() { alert($("commonStrings").getString('common.unimplemented')); }
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
                    'cmd_csv_to_clipboard' : [ ['command'], function() { obj.list.dump_csv_to_clipboard(); } ],
					'cmd_csv_to_printer' : [ ['command'], function() { obj.list.dump_csv_to_printer(); } ],
					'cmd_csv_to_file' : [ ['command'], function() { obj.list.dump_csv_to_file( { 'defaultFileName' : 'holds.txt' } ); } ],

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
								obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.show_notifications.error_rendering_notifs'),E);
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
								xml += '<description>' + $("patronStrings").getString('staff.patron.holds.holds_edit_selection_depth.choose_hold_range') + '</description>';
								xml += util.widgets.serialize_node(ml);
								xml += '</vbox>';
								var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								bot_xml += '<spacer flex="1"/><button label="'+ $("patronStrings").getString('staff.patron.holds.holds_edit_selection_depth.done.label') +'"';
								bot_xml += 'accesskey="'+ $("patronStrings").getString('staff.patron.holds.holds_edit_selection_depth.done.accesskey') +'" name="fancy_submit"/>';
								bot_xml += '<button label="'+ $("patronStrings").getString('staff.patron.holds.holds_edit_selection_depth.cancel.label') +'"';
								bot_xml += 'accesskey="'+ $("patronStrings").getString('staff.patron.holds.holds_edit_selection_depth.cancel.accesskey') +'" name="fancy_cancel"/></hbox>';
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
									{ 'xml' : xml, 'bottom_xml' : bot_xml, 'title' : $("patronStrings").getString('staff.patron.holds.holds_edit_selection_depth.choose_library') }
								);
								if (fancy_prompt_data.fancy_status == 'incomplete') { return; }
								var selection = fancy_prompt_data.selection;
                
								var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;}).join(', ');
								var msg = '';
								if(obj.retrieve_ids.length > 1) {
									msg = $("patronStrings").getformattedString('staff.patron.holds.holds_edit_selection_depth.modify_holds_message.plural', [hold_list, obj.data.hash.aout[selection].opac_label()])
								} else {
									msg = $("patronStrings").getformattedString('staff.patron.holds.holds_edit_selection_depth.modify_holds_message.singular', [hold_list, obj.data.hash.aout[selection].opac_label()])
								}
                    
								var r = obj.error.yns_alert(msg,
										$("patronStrings").getString('staff.patron.holds.holds_edit_selection_depth.modify_holds_title'),
										$("commonStrings").getString('common.yes'),
										$("commonStrings").getString('common.no'),
										null,
										$("commonStrings").getString('common.check_to_confirm')
								);
								if (r == 0) {
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
										hold.selection_depth( obj.data.hash.aout[selection].depth() ); hold.ischanged('1');
                                        hold = obj.flatten_copy(hold);
										var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
									obj.clear_and_retrieve(true);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_not_modified'),E);
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
                                    alert(document.getElementById('circStrings').getString('staff.circ.holds.error.may_not_edit_pickup_lib_for_hold_intransit'));
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
								xml += '<description>'+$("patronStrings").getString('staff.patron.holds.holds_edit_pickup_lib.new_pickup_lib.description')+'</description>';
								xml += util.widgets.serialize_node(ml);
								xml += '</vbox>';
								var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								bot_xml += '<spacer flex="1"/><button label="'+ $("patronStrings").getString('staff.patron.holds.holds_edit_pickup_lib.done.label') +'"';
								bot_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_pickup_lib.done.accesskey')+'" name="fancy_submit"/>';
								bot_xml += '<button label="'+$("patronStrings").getString('staff.patron.holds.holds_edit_pickup_lib.cancel.label')+'"';
								bot_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_pickup_lib.cancel.accesskey')+'" name="fancy_cancel"/></hbox>';
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
									{ 'xml' : xml, 'bottom_xml' : bot_xml, 'title' : $("patronStrings").getString('staff.patron.holds.holds_edit_pickup_lib.choose_lib') }
								);
								if (fancy_prompt_data.fancy_status == 'incomplete') { return; }
								var pickup_lib = fancy_prompt_data.lib;
                
								var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;}).join(', ');
								var msg = '';
								if(obj.retrieve_ids.length > 1) {
									msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_pickup_lib.change_pickup_lib_message.plural',[hold_list, obj.data.hash.aou[pickup_lib].shortname()]);
								} else {
									msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_pickup_lib.change_pickup_lib_message.singular',[hold_list, obj.data.hash.aou[pickup_lib].shortname()]);
								}
								var r = obj.error.yns_alert(msg,
										$("patronStrings").getString('staff.patron.holds.holds_edit_pickup_lib.change_pickup_lib_title'),
										$("commonStrings").getString('common.yes'),
										$("commonStrings").getString('common.no'),
										null,
										$("commonStrings").getString('common.check_to_confirm')
								);
								if (r == 0) {
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
										hold.pickup_lib(  pickup_lib ); hold.ischanged('1');
                                        hold = obj.flatten_copy(hold);
										var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
									obj.clear_and_retrieve(true);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_not_modified'),E);
							}
						}
					],
					'cmd_holds_edit_phone_notify' : [
						['command'],
						function() {
							try {
								var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								xml += '<description>'+$("patronStrings").getString('staff.patron.holds.holds_edit_phone_notify.new_phone_number')+'</description>';
								xml += '<textbox id="phone" name="fancy_data"/>';
								xml += '</vbox>';
								var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								bot_xml += '<spacer flex="1"/><button label="'+$("patronStrings").getString('staff.patron.holds.holds_edit_phone_notify.btn_done.label')+'"';
								bot_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_phone_notify.btn_done.accesskey')+'" name="fancy_submit"/>';
								bot_xml += '<button label="'+$("patronStrings").getString('staff.patron.holds.holds_edit_phone_notify.btn_cancel.label')+'"';
								bot_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_phone_notify.btn_cancel.accesskey')+'" name="fancy_cancel"/></hbox>';
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
									{ 'xml' : xml, 'bottom_xml' : bot_xml, 'title' : $("patronStrings").getString('staff.patron.holds.holds_edit_phone_notify.choose_phone_number'), 'focus' : 'phone' }
								);
								if (fancy_prompt_data.fancy_status == 'incomplete') { return; }
								var phone = fancy_prompt_data.phone;

								var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;}).join(', ');
								var msg = '';
								if(obj.retrieve_ids.length > 1) {
									msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_phone_notify.confirm_phone_number_change.plural',[hold_list, phone]);
								} else {
									msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_phone_notify.confirm_phone_number_change.singular',[hold_list, phone]);
								}
								var r = obj.error.yns_alert(msg,
										$("patronStrings").getString('staff.patron.holds.holds_edit_phone_notify.modifying_holds_title'),
										$("commonStrings").getString('common.yes'),
										$("commonStrings").getString('common.no'),
										null,
										$("commonStrings").getString('common.check_to_confirm')
								);
								if (r == 0) {
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
										hold.phone_notify(  phone ); hold.ischanged('1');
                                        hold = obj.flatten_copy(hold);
										var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
									obj.clear_and_retrieve(true);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_not_modified'),E);
							}
						}
					],
					'cmd_holds_edit_email_notify' : [
						['command'],
						function() {
							try {
								var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								xml += '<description>'+$("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.description')+'</description>';
								xml += '<hbox><button value="email" label="'+$("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.btn_email.label')+'"';
								xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.btn_email.accesskey')+'" name="fancy_submit"/>';
								xml += '<button value="noemail" label="'+$("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.btn_no_email.label')+'"';
								xml += '  accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.btn_no_email.accesskey')+'" name="fancy_submit"/></hbox>';
								xml += '</vbox>';
								var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
								bot_xml += '<spacer flex="1"/><button label="'+$("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.btn_cancel.label')+'"';
								bot_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.btn_cancel.accesskey')+'" name="fancy_cancel"/></hbox>';
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
									{ 'xml' : xml, 'bottom_xml' : bot_xml, 'title' : $("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.set_notifs') }
								);
								if (fancy_prompt_data.fancy_status == 'incomplete') { return; }
								var email = fancy_prompt_data.fancy_submit == 'email' ? get_db_true() : get_db_false();

								var hold_list = util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ');
								var msg = '';
								if(get_bool(email)) {
									if(obj.retrieve_ids.length > 1) {
										msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_email_notify.enable_email.plural', [hold_list]);
									} else {
										msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_email_notify.enable_email.singular', [hold_list]);
									}
								} else {
									if(obj.retrieve_ids.length > 1) {
										msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_email_notify.disable_email.plural', [hold_list]);
									} else {
										msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_email_notify.disable_email.singular', [hold_list]);
									}
								}
										
								var r = obj.error.yns_alert(msg,
										$("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.mod_holds_title'),
										$("commonStrings").getString('common.yes'),
										$("commonStrings").getString('common.no'),
										null,
										$("commonStrings").getString('common.check_to_confirm')
								);
								if (r == 0) {
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
										hold.email_notify(  email ); hold.ischanged('1');
                                        hold = obj.flatten_copy(hold);
										var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
									obj.clear_and_retrieve(true);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_not_modified'),E);
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
                                    document.getElementById('circStrings').getFormattedString('staff.circ.holds.suspend.prompt.plural',[hold_list]) :
                                    document.getElementById('circStrings').getFormattedString('staff.circ.holds.suspend.prompt',[hold_list]),
                                    document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds'),
                                    document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds.yes'),
                                    document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds.no'),
                                    null,
                                    document.getElementById('commonStrings').getString('common.confirm')
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
                                        alert( document.getElementById('circStrings').getFormattedString('staff.circ.holds.already_suspended',[already_suspended[0]]) );
                                    } else if (already_suspended.length > 1) {
                                        alert( document.getElementById('circStrings').getFormattedString('staff.circ.holds.already_suspended.plural',[already_suspended.join(', ')]) );
                                    }
									obj.clear_and_retrieve(true);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.holds.unexpected_error.not_likely_suspended'),E);
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
                                    document.getElementById('circStrings').getFormattedString('staff.circ.holds.activate.prompt.plural',[hold_list]) :
                                    document.getElementById('circStrings').getFormattedString('staff.circ.holds.activate.prompt',[hold_list]),
                                    document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds'),
                                    document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds.yes'),
                                    document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds.no'),
                                    null,
                                    document.getElementById('commonStrings').getString('common.confirm')
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
                                        alert( document.getElementById('circStrings').getFormattedString('staff.circ.holds.already_activated',[already_activated[0]]) );
                                    } else if (already_activated.length > 1) {
                                        alert( document.getElementById('circStrings').getFormattedString('staff.circ.holds.already_activated.plural',[already_activated.join(', ')]) );
                                    }
									obj.clear_and_retrieve(true);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.holds.unexpected_error.not_likely_activated'),E);
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
                                        if (! util.date.check('YYYY-MM-DD',value) ) { throw(document.getElementById('circStrings').getString('staff.circ.holds.activation_date.invalid_date')); }
                                        if (util.date.check_past('YYYY-MM-DD',value) || util.date.formatted_date(new Date(),'%F') == value ) { 
                                            throw(document.getElementById('circStrings').getString('staff.circ.holds.activation_date.too_early.error'));
                                        }
                                        return true;
                                    } catch(E) {
                                        alert(E);
                                        return false;
                                    }
                                }

                                var hold_ids = util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ');
								var msg_singular = document.getElementById('circStrings').getFormattedString('staff.circ.holds.activation_date.prompt',[hold_ids]);
								var msg_plural = document.getElementById('circStrings').getFormattedString('staff.circ.holds.activation_date.prompt',[hold_ids]);
                                var msg = obj.retrieve_ids.length > 1 ? msg_plural : msg_singular;
                                var value = 'YYYY-MM-DD';
                                var title = document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds');
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
                                        hold.frozen('t');
                                        hold.thaw_date(  thaw_date == '' ? null : util.date.formatted_date(thaw_date + ' 00:00:00','%{iso8601}') ); hold.ischanged('1');
                                        hold = obj.flatten_copy(hold);
                                        var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
                                        if (typeof robj.ilsevent != 'undefined') throw(robj);
                                    }
									obj.clear_and_retrieve(true);
                                }
							} catch(E) {
								obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.holds.unexpected_error.not_likely_modified'),E);
							}
						}
					],
                    'cmd_holds_edit_expire_time' : [
						['command'],
						function() {
							try {
                                JSAN.use('util.date');
                                function check_date(value) {
                                    try {
                                        if (! util.date.check('YYYY-MM-DD',value) ) { throw(document.getElementById('circStrings').getString('staff.circ.holds.expire_time.invalid_date')); }
                                        if (util.date.check_past('YYYY-MM-DD',value) || util.date.formatted_date(new Date(),'%F') == value ) { 
                                            throw(document.getElementById('circStrings').getString('staff.circ.holds.expire_time.too_early.error'));
                                        }
                                        return true;
                                    } catch(E) {
                                        alert(E);
                                        return false;
                                    }
                                }

                                var hold_ids = util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ');
								var msg_singular = document.getElementById('circStrings').getFormattedString('staff.circ.holds.expire_time.prompt',[hold_ids]);
								var msg_plural = document.getElementById('circStrings').getFormattedString('staff.circ.holds.expire_time.prompt',[hold_ids]);
                                var msg = obj.retrieve_ids.length > 1 ? msg_plural : msg_singular;
                                var value = 'YYYY-MM-DD';
                                var title = document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds');
								var expire_time; var invalid = true;
                                while(invalid) {
                                    expire_time = window.prompt(msg,value,title);
                                    if (expire_time) {
                                        invalid = ! check_date(expire_time);
                                    } else { 
                                        invalid = false;
                                    }
                                }
                                if (expire_time || expire_time == '') {
                                    for (var i = 0; i < obj.retrieve_ids.length; i++) {
                                        var hold = obj.holds_map[ obj.retrieve_ids[i].id ];
                                        hold.expire_time(  expire_time == '' ? null : util.date.formatted_date(expire_time + ' 00:00:00','%{iso8601}') ); hold.ischanged('1');
                                        hold = obj.flatten_copy(hold);
                                        var robj = obj.network.simple_request('FM_AHR_UPDATE',[ ses(), hold ]);
                                        if (typeof robj.ilsevent != 'undefined') throw(robj);
                                    }
									obj.clear_and_retrieve(true);
                                }
							} catch(E) {
								obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.holds.unexpected_error.not_likely_modified'),E);
							}
						}
					],



					'cmd_holds_retarget' : [
						['command'],
						function() {
							try {
								JSAN.use('util.functional');

								var hold_list = util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ');
								var msg = '';
								if(obj.retrieve_ids.length > 1) {
									msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_retarget.reset_hold_message.plural',[hold_list]);
								} else {
									msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_retarget.reset_hold_message.singular',[hold_list]);
								}
								var r = obj.error.yns_alert(msg,
										$("patronStrings").getString('staff.patron.holds.holds_retarget.reset_hold_title'),
										$("commonStrings").getString('common.yes'),
										$("commonStrings").getString('common.no'),
										null,
										$("commonStrings").getString('common.check_to_confirm')
								);
								if (r == 0) {
									for (var i = 0; i < obj.retrieve_ids.length; i++) {
										var robj = obj.network.simple_request('FM_AHR_RESET',[ ses(), obj.retrieve_ids[i].id]);
										if (typeof robj.ilsevent != 'undefined') throw(robj);
									}
									obj.clear_and_retrieve();
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_retarget.holds_not_reset'),E);
							}

						}
					],

					'cmd_holds_cancel' : [
						['command'],
						function() {
							try {
								JSAN.use('util.functional');

								var hold_list = util.functional.map_list( obj.retrieve_ids, function(o){return o.id;}).join(', ');
								var msg = '';
								if(obj.retrieve_ids.length > 1 ) {
									msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_cancel.cancel_hold_message.plural', [hold_list]);
								} else {
									msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_cancel.cancel_hold_message.singular', [hold_list]);
								}
								var r = obj.error.yns_alert(msg,
										$("patronStrings").getString('staff.patron.holds.holds_cancel.cancel_hold_title'),
										$("commonStrings").getString('common.yes'),
										$("commonStrings").getString('common.no'),
										null,
										$("commonStrings").getString('common.check_to_confirm')
								);
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
                                        var msg2 = $("patronStrings").getFormattedString('staff.patron.holds.holds_cancel.cancel_for_barcodes', [transits.join(', ')]);
                                        var r2 = obj.error.yns_alert(msg2,
                                            $("patronStrings").getString('staff.patron.holds.holds_cancel.cancel_for_barcodes.title'),
                                            $("commonStrings").getString('common.yes'),
                                            $("commonStrings").getString('common.no'),
											null,
                                            $("commonStrings").getString('common.check_to_confirm'));
                                        if (r2 == 0) {
                                            try {
                                                for (var i = 0; i < transits.length; i++) {
                                                    var robj = obj.network.simple_request('FM_ATC_VOID',[ ses(), { 'barcode' : transits[i] } ]);
                                                    if (typeof robj.ilsevent != 'undefined') {
                                                        switch(Number(robj.ilsevent)) {
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
                                               obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_cancel.hold_transits_not_cancelled'),E);
                                            }
                                        }
                                    }
									obj.clear_and_retrieve();
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_cancel.hold_not_cancelled'),E);
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
											var my_acn = obj.network.simple_request( 'FM_ACN_RETRIEVE.authoritative', [ htarget ]);
											opac_url = xulG.url_prefix( urls.opac_rdetail) + '?r=' + my_acn.record();
										break;
										case 'C' :
											var my_acp = obj.network.simple_request( 'FM_ACP_RETRIEVE', [ htarget ]);
											var my_acn;
											if (typeof my_acp.call_number() == 'object') {
												my_acn = my.acp.call_number();
											} else {
												my_acn = obj.network.simple_request( 'FM_ACN_RETRIEVE.authoritative', 
													[ my_acp.call_number() ]);
											}
											opac_url = xulG.url_prefix( urls.opac_rdetail) + '?r=' + my_acn.record();
										break;
										default:
											obj.error.standard_unexpected_error_alert($("patronStrings").getFormattedString('staff.patron.holds.show_catalog.unknown_htype', [htype]), obj.retrieve_ids[i]);
											continue;
										break;
									}
									var content_params = { 
										'session' : ses(),
										'authtime' : ses('authtime'),
										'opac_url' : opac_url
									};
									xulG.new_tab(
										xulG.url_prefix(urls.XUL_OPAC_WRAPPER), 
										{'tab_name': htype == 'M' ? 'Catalog' : $("patronStrings").getString('staff.patron.holds.show_catalog.retrieving_title') },
										content_params
									);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('',E);
							}
						}
					],
                    'fetch_more' : [
                        ['command'],
                        function() {
                            obj.pull_from_shelf_interface.current.offset += obj.pull_from_shelf_interface.current.limit;
                            obj.retrieve(true);
                        }
                    ],
                    'lib_filter_checkbox' : [
                        ['command'],
                        function(ev) {
                            var x_lib_type_menu = document.getElementById('lib_type_menu');
                            if (x_lib_type_menu) x_lib_type_menu.disabled = ! ev.target.checked;
                            if (obj.controller.view.lib_menu) obj.controller.view.lib_menu.disabled = ! ev.target.checked;
                            obj.clear_and_retrieve();
                            ev.target.setAttribute('checked',ev.target.checked);
                        }
                    ]
				}
			}
		);
        
        obj.determine_hold_interface_type();
        var x_fetch_more = document.getElementById('fetch_more');
        var x_lib_type_menu = document.getElementById('lib_type_menu');
        var x_lib_menu_placeholder = document.getElementById('lib_menu_placeholder');
        var x_lib_filter_checkbox = document.getElementById('lib_filter_checkbox');
        switch(obj.hold_interface_type) {
            case 'shelf':
                obj.render_lib_menus({'pickup_lib':true});
                if (x_lib_type_menu) x_lib_type_menu.hidden = false;
                if (x_lib_menu_placeholder) x_lib_menu_placeholder.hidden = false;
            break;
            case 'pull' :
                if (x_fetch_more) x_fetch_more.hidden = false;
                if (x_lib_type_menu) x_lib_type_menu.hidden = true;
                if (x_lib_menu_placeholder) x_lib_menu_placeholder.hidden = true;
            break;
            case 'record' :
                obj.render_lib_menus({'pickup_lib':true,'request_lib':true});
                if (x_lib_filter_checkbox) x_lib_filter_checkbox.hidden = false;
                if (x_lib_type_menu) x_lib_type_menu.hidden = false;
                if (x_lib_menu_placeholder) x_lib_menu_placeholder.hidden = false;
            break;
            default:
                if (x_fetch_more) x_fetch_more.hidden = true;
                if (x_lib_type_menu) x_lib_type_menu.hidden = true;
                if (x_lib_menu_placeholder) x_lib_menu_placeholder.hidden = true;
            break;
        }
        setTimeout( // We do this because render_lib_menus above creates and appends a DOM node, but until this thread exits, it doesn't really happen
            function() {
                if (x_lib_filter_checkbox) if (!x_lib_filter_checkbox.checked) {
                    if (x_lib_type_menu) x_lib_type_menu.disabled = true;
                    if (obj.controller.view.lib_menu) obj.controller.view.lib_menu.disabled = true;
                }
                obj.controller.render();
                obj.retrieve(true);

                obj.controller.view.cmd_retrieve_patron.setAttribute('disabled','true');
                obj.controller.view.cmd_holds_edit_pickup_lib.setAttribute('disabled','true');
                obj.controller.view.cmd_holds_edit_phone_notify.setAttribute('disabled','true');
                obj.controller.view.cmd_holds_edit_email_notify.setAttribute('disabled','true');
				obj.controller.view.cmd_holds_edit_thaw_date.setAttribute('disabled','true');
				obj.controller.view.cmd_holds_activate.setAttribute('disabled','true');
				obj.controller.view.cmd_holds_suspend.setAttribute('disabled','true');
                obj.controller.view.cmd_holds_edit_selection_depth.setAttribute('disabled','true');
                obj.controller.view.cmd_show_notifications.setAttribute('disabled','true');
                obj.controller.view.cmd_holds_retarget.setAttribute('disabled','true');
                obj.controller.view.cmd_holds_cancel.setAttribute('disabled','true');
                obj.controller.view.cmd_show_catalog.setAttribute('disabled','true');
            }, 0
        );
	},

    'determine_hold_interface_type' : function() {
		var obj = this;
        if (obj.patron_id) { /*************************************************** PATRON ******************************/
            obj.hold_interface_type = 'patron';
		} else if (obj.docid) { /*************************************************** RECORD ******************************/
            obj.hold_interface_type = 'record';
		} else if (obj.pull) { /*************************************************** PULL ******************************/
            obj.hold_interface_type = 'pull';
		} else if (obj.shelf) { /*************************************************** HOLD SHELF ******************************/
            obj.hold_interface_type = 'shelf';
		} else { /*************************************************** PULL ******************************/
            obj.hold_interface_type = 'pull';
		}
    },

    'clear_and_retrieve' : function(dont_show_me_the_list_change) {
        this.list.clear();
        this.pull_from_shelf_interface.current.offset = this.pull_from_shelf_interface._default.offset;
        this.retrieve(dont_show_me_the_list_change);
    },

	'retrieve' : function(dont_show_me_the_list_change) {
		var obj = this; var holds = [];
		if (window.xulG && window.xulG.holds) {
			holds = window.xulG.holds;
		} else {
			var method; var params = [ ses() ];
            switch(obj.hold_interface_type) {
                case 'patron' :
				    method = 'FM_AHR_ID_LIST_RETRIEVE_VIA_AU.authoritative'; 
    				params.push( obj.patron_id ); 
    				obj.controller.view.cmd_retrieve_patron.setAttribute('hidden','true');
                break;
                case 'record' :
				    method = 'FM_AHR_RETRIEVE_ALL_VIA_BRE'; 
    				params.push( obj.docid ); 
                    var x_lib_filter = document.getElementById('lib_filter_checkbox');
                    var x_lib_type_menu = document.getElementById('lib_type_menu');
                    if (x_lib_filter) {
                        if (x_lib_filter.checked) {
                            if (x_lib_type_menu && obj.controller.view.lib_menu) {
                                var x = {};
                                x[ x_lib_type_menu.value ] = obj.controller.view.lib_menu.value;
                                params.push( x );
                            }
                        }
                    }
    				obj.controller.view.cmd_retrieve_patron.setAttribute('hidden','false');
                break;
                case 'shelf' : 
				    method = 'FM_AHR_ID_LIST_ONSHELF_RETRIEVE';
                    params.push( obj.filter_lib || obj.data.list.au[0].ws_ou() ); 
    				obj.controller.view.cmd_retrieve_patron.setAttribute('hidden','false');
                break;
                case 'pull' : 
                default:
				    method = 'FM_AHR_ID_LIST_PULL_LIST'; 
    				params.push( obj.pull_from_shelf_interface.current.limit ); params.push( obj.pull_from_shelf_interface.current.offset );
				    //obj.controller.view.cmd_retrieve_patron.setAttribute('hidden','false');
                break;
			}
			var robj = obj.network.simple_request( method, params );
			if (robj != null && typeof robj.ilsevent != 'undefined') throw(robj);
			if (method == 'FM_AHR_RETRIEVE_ALL_VIA_BRE') {
				holds = [];
                if (robj != null) {
                    holds = holds.concat( robj.copy_holds );
                    holds = holds.concat( robj.volume_holds );
                    holds = holds.concat( robj.title_holds );
                    holds = holds.sort();
                }
			} else {
				holds = robj == null ? [] : robj;
			}
			//alert('method = ' + method + ' params = ' + js2JSON(params));
		}

        var x_fetch_more = document.getElementById('fetch_more');
        if (holds.length == 0) {
            if (x_fetch_more) x_fetch_more.disabled = true;
        } else {
            if (x_fetch_more) x_fetch_more.disabled = false;
            obj.render(holds,dont_show_me_the_list_change);
        }

    },

    'render' : function(holds,dont_show_me_the_list_change) {
        var obj = this;

		function list_append(hold_id) {
			obj.list.append(
				{
					'row' : {
						'my' : {
							'hold_id' : hold_id
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
					list_append(typeof hold == 'object' ? hold.id() : hold);
				}
			};
		}

		//obj.list.clear();

		JSAN.use('util.exec'); var exec = new util.exec(2);
		var rows = [];
		for (var i in holds) {
			rows.push( gen_list_append(holds[i]) );
		}
		exec.chain( rows );
	
		if (!dont_show_me_the_list_change) {
			if (window.xulG && typeof window.xulG.on_list_change == 'function') {
				try { window.xulG.on_list_change(holds); } catch(E) { this.error.sdump('D_ERROR',E); }
			}
		}
	},

	'render_lib_menus' : function(types) {
		try {
			var obj = this;
			JSAN.use('util.widgets'); JSAN.use('util.functional'); JSAN.use('util.fm_utils');

            var x = document.getElementById('lib_type_menu');
            if (types) {
                var nodes = x.firstChild.childNodes;
                for (var i = 0; i < nodes.length; i++) nodes[i].hidden = true;
                for (var i in types) document.getElementById(i).hidden = false;
            }
            x.setAttribute('oncommand','g.holds.clear_and_retrieve()');

			x = document.getElementById('lib_menu_placeholder');
			util.widgets.remove_children( x );

            JSAN.use('util.file');
			var file = new util.file('offline_ou_list'); 
			if (file._file.exists()) {
				var list_data = file.get_object(); file.close();
				var ml = util.widgets.make_menulist( list_data[0], obj.data.list.au[0].ws_ou() );
                ml.setAttribute('id','lib_menu');
                x.appendChild( ml );
    			ml.addEventListener(
    				'command',
    				function(ev) {
    					obj.filter_lib = ev.target.value;
    					obj.clear_and_retrieve();
    				},
    				false
    			);
    			obj.controller.view.lib_menu = ml;
			} else {
				throw($("patronStrings").getString('staff.patron.holds.lib_menus.missing_library_list'));
			}

		} catch(E) {
			this.error.standard_unexpected_error_alert('rendering lib menu',E);
		}
	}
}

dump('exiting patron.holds.js\n');
