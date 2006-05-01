dump('entering cat.copy_buckets.js\n');

if (typeof cat == 'undefined') cat = {};
cat.copy_buckets = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('util.date');
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
}

cat.copy_buckets.prototype = {
	'selection_list1' : [],
	'selection_list2' : [],
	'bucket_id_name_map' : {},

	'render_pending_copies' : function() {
		var obj = this;
		obj.list1.clear();
		for (var i = 0; i < obj.copy_ids.length; i++) {
			var item = obj.flesh_item_for_list( obj.copy_ids[i] );
			if (item) obj.list1.append( item );
		}
	},

	'init' : function( params ) {

		var obj = this;

		obj.copy_ids = params['copy_ids'] || [];

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

		JSAN.use('util.list'); 

		obj.list1 = new util.list('pending_copies_list');
		obj.list1.init(
			{
				'columns' : columns,
				'map_row_to_column' : circ.util.std_map_row_to_column(),
				'on_select' : function(ev) {
					try {
						JSAN.use('util.functional');
						var sel = obj.list1.retrieve_selection();
						obj.selection_list1 = util.functional.map_list(
							sel,
							function(o) { return JSON2js(o.getAttribute('retrieve_id')); }
						);
						obj.error.sdump('D_TRACE','circ/copy_buckets: selection list 1 = ' + js2JSON(obj.selection_list1) );
						if (obj.selection_list1.length == 0) {
							obj.controller.view.copy_buckets_sel_add.disabled = true;
						} else {
							obj.controller.view.copy_buckets_sel_add.disabled = false;
						}
					} catch(E) {
						alert('FIXME: ' + E);
					}
				},

			}
		);

		obj.render_pending_copies();
	
		obj.list2 = new util.list('copies_in_bucket_list');
		obj.list2.init(
			{
				'columns' : columns,
				'map_row_to_column' : circ.util.std_map_row_to_column(),
				'on_select' : function(ev) {
					try {
						JSAN.use('util.functional');
						var sel = obj.list2.retrieve_selection();
						obj.selection_list2 = util.functional.map_list(
							sel,
							function(o) { return JSON2js(o.getAttribute('retrieve_id')); }
						);
						obj.error.sdump('D_TRACE','circ/copy_buckets: selection list 2 = ' + js2JSON(obj.selection_list2) );
						if (obj.selection_list2.length == 0) {
							obj.controller.view.copy_buckets_delete_item.disabled = true;
						} else {
							obj.controller.view.copy_buckets_delete_item.disabled = false;
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
					'copy_buckets_menulist_placeholder' : [
						['render'],
						function(e) {
							return function() {
								JSAN.use('util.widgets'); JSAN.use('util.functional');
								var items = [ ['Choose a bucket...',''] ].concat(
									util.functional.map_list(
										obj.network.simple_request(
											'BUCKET_RETRIEVE_VIA_USER',
											[ ses(), obj.data.list.au[0].id() ]
										).copy,
										function(o) {
											obj.bucket_id_name_map[ o.id() ] = o.name();
											return [ o.name(), o.id() ];
										}
									)
								);
								g.error.sdump('D_TRACE','items = ' + js2JSON(items));
								util.widgets.remove_children( e );
								var ml = util.widgets.make_menulist(
									items
								);
								e.appendChild( ml );
								ml.setAttribute('id','bucket_menulist');
								ml.setAttribute('accesskey','');

								function change_bucket(ev) {
									var bucket_id = ev.target.value;
									if (!bucket_id) return;
									var bucket = obj.network.simple_request(
										'BUCKET_FLESH',
										[ ses(), 'copy', bucket_id ]
									);
									var items = bucket.items() || [];
									obj.list2.clear();
									for (var i = 0; i < items.length; i++) {
										var item = obj.flesh_item_for_list( 
											items[i].target_copy(),
											items[i].id()
										);
										if (item) obj.list2.append( item );
									}
								}

								ml.addEventListener( 'change_bucket', change_bucket , false);
								ml.addEventListener( 'command', function() {
									JSAN.use('util.widgets'); util.widgets.dispatch('change_bucket',ml);
								}, false);
								obj.controller.view.bucket_menulist = ml;
								JSAN.use('util.widgets'); util.widgets.dispatch('change_bucket',ml);
							};
						},
					],

					'copy_buckets_add' : [
						['command'],
						function() {
							var bucket_id = obj.controller.view.bucket_menulist.value;
							if (!bucket_id) return;
							for (var i = 0; i < obj.copy_ids.length; i++) {
								var bucket_item = new ccbi();
								bucket_item.isnew('1');
								bucket_item.bucket(bucket_id);
								bucket_item.target_copy( obj.copy_ids[i] );
								try {
									var robj = obj.network.simple_request('BUCKET_ITEM_CREATE',
										[ ses(), 'copy', bucket_item ]);

									if (typeof robj == 'object') throw robj;

									var item = obj.flesh_item_for_list( obj.copy_ids[i], robj );
									if (!item) continue;

									obj.list2.append( item );
								} catch(E) {
									obj.error.standard_unexpected_error_alert('Addition likely failed.',E);
								}
							}
						}
					],
					'copy_buckets_sel_add' : [
						['command'],
						function() {                                                        
							var bucket_id = obj.controller.view.bucket_menulist.value;
							if (!bucket_id) return;
							for (var i = 0; i < obj.selection_list1.length; i++) {
	                                                        var acp_id = obj.selection_list1[i][0];
								//var barcode = obj.selection_list1[i][1];
								var bucket_item = new ccbi();
								bucket_item.isnew('1');
								bucket_item.bucket(bucket_id);
								bucket_item.target_copy( acp_id );
								try {
									var robj = obj.network.simple_request('BUCKET_ITEM_CREATE',
										[ ses(), 'copy', bucket_item ]);

									if (typeof robj == 'object') throw robj;

									var item = obj.flesh_item_for_list( acp_id, robj );
									if (!item) continue;

									obj.list2.append( item );
								} catch(E) {
									obj.error.standard_unexpected_error_alert('Deletion likely failed.',E);
								}
							}

						}
					],
					'copy_buckets_export' : [
						['command'],
						function() {                                                        
							for (var i = 0; i < obj.selection_list2.length; i++) {
	                                                        var acp_id = obj.selection_list2[i][0];
								//var barcode = obj.selection_list1[i][1];
								//var bucket_item_id = obj.selection_list1[i][2];
								var item = obj.flesh_item_for_list( acp_id );
								if (item) {
									obj.list1.append( item );
									obj.copy_ids.push( acp_id );
								}
							}
						}
					],

					'copy_buckets_delete_item' : [
						['command'],
						function() {
                                                        for (var i = 0; i < obj.selection_list2.length; i++) {
								try {
	                                                                //var acp_id = obj.selection_list2[i][0];
									//var barcode = obj.selection_list2[i][1];
									var bucket_item_id = obj.selection_list2[i][2];
									var robj = obj.network.simple_request('BUCKET_ITEM_DELETE',
										[ ses(), 'copy', bucket_item_id ]);
									if (typeof robj == 'object') throw robj;
								} catch(E) {
									obj.error.standard_unexpected_error_alert('Deletion likely failed.',E);
								}
                                                        }
							setTimeout(
								function() {
									JSAN.use('util.widgets'); 
									util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
								}, 0
							);
						}
					],
					'copy_buckets_delete_bucket' : [
						['command'],
						function() {
							try {
								var bucket = obj.controller.view.bucket_menulist.value;
								var name = obj.bucket_id_name_map[ bucket ];
								var conf = window.confirm('Delete the bucket named ' + name + '?');
								if (!conf) return;
								obj.list2.clear();
								var robj = obj.network.simple_request('BUCKET_DELETE',[ses(),'copy',bucket]);
								if (typeof robj == 'object') throw robj;
								obj.controller.render('copy_buckets_menulist_placeholder');
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Bucket deletion likely failed.',E);
							}
						}
					],
					'copy_buckets_new_bucket' : [
						['command'],
						function() {
							try {
								var name = prompt('What would you like to name the bucket?','','Bucket Creation');

								if (name) {
									var bucket = new ccb();
									bucket.btype('staff_client');
									bucket.owner( obj.data.list.au[0].id() );
									bucket.name( name );

									var robj = obj.network.simple_request('BUCKET_CREATE',[ses(),'copy',bucket]);

									if (typeof robj == 'object') throw robj;

									obj.controller.render('copy_buckets_menulist_placeholder');
									obj.controller.view.bucket_menulist.value = robj;
									setTimeout(
										function() {
											JSAN.use('util.widgets'); 
											util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
										}, 0
									);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Bucket creation failed.',E);
							}
						}
					],
					'copy_buckets_batch_copy_edit' : [
						['command'],
						function() {
							try {
								JSAN.use('util.functional');
								JSAN.use('util.window'); var win = new util.window();
								win.open(
									urls.XUL_COPY_EDITOR 
									+ '?copy_ids=' + window.escape( js2JSON(
										util.functional.map_list(
											obj.list2.dump_retrieve_ids(),
											function (o) {
												return JSON2js(o)[0]; // acp_id
											}
										)
									) )
									+ '&single_edit=1'
									+ '&handle_update=1',
									'batch_copy_editor_win_' + win.window_name_increment(),
									'chrome,resizable,modal'
								);
								obj.render_pending_copies(); // FIXME -- need a generic refresh for lists
								setTimeout(
									function() {
										JSAN.use('util.widgets'); 
										util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
									}, 0
								);
							} catch(E) {
								alert( js2JSON(E) );
							}
						}
					],
					'copy_buckets_transfer_to_volume' : [
						['command'],
						function() {
							try {
								// FM_ACN_RETRIEVE
								obj.data.stash_retrieve();
								if (!obj.data.marked_volume) {
									alert('Please mark a volume as the destination from within the copy browser and then try this again.');
									return;
								}
								var volume = obj.network.simple_request('FM_ACN_RETRIEVE',[ obj.data.marked_volume ]);
								netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
								var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: auto">';
								xml += '<description>Transfer the copies in bucket "';
								xml += obj.controller.view.bucket_menulist.getAttribute('label') + '" ';
								xml += 'from their original volumes to ';
								xml += obj.data.hash.aou[ volume.owning_lib() ].shortname() + "'s volume labelled ";
								xml += '"' + volume.label() + '" on the following record?</description>';
								xml += '<hbox><button label="Transfer" name="fancy_submit"/>';
								xml += '<button label="Cancel" accesskey="C" name="fancy_cancel"/></hbox>';
								xml += '<iframe style="overflow: scroll" flex="1" src="' + xulG.url_prefix( urls.XUL_BIB_BRIEF ) + '?docid=' + volume.record() + '"/>';
								xml += '</vbox>';
								obj.data.temp_transfer = xml; obj.data.stash('temp_transfer');
								window.open(
									urls.XUL_FANCY_PROMPT
									+ '?xml_in_stash=temp_transfer'
									+ '&title=' + window.escape('Copy Transfer'),
									'fancy_prompt', 'chrome,resizable,modal,width=500,height=300'
								);
								JSAN.use('OpenILS.data');
								var data = new OpenILS.data(); data.init({'via':'stash'});
								if (data.fancy_prompt_data == '') { alert('Transfer Aborted'); return; }

								JSAN.use('util.functional');

								var copies = obj.network.simple_request('FM_ACP_FLESHED_BATCH_RETRIEVE', [
									util.functional.map_list(
										obj.list2.dump_retrieve_ids(),
										function (o) {
											return JSON2js(o)[0]; // acp_id
										}
									)
								]);

								for (var i = 0; i < copies.length; i++) {
									copies[i].call_number( obj.data.marked_volume );
									copies[i].ischanged( 1 );
								}

								var robj = obj.network.simple_request('FM_ACP_FLESHED_BATCH_UPDATE', [ ses(), copies ]);

								obj.render_pending_copies(); // FIXME -- need a generic refresh for lists
								setTimeout(
									function() {
										JSAN.use('util.widgets'); 
										util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
									}, 0
								);
								
								if (typeof robj.ilsevent != 'undefined') {
									throw(robj);
								} else {
									alert('Copies transferred.');
								}

							} catch(E) {
								obj.error.standard_unexpected_error_alert('Copies not likely transferred.',E);
							}
						}
					],
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_copy_buckets_print' : [
						['command'],
						function() {
							dump( js2JSON( obj.list2.dump() ) );
							alert( js2JSON( obj.list2.dump() ) );
						}
					],
					'cmd_copy_buckets_reprint' : [
						['command'],
						function() {
						}
					],
					'cmd_copy_buckets_done' : [
						['command'],
						function() {
							window.close();
						}
					],
					'cmd_export_to_copy_status' : [
						['command'],
						function() {
							try {
								JSAN.use('util.functional');
								var barcodes = util.functional.map_list(
									obj.list2.dump_retrieve_ids(),
									function(o) { return JSON2js(o)[1]; }
								);
								var url = urls.XUL_COPY_STATUS + '?barcodes=' + window.escape( js2JSON(barcodes) );
								xulG.new_tab( url, {}, {});
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Copy Status from Copy Buckets',E);
							}
						}
					],
				}
			}
		);
		this.controller.render();

	},

	'flesh_item_for_list' : function(acp_id,bucket_item_id) {
		var obj = this;
		try {
			var copy = obj.network.simple_request( 'FM_ACP_RETRIEVE', [ acp_id ]);
			if (copy == null || typeof copy.ilsevent != 'undefined') {
				throw(copy);
			} else {
				var item = {
					'retrieve_id' : js2JSON( [ copy.id(), copy.barcode(), bucket_item_id ] ),
					'row' : {
						'my' : {
							'mvr' : obj.network.simple_request('MODS_SLIM_RECORD_RETRIEVE_VIA_COPY', [ copy.id() ]),
							'acp' : copy,
						}
					}
				};
				return item;
			}
		} catch(E) {
			obj.error.standard_unexpected_error_alert('List building failed.',E);
			return null;
		}

	},
	
}

dump('exiting cat.copy_buckets.js\n');
