dump('entering cat.record_buckets.js\n');

if (typeof cat == 'undefined') cat = {};
cat.record_buckets = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('util.date');
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
}

cat.record_buckets.prototype = {
	'selection_list1' : [],
	'selection_list2' : [],
	'bucket_id_name_map' : {},

	'render_pending_records' : function() {
		var obj = this;
		obj.list1.clear();
		for (var i = 0; i < obj.record_ids.length; i++) {
			var item = obj.flesh_item_for_list( obj.record_ids[i] );
			if (item) obj.list1.append( item );
		}
	},

	'init' : function( params ) {

		var obj = this;

		obj.record_ids = params['record_ids'] || [];

		JSAN.use('circ.util');
		var columns = circ.util.columns( 
			{ 
				'title' : { 'hidden' : false },
				'author' : { 'hidden' : false },
				'edition' : { 'hidden' : false },
				'publisher' : { 'hidden' : false },
				'pubdate' : { 'hidden' : false },
				'isbn' : { 'hidden' : false },
				'tcn' : { 'hidden' : false },
			} 
		);

		JSAN.use('util.list'); 

		obj.list1 = new util.list('pending_records_list');
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
						obj.error.sdump('D_TRACE','circ/record_buckets: selection list 1 = ' + js2JSON(obj.selection_list1) );
						if (obj.selection_list1.length == 0) {
							obj.controller.view.record_buckets_sel_add.disabled = true;
						} else {
							obj.controller.view.record_buckets_sel_add.disabled = false;
						}
					} catch(E) {
						alert('FIXME: ' + E);
					}
				},

			}
		);

		obj.render_pending_records();
	
		obj.list2 = new util.list('records_in_bucket_list');
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
						obj.error.sdump('D_TRACE','circ/record_buckets: selection list 2 = ' + js2JSON(obj.selection_list2) );
						if (obj.selection_list2.length == 0) {
							obj.controller.view.record_buckets_delete_item.disabled = true;
						} else {
							obj.controller.view.record_buckets_delete_item.disabled = false;
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
					'record_buckets_menulist_placeholder' : [
						['render'],
						function(e) {
							return function() {
								JSAN.use('util.widgets'); JSAN.use('util.functional');
								var buckets = obj.network.simple_request(
									'BUCKET_RETRIEVE_VIA_USER',
									[ ses(), obj.data.list.au[0].id() ]
								);
								if (typeof buckets.ilsevent != 'undefined') {
									obj.error.standard_unexpected_error_alert('Could not retrieve your buckets.',buckets);
									return;
								}
								var items = [ ['Choose a bucket...',''] ].concat(
									util.functional.map_list(
										util.functional.filter_list(
											buckets.biblio,
											function(o) {
												return o.btype() == 'staff_client';
											}
										),
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
										[ ses(), 'biblio', bucket_id ]
									);
									var items = bucket.items() || [];
									obj.list2.clear();
									for (var i = 0; i < items.length; i++) {
										var item = obj.flesh_item_for_list( 
											items[i].target_biblio_record_entry(),
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

					'record_buckets_add' : [
						['command'],
						function() {
							var bucket_id = obj.controller.view.bucket_menulist.value;
							if (!bucket_id) return;
							for (var i = 0; i < obj.record_ids.length; i++) {
								var bucket_item = new cbrebi();
								bucket_item.isnew('1');
								bucket_item.bucket(bucket_id);
								bucket_item.target_biblio_record_entry( obj.record_ids[i] );
								try {
									var robj = obj.network.simple_request('BUCKET_ITEM_CREATE',
										[ ses(), 'biblio', bucket_item ]);

									if (typeof robj == 'object') throw robj;

									var item = obj.flesh_item_for_list( obj.record_ids[i], robj );
									if (!item) continue;

									obj.list2.append( item );
								} catch(E) {
									alert( js2JSON(E) );
								}
							}
						}
					],
					'record_buckets_sel_add' : [
						['command'],
						function() {                                                        
							var bucket_id = obj.controller.view.bucket_menulist.value;
							if (!bucket_id) return;
							for (var i = 0; i < obj.selection_list1.length; i++) {
								var docid = obj.selection_list1[i].docid;
								var bucket_item = new cbrebi();
								bucket_item.isnew('1');
								bucket_item.bucket(bucket_id);
								bucket_item.target_biblio_record_entry( docid );
								try {
									var robj = obj.network.simple_request('BUCKET_ITEM_CREATE',
										[ ses(), 'biblio', bucket_item ]);

									if (typeof robj == 'object') throw robj;

									var item = obj.flesh_item_for_list( docid, robj );
									if (!item) continue;

									obj.list2.append( item );
								} catch(E) {
									alert( js2JSON(E) );
								}
							}

						}
					],
					'record_buckets_export' : [
						['command'],
						function() {                                                        
							for (var i = 0; i < obj.selection_list2.length; i++) {
								var docid = obj.selection_list2[i].docid;
								var item = obj.flesh_item_for_list( docid );
								if (item) {
									obj.list1.append( item );
									obj.record_ids.push( docid );
								}
							}
						}
					],

					'record_buckets_delete_item' : [
						['command'],
						function() {
							for (var i = 0; i < obj.selection_list2.length; i++) {
								try {
									var bucket_item_id = obj.selection_list2[i].bucket_item_id;
									var robj = obj.network.simple_request('BUCKET_ITEM_DELETE',
										[ ses(), 'biblio', bucket_item_id ]);
									if (typeof robj == 'object') throw robj;
								} catch(E) {
									alert(js2JSON(E));
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
					'record_buckets_delete_bucket' : [
						['command'],
						function() {
							try {
								var bucket = obj.controller.view.bucket_menulist.value;
								var name = obj.bucket_id_name_map[ bucket ];
								var conf = window.confirm('Delete the bucket named ' + name + '?');
								if (!conf) return;
								obj.list2.clear();
								var robj = obj.network.simple_request('BUCKET_DELETE',[ses(),'biblio',bucket]);
								if (typeof robj == 'object') throw robj;
								obj.controller.render('record_buckets_menulist_placeholder');
								setTimeout(
									function() {
										JSAN.use('util.widgets'); 
										util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
									}, 0
								);

							} catch(E) {
								alert('FIXME -- ' + E);
							}
						}
					],
					'record_buckets_new_bucket' : [
						['command'],
						function() {
							try {
								var name = prompt('What would you like to name the bucket?','','Bucket Creation');

								if (name) {
									var bucket = new ccb();
									bucket.btype('staff_client');
									bucket.owner( obj.data.list.au[0].id() );
									bucket.name( name );

									var robj = obj.network.simple_request('BUCKET_CREATE',[ses(),'biblio',bucket]);

									if (typeof robj == 'object') throw robj;

									obj.controller.render('record_buckets_menulist_placeholder');
									obj.controller.view.bucket_menulist.value = robj;
									setTimeout(
										function() {
											JSAN.use('util.widgets'); 
											util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
										}, 0
									);
								}
							} catch(E) {
								alert( js2JSON(E) );
							}
						}
					],
					'record_buckets_batch_record_edit' : [
						['command'],
						function() {
							try {
								JSAN.use('util.functional');
								JSAN.use('util.window'); var win = new util.window();
								win.open(
									urls.XUL_COPY_EDITOR 
									+ '?record_ids=' + window.escape( js2JSON(
										util.functional.map_list(
											obj.list2.dump_retrieve_ids(),
											function (o) {
												return JSON2js(o).docid; // docid
											}
										)
									) )
									+ '&single_edit=1'
									+ '&handle_update=1',
									'batch_record_editor_win_' + win.window_name_increment(),
									'chrome,resizable,modal'
								);
								setTimeout(
									function() {
										JSAN.use('util.widgets'); 
										util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
									}, 0
								);
								obj.render_pending_records(); // FIXME -- need a generic refresh for lists
							} catch(E) {
								alert( js2JSON(E) );
							}
						}
					],
					'cmd_merge_records' : [
						['command'],
						function() {
							try {
								obj.data.stash_retrieve();
								JSAN.use('util.functional');

								var record_ids = util.functional.map_list(
									obj.list2.dump_retrieve_ids(),
									function (o) {
										return JSON2js(o).docid; // docid
									}
								);

								netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
								var top_xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" >';
								top_xml += '<description>Merge these records? (Select the "lead" record first)</description>';
								top_xml += '<hbox><button id="lead" disabled="true" label="Merge" name="fancy_submit"/><button label="Cancel" accesskey="C" name="fancy_cancel"/></hbox></vbox>';

								var xml = '<form xmlns="http://www.w3.org/1999/xhtml">';
								xml += '<table><tr valign="top">';
								for (var i = 0; i < record_ids.length; i++) {
									xml += '<td><input value="Lead" id="record_' + record_ids[i] + '" type="radio" name="lead"';
									xml += ' onclick="' + "try { var x = document.getElementById('lead'); x.setAttribute('value',";
									xml += record_ids[i] + '); x.disabled = false; } catch(E) { alert(E); }">';
									xml += '</input>Lead Record? #' + record_ids[i] + '</td>';
								}
								xml += '</tr><tr valign="top">';
								for (var i = 0; i < record_ids.length; i++) {
									xml += '<td nowrap="nowrap"><iframe src="' + urls.XUL_BIB_BRIEF; 
									xml += '?docid=' + record_ids[i] + '"/></td>';
								}
								xml += '</tr><tr valign="top">';
								for (var i = 0; i < record_ids.length; i++) {
									html = obj.network.simple_request('MARC_HTML_RETRIEVE',[ record_ids[i] ]);
									xml += '<td nowrap="nowrap"><iframe style="min-height: 1000px; min-width: 300px;" flex="1" src="data:text/html,' + window.escape(html) + '"/></td>';
								}
								xml += '</tr></table></form>';
								obj.data.temp_merge_top = top_xml; obj.data.stash('temp_merge_top');
								obj.data.temp_merge_mid = xml; obj.data.stash('temp_merge_mid');
								window.open(
									urls.XUL_FANCY_PROMPT
									+ '?xml_in_stash=temp_merge_mid'
									+ '&top_xml_in_stash=temp_merge_top'
									+ '&title=' + window.escape('Record Merging'),
									'fancy_prompt', 'chrome,resizable,modal,width=700,height=500'
								);
								obj.data.stash_retrieve();
								if (obj.data.fancy_prompt_data == '') { alert('Merge Aborted'); return; }
								var robj = obj.network.simple_request('MERGE_RECORDS', 
									[ 
										ses(), 
										obj.data.fancy_prompt_data.lead, 
										util.functional.filter_list( record_ids,
											function(o) {
												return o != obj.data.fancy_prompt_data.lead;
											}
										)
									]
								);
								if (typeof robj.ilsevent != 'undefined') {
									throw(robj);
								} else {
									alert('Records were successfully merged.');
								}

								obj.render_pending_records(); // FIXME -- need a generic refresh for lists
								setTimeout(
									function() {
										JSAN.use('util.widgets'); 
										util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
									}, 0
								);
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Records were not likely merged.',E);
							}

						}
					],
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_record_buckets_print' : [
						['command'],
						function() {
							dump( js2JSON( obj.list2.dump() ) );
							alert( js2JSON( obj.list2.dump() ) );
						}
					],
					'cmd_record_buckets_reprint' : [
						['command'],
						function() {
						}
					],
					'cmd_record_buckets_done' : [
						['command'],
						function() {
							window.close();
						}
					],
					'cmd_sel_opac' : [
						['command'],
						function() {
							try {
								JSAN.use('util.functional');
								var docids = util.functional.map_list(
									obj.list2.dump_retrieve_ids(),
									function (o) {
										return JSON2js(o).docid; // docid
									}
								);
								for (var i = 0; i < docids.length; i++) {
									var doc_id = docids[i];
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
								obj.error.standard_unexpected_error_alert('Showing in OPAC',E);
							}
						}
					],

				}
			}
		);
		this.controller.render();

		if (typeof xulG == 'undefined') {
			obj.controller.view.cmd_sel_opac.disabled = true;
			obj.controller.view.cmd_sel_opac.setAttribute('disabled',true);
		} else {
			obj.controller.view.cmd_record_buckets_done.disabled = true;
			obj.controller.view.cmd_record_buckets_done.setAttribute('disabled',true);
		}
	},

	'flesh_item_for_list' : function(docid,bucket_item_id) {
		var obj = this;
		try {
			var record = obj.network.simple_request( 'MODS_SLIM_RECORD_RETRIEVE', [ docid ]);
			if (record == null || typeof(record.ilsevent) != 'undefined') {
				throw(record);
			} else {
				var item = {
					'retrieve_id' : js2JSON( { 'docid' : docid, 'bucket_item_id' : bucket_item_id } ),
					'row' : {
						'my' : {
							'mvr' : record,
						}
					}
				};
				return item;
			}
		} catch(E) {
			obj.error.standard_unexpected_error_alert('Could not retrieve this record: ' + docid,E);
			return null;
		}

	},
	
}

dump('exiting cat.record_buckets.js\n');
