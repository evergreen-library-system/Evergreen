dump('entering patron/display.js\n');

if (typeof patron == 'undefined') patron = {};
patron.display = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.window'); this.window = new util.window();
	JSAN.use('util.network'); this.network = new util.network();
	this.w = window;
}

patron.display.prototype = {

	'retrieve_ids' : [],

	'init' : function( params ) {

		var obj = this;

		obj.barcode = params['barcode'];
		obj.id = params['id'];

		JSAN.use('OpenILS.data'); this.OpenILS = {}; 
		obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'});

		JSAN.use('util.deck'); 
		obj.right_deck = new util.deck('patron_right_deck');
		obj.left_deck = new util.deck('patron_left_deck');

		function spawn_checkout_interface() {
			obj.right_deck.set_iframe(
				urls.XUL_CHECKOUT
				+ '?patron_id=' + window.escape( obj.patron.id() ),
				{},
				{ 
					'on_list_change' : function(checkout) {

						netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
						obj.summary_window.g.summary.controller.render('patron_checkouts');
						obj.summary_window.g.summary.controller.render('patron_standing');
						if (obj.items_window) {
							obj.items_window.g.items.list.append(
								{
									'row' : {
										'my' : {
											'circ' : checkout.circ,
											'mvr' : checkout.record,
											'acp' : checkout.copy
										}
									}
								}
							)
						}
					}
				}
			);
		}

		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				control_map : {
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_patron_retrieve' : [
						['command'],
						function(ev) {
							if (typeof window.xulG == 'object' && typeof window.xulG.new_tab == 'function') {
								for (var i = 0; i < obj.retrieve_ids.length; i++) {	
									try {
										var url = urls.XUL_PATRON_DISPLAY 
											+ '?id=' + window.escape( obj.retrieve_ids[i] );
										window.xulG.new_tab(
											url
										);
									} catch(E) {
										alert(E);
									}
								}
							}
						}
					],
					'cmd_search_form' : [
						['command'],
						function(ev) {
							obj.controller.view.cmd_search_form.setAttribute('disabled','true');
							obj.left_deck.node.selectedIndex = 0;
							obj.controller.view.patron_name.setAttribute('value','No Patron Selected');
						}
					],
					'cmd_patron_refresh' : [
						['command'],
						function(ev) {
							obj.refresh_all();
						}
					],
					'cmd_patron_checkout' : [
						['command'],
						spawn_checkout_interface
					],
					'cmd_patron_items' : [
						['command'],
						function(ev) {
							var frame = obj.right_deck.set_iframe(
								urls.XUL_PATRON_ITEMS
								+ '?patron_id=' + window.escape( obj.patron.id() ),
								{},
								{
									'on_list_change' : function(b) {
										netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
										obj.summary_window.g.summary.controller.render('patron_checkouts');
										obj.summary_window.g.summary.controller.render('patron_standing');
									},
									'url_prefix' : xulG.url_prefix,
									'new_tab' : xulG.new_tab,
								}
							);
							netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
							obj.items_window = frame.contentWindow;
						}
					],
					'cmd_patron_edit' : [
						['command'],
						function(ev) {
							obj.right_deck.set_iframe(
								urls.XUL_REMOTE_BROWSER
								+ '?url=' + window.escape( 
									urls.XUL_PATRON_EDIT
									+ '?ses=' + window.escape( ses() )
									+ '&usr=' + window.escape( obj.patron.id() )
								),
								{}, {
									'show_print_button' : true,
									'passthru_content_params' : {
										'on_save' : function(p) {
											try {
												netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
												obj.summary_window.g.summary.retrieve();
											} catch(E) {
												alert(E);
											}
										},
									}
								}
							);
						}
					],
					'cmd_patron_info' : [
						['command'],
						function(ev) {
							obj.right_deck.set_iframe(
								urls.XUL_PATRON_INFO + '?patron_id=' + window.escape( obj.patron.id() )
							);
						}
					],
					'cmd_patron_holds' : [
						['command'],
						function(ev) {
							obj.right_deck.set_iframe(
								urls.XUL_PATRON_HOLDS	
								+ '?patron_id=' + window.escape( obj.patron.id() ),
								{},
								{
									'on_list_change' : function(h) {
										netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
										obj.summary_window.g.summary.controller.render('patron_holds');
										obj.summary_window.g.summary.controller.render('patron_standing');
									},
									'url_prefix' : xulG.url_prefix,
									'new_tab' : xulG.new_tab,
								}
							);
						}
					],
					'cmd_patron_bills' : [
						['command'],
						function(ev) {
							var f = obj.right_deck.set_iframe(
								urls.XUL_PATRON_BILLS
								+ '?patron_id=' + window.escape( obj.patron.id() ),
								{},
								{
									'on_money_change' : function(b) {
										//alert('test');
										netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
										obj.summary_window.g.summary.retrieve(true);
									}
								}
							);
						}
					],
					'patron_name' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.family_name() + ', ' + obj.patron.first_given_name() + ' ' +
									( obj.patron.second_given_name() ? obj.patron.second_given_name() : '' )
								);
								JSAN.use('patron.util'); patron.util.set_penalty_css(obj.patron);
							};
						}
					],
					'PatronNavBar' : [
						['render'],
						function(e) {
							return function() {}
						}
					],
				}
			}
		);

		if (obj.barcode || obj.id) {
			if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
				try { window.xulG.set_tab_name('Retrieving Patron...'); } catch(E) { alert(E); }
			}

			obj.controller.view.PatronNavBar.selectedIndex = 1;
			JSAN.use('util.widgets'); 
			util.widgets.enable_accesskeys_in_node_and_children(
				obj.controller.view.PatronNavBar.lastChild
			);
			util.widgets.disable_accesskeys_in_node_and_children(
				obj.controller.view.PatronNavBar.firstChild
			);
			obj.controller.view.cmd_patron_refresh.setAttribute('disabled','true');
			obj.controller.view.cmd_patron_checkout.setAttribute('disabled','true');
			obj.controller.view.cmd_patron_items.setAttribute('disabled','true');
			obj.controller.view.cmd_patron_holds.setAttribute('disabled','true');
			obj.controller.view.cmd_patron_bills.setAttribute('disabled','true');
			obj.controller.view.cmd_patron_edit.setAttribute('disabled','true');
			obj.controller.view.cmd_patron_info.setAttribute('disabled','true');
			obj.controller.view.patron_name.setAttribute('value','Retrieving...');
			document.documentElement.setAttribute('class','');
			var frame = obj.left_deck.set_iframe(
				urls.XUL_PATRON_SUMMARY
				+'?barcode=' + window.escape(obj.barcode) 
				+'&id=' + window.escape(obj.id), 
				{},
				{
					'on_finished' : function(patron) {

						obj.patron = patron; obj.controller.render();

						obj.controller.view.cmd_patron_refresh.setAttribute('disabled','false');
						obj.controller.view.cmd_patron_checkout.setAttribute('disabled','false');
						obj.controller.view.cmd_patron_items.setAttribute('disabled','false');
						obj.controller.view.cmd_patron_holds.setAttribute('disabled','false');
						obj.controller.view.cmd_patron_bills.setAttribute('disabled','false');
						obj.controller.view.cmd_patron_edit.setAttribute('disabled','false');
						obj.controller.view.cmd_patron_info.setAttribute('disabled','false');

						if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
							try { 
								window.xulG.set_tab_name(
									'Patron: ' + patron.family_name() + ', ' + patron.first_given_name() + ' ' 
										+ (patron.second_given_name() ? patron.second_given_name() : '' ) 
								); 
							} catch(E) { 
								obj.error.sdump('D_ERROR',E);
							}
						}

						if (!obj._checkout_spawned) {
							spawn_checkout_interface();
							obj._checkout_spawned = true;
						}

						if (patron.alert_message()) {
							obj.error.yns_alert('"' + patron.alert_message() + '"','Alert Message','OK',null,null,'Check here to confirm this message.');
						}
					},
					'on_error' : function(E) {
						var error = js2JSON(E); obj.error.sdump('D_ERROR', error);
						location.href = urls.XUL_PATRON_BARCODE_ENTRY 
							+ '?error=' + window.escape(error.substr(0,100));
					}
				}
			);
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			obj.summary_window = frame.contentWindow;
		} else {
			if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
				try { window.xulG.set_tab_name('Patron Search'); } catch(E) { alert(E); }
			}

			obj.controller.view.PatronNavBar.selectedIndex = 0;
			JSAN.use('util.widgets'); 
			util.widgets.enable_accesskeys_in_node_and_children(
				obj.controller.view.PatronNavBar.firstChild
			);
			util.widgets.disable_accesskeys_in_node_and_children(
				obj.controller.view.PatronNavBar.lastChild
			);
			obj.controller.view.cmd_patron_retrieve.setAttribute('disabled','true');
			obj.controller.view.cmd_search_form.setAttribute('disabled','true');

			var loc = urls.XUL_PATRON_SEARCH_FORM + '?blah=blah';
			if (params['query']) {
				var query = JSON2js(params['query']);
				for (var i in query) {
					loc += '&'+window.escape(i)+'='+window.escape(query[i].value);
				}
				if (params.doit) {
					loc += '&doit=1';
				}
			}
			var form_frame = obj.left_deck.set_iframe(
				loc,
				{},
				{
					'on_submit' : function(query) {
						obj.controller.view.cmd_patron_retrieve.setAttribute('disabled','true');
						var list_frame = obj.right_deck.reset_iframe(
							urls.XUL_PATRON_SEARCH_RESULT + '?' + query,
							{},
							{
								'on_select' : function(list) {
									obj.controller.view.cmd_patron_retrieve.setAttribute('disabled','false');
									obj.controller.view.cmd_search_form.setAttribute('disabled','false');
									obj.retrieve_ids = list;
									obj.controller.view.patron_name.setAttribute('value','Retrieving...');
									document.documentElement.setAttribute('class','');
									setTimeout(
										function() {
											var frame = obj.left_deck.set_iframe(
												urls.XUL_PATRON_SUMMARY
													+'?id=' + window.escape(list[0]), 
													{},
													{
														'on_finished' : function(patron) {
															obj.patron = patron;
															obj.controller.render();
														}
													}
											);
											netscape.security.PrivilegeManager.enablePrivilege(
												"UniversalXPConnect"
											);
											obj.summary_window = frame.contentWindow;
											obj.patron = obj.summary_window.g.summary.patron;
											obj.controller.render('patron_name');
										}, 0
									);
								}
							}
						);
						netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
						obj.search_result = list_frame.contentWindow;
					}
				}
			);
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			obj.search_window = form_frame.contentWindow;
			obj._checkout_spawned = true;
		}
	},

	'_checkout_spawned' : false,

	'refresh_deck' : function(url) {
		var obj = this;
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		for (var i = 0; i < obj.right_deck.node.childNodes.length; i++) {
			try {
				var f = obj.right_deck.node.childNodes[i];
				var w = f.contentWindow;
				if (url) {
					if (w.location.href == url) w.refresh(true);
				} else {
					if (typeof w.refresh == 'function') {
						w.refresh(true);
					}
				}

			} catch(E) {
				obj.error.sdump('D_ERROR','refresh_deck: ' + E + '\n');
			}
		}
	},
	
	'refresh_all' : function() {
		var obj = this;
		obj.controller.view.patron_name.setAttribute(
			'value','Retrieving...'
		);
		document.documentElement.setAttribute('class','');
		try { obj.summary_window.refresh(); } catch(E) { obj.error.sdump('D_ERROR', E + '\n'); }
		try { obj.refresh_deck(); } catch(E) { obj.error.sdump('D_ERROR', E + '\n'); }
	},
}

dump('exiting patron/display.js\n');
