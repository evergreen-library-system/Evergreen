dump('entering patron/display.js\n');

function $(id) { return document.getElementById(id); }

if (typeof patron == 'undefined') patron = {};
patron.display = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.window'); this.window = new util.window();
	JSAN.use('util.network'); this.network = new util.network();
	this.w = window;
}

patron.display.prototype = {

	'retrieve_ids' : [],
	'stop_checkouts' : false,
	'check_stop_checkouts' : function() { return this.stop_checkouts; },

	'init' : function( params ) {

		var obj = this;

		obj.barcode = params['barcode'];
		obj.id = params['id'];

		JSAN.use('OpenILS.data'); this.OpenILS = {}; 
		obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'});
		
		//var horizontal_interface = String( obj.OpenILS.data.hash.aous['ui.circ.patron_summary.horizontal'] ) == 'true';
		//document.getElementById('ui.circ.patron_summary.horizontal').setAttribute('orient', horizontal_interface ? 'vertical' : 'horizontal');
		//document.getElementById('pdms1').setAttribute('orient', horizontal_interface ? 'vertical' : 'horizontal');
		
		JSAN.use('util.deck'); 
		obj.right_deck = new util.deck('patron_right_deck');
		obj.left_deck = new util.deck('patron_left_deck');

		function spawn_checkout_interface() {
	            try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible( document.getElementById("PatronNavBar_checkout" ) ); } catch(E) {};
			obj.reset_nav_styling('cmd_patron_checkout');
			var frame = obj.right_deck.set_iframe(
				urls.XUL_CHECKOUT,
				{},
				{ 
					'set_tab' : xulG.set_tab,
					'patron_id' : obj.patron.id(),
					'check_stop_checkouts' : function() { return obj.check_stop_checkouts(); },
					'on_list_change' : function(checkout) {
						netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
						var x = obj.summary_window.g.summary.controller.view.patron_checkouts;
						var n = Number(x.getAttribute('value'));
						x.setAttribute('value',n+1);
					},
					'on_list_change_old' : function(checkout) {
					
						/* this stops noncats from getting pushed into Items Out */
						if (!checkout.circ.id()) return; 

						netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
						obj.summary_window.g.summary.controller.render('patron_checkouts');
						obj.summary_window.g.summary.controller.render('patron_standing_penalties');
						if (obj.items_window) {
							obj.items_window.g.items.list.append(
								{
									'row' : {
										'my' : {
											'circ_id' : checkout.circ.id()
										}
									}
								}
							)
						}
					}
				}
			);
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			obj.checkout_window = get_contentWindow(frame);
		}

		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				control_map : {
					'cmd_broken' : [
						['command'],
						function() { alert($("commonStrings").getString('common.unimplemented')); }
					],
					'cmd_patron_retrieve' : [
						['command'],
						function(ev) {
							if (typeof window.xulG == 'object' && typeof window.xulG.new_tab == 'function') {
								for (var i = 0; i < obj.retrieve_ids.length; i++) {	
									try {
										window.xulG.new_patron_tab(
											{}, { 'id' : obj.retrieve_ids[i] }
										);
									} catch(E) {
										alert(E);
									}
								}
							}
						}
					],
                    'cmd_patron_merge' : [
                        ['command'],
                        function(ev) {
                            JSAN.use('patron.util');
                            if (patron.util.merge( obj.retrieve_ids )) {
                                obj.controller.view.cmd_patron_retrieve.setAttribute('disabled','true');
                                obj.controller.view.cmd_patron_merge.setAttribute('disabled','true');
                                var sobj = obj.search_result.g.search_result;
                                if ( sobj.query ) { sobj.search( sobj.query ); }
                            }
                        }
                    ],
                    'cmd_patron_toggle_summary' : [
                        ['command'],
                        function(ev) {
                            var x = document.getElementById('left_deck_vbox'); 
                            if (x) {
                                x.hidden = ! x.hidden;
                            }
                        }
                    ],
					'cmd_search_form' : [
						['command'],
						function(ev) {
							obj.controller.view.cmd_search_form.setAttribute('disabled','true');
							obj.left_deck.node.selectedIndex = 0;
							obj.controller.view.patron_name.setAttribute('value', $("patronStrings").getString('staff.patron.display.cmd_search_form.no_patron'));
							removeCSSClass(document.documentElement,'PATRON_HAS_BILLS');
							removeCSSClass(document.documentElement,'PATRON_HAS_OVERDUES');
							removeCSSClass(document.documentElement,'PATRON_HAS_NOTES');
							removeCSSClass(document.documentElement,'PATRON_EXCEEDS_CHECKOUT_COUNT');
							removeCSSClass(document.documentElement,'PATRON_EXCEEDS_OVERDUE_COUNT');
							removeCSSClass(document.documentElement,'PATRON_EXCEEDS_FINES');
							removeCSSClass(document.documentElement,'NO_PENALTIES');
							removeCSSClass(document.documentElement,'ONE_PENALTY');
							removeCSSClass(document.documentElement,'MULTIPLE_PENALTIES');
							removeCSSClass(document.documentElement,'PATRON_HAS_ALERT');
							removeCSSClass(document.documentElement,'PATRON_BARRED');
							removeCSSClass(document.documentElement,'PATRON_INACTIVE');
							removeCSSClass(document.documentElement,'PATRON_EXPIRED');
							removeCSSClass(document.documentElement,'PATRON_HAS_INVALID_DOB');
							removeCSSClass(document.documentElement,'PATRON_JUVENILE');
							removeCSSClass(document.documentElement,'PATRON_HAS_INVALID_ADDRESS');
							removeCSSClass(document.documentElement,'PATRON_AGE_GE_65');
							removeCSSClass(document.documentElement,'PATRON_AGE_LT_65');
							removeCSSClass(document.documentElement,'PATRON_AGE_GE_24');
							removeCSSClass(document.documentElement,'PATRON_AGE_LT_24');
							removeCSSClass(document.documentElement,'PATRON_AGE_GE_21');
							removeCSSClass(document.documentElement,'PATRON_AGE_LT_21');
							removeCSSClass(document.documentElement,'PATRON_AGE_GE_18');
							removeCSSClass(document.documentElement,'PATRON_AGE_LT_18');
							removeCSSClass(document.documentElement,'PATRON_AGE_GE_13');
							removeCSSClass(document.documentElement,'PATRON_AGE_LT_13');
							removeCSSClass(document.documentElement,'PATRON_NET_ACCESS_1');
							removeCSSClass(document.documentElement,'PATRON_NET_ACCESS_2');
							removeCSSClass(document.documentElement,'PATRON_NET_ACCESS_3');
						}
					],
					'cmd_patron_refresh' : [
						['command'],
						function(ev) {
                            try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible( document.getElementById("PatronNavBar_refresh" ) ); } catch(E) {};
							obj.network.simple_request(
								'RECALCULATE_STANDING_PENALTIES',
								[ ses(), obj.patron.id() ]
							);
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
                            try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible( document.getElementById("PatronNavBar_items" ) ); } catch(E) {};
							obj.reset_nav_styling('cmd_patron_items');
							var frame = obj.right_deck.set_iframe(
								urls.XUL_PATRON_ITEMS,
								//+ '?patron_id=' + window.escape( obj.patron.id() ),
								{},
								{
									'patron_id' : obj.patron.id(),
									'on_list_change' : function(b) {
										netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
										obj.summary_window.g.summary.controller.render('patron_checkouts');
										obj.summary_window.g.summary.controller.render('patron_standing_penalties');
										obj.summary_window.g.summary.controller.render('patron_bill');
										obj.bill_window.g.bills.refresh(true);
									},
									'url_prefix' : xulG.url_prefix,
									'new_tab' : xulG.new_tab
								}
							);
							netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
							obj.items_window = get_contentWindow(frame);
						}
					],
					'cmd_patron_edit' : [
						['command'],
						function(ev) {
                                try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible( document.getElementById("PatronNavBar_edit" ) ); } catch(E) {};
								obj.reset_nav_styling('cmd_patron_edit');

								function spawn_search(s) {
									obj.error.sdump('D_TRACE', $("commonStrings").getFormattedString('staff.patron.display.cmd_patron_edit.edit_search', [js2JSON(s)]) ); 
									obj.OpenILS.data.stash_retrieve();
									xulG.new_patron_tab( {}, { 'doit' : 1, 'query' : s } );
								}

								function spawn_editor(p) {
									var url = urls.XUL_PATRON_EDIT;
									//var param_count = 0;
									//for (var i in p) {
									//	if (param_count++ == 0) url += '?'; else url += '&';
									//	url += i + '=' + window.escape(p[i]);
									//}
									var loc = xulG.url_prefix( urls.XUL_REMOTE_BROWSER ); // + '?url=' + window.escape( url );
									xulG.new_tab(
										loc, 
										{}, 
										{ 
											'url' : url,
											'show_print_button' : true , 
											'tab_name' : $("patronStrings").getString('staff.patron.display.spawn_editor.editing_related_patron'),
											'passthru_content_params' : {
												'spawn_search' : spawn_search,
												'spawn_editor' : spawn_editor,
												'url_prefix' : xulG.url_prefix,
												'new_tab' : xulG.new_tab,
												'params' : p
											}
										}
									);
								}

							obj.right_deck.set_iframe(
								urls.XUL_REMOTE_BROWSER + '?patron_edit=1',
								//+ '?url=' + window.escape( 
								//	urls.XUL_PATRON_EDIT
								//	+ '?ses=' + window.escape( ses() )
								//	+ '&usr=' + window.escape( obj.patron.id() )
								//),
								{}, {
									'url' : urls.XUL_PATRON_EDIT,
									'show_print_button' : true,
									'passthru_content_params' : {
										'params' : {
											'ses' : ses(),
											'usr' : obj.patron.id()
										},
										'on_save' : function(p) {
											try {
												if (obj.barcode) obj.barcode = p.card().barcode();
												netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
												//obj.summary_window.g.summary.retrieve();
												obj.refresh_all();
											} catch(E) {
												alert(E);
											}
										},
										'spawn_search' : spawn_search,
										'spawn_editor' : spawn_editor,
										'url_prefix' : xulG.url_prefix,
										'new_tab' : xulG.new_tab
									}
								}
							);
						}
					],
                    'cmd_patron_other' : [
						['command'],
						function(ev) {
                            try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible( document.getElementById("PatronNavBar_other" ) ); } catch(E) {};
							obj.reset_nav_styling('cmd_patron_other');
                            try { document.getElementById('PatronNavBar_other').firstChild.showPopup(); } catch(E) {};
                        }
                    ],
					'cmd_patron_info_notes' : [
						['command'],
						function(ev) {
							obj.right_deck.set_iframe(
                                urls.XUL_PATRON_INFO_NOTES,
								{},
								{
									'patron_id' : obj.patron.id(),
									'url_prefix' : xulG.url_prefix,
									'new_tab' : xulG.new_tab
								}
							);
						}
					],
					'cmd_patron_info_stats' : [
						['command'],
						function(ev) {
							obj.right_deck.set_iframe(
                                urls.XUL_PATRON_INFO_STAT_CATS,
								{},
								{
									'patron_id' : obj.patron.id(),
									'url_prefix' : xulG.url_prefix,
									'new_tab' : xulG.new_tab
								}
							);
						}
					],
					'cmd_patron_info_surveys' : [
						['command'],
						function(ev) {
							obj.right_deck.set_iframe(
                                urls.XUL_PATRON_INFO_SURVEYS,
								{},
								{
									'patron_id' : obj.patron.id(),
									'url_prefix' : xulG.url_prefix,
									'new_tab' : xulG.new_tab
								}
							);
						}
					],
					'cmd_patron_info_groups' : [
						['command'],
						function(ev) {
							obj.right_deck.set_iframe(
                                urls.XUL_PATRON_INFO_GROUP,
								{},
								{
									'patron_id' : obj.patron.id(),
									'url_prefix' : xulG.url_prefix,
									'new_tab' : xulG.new_tab
								}
							);
						}
					],
                    'cmd_patron_alert' : [
                        ['command'],
                        function(ev) {
                            if (obj.msg_url) {
                                obj.right_deck.set_iframe('data:text/html,'+obj.msg_url,{},{});
                            } else {
                                obj.right_deck.set_iframe('data:text/html,<h1>' + $("patronStrings").getString('staff.patron.display.no_alerts_or_messages') + '</h1>',{},{});
                            }
                        }
                    ],
					'cmd_patron_exit' : [
						['command'],
						function(ev) {
							xulG.set_tab(urls.XUL_PATRON_BARCODE_ENTRY,{},{});
						}
					],
					'cmd_patron_holds' : [
						['command'],
						function(ev) {
                            try {
                                try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible( document.getElementById("PatronNavBar_holds" ) ); } catch(E) {};
                                obj.reset_nav_styling('cmd_patron_holds');
                                obj.right_deck.set_iframe(
                                    urls.XUL_PATRON_HOLDS,	
                                    //+ '?patron_id=' + window.escape( obj.patron.id() ),
                                    {},
                                    {
                                        'display_window' : window,
                                        'patron_id' : obj.patron.id(),
                                        'patron_barcode' : obj.patron.card().barcode(),
                                        'on_list_change' : function(h) {
                                            netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
                                            //obj.summary_window.g.summary.controller.render('patron_holds');
                                            //obj.summary_window.g.summary.controller.render('patron_standing_penalties');
                                            obj.refresh_all();
                                        },
                                        'url_prefix' : xulG.url_prefix,
                                        'new_tab' : xulG.new_tab
                                    }
                                );
                            } catch(E) {
                                alert(E);
                            }
						}
					],
					'cmd_patron_bills' : [
						['command'],
						function(ev) {
                            try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible( document.getElementById("PatronNavBar_bills" ) ); } catch(E) {};
							obj.reset_nav_styling('cmd_patron_bills');
							var f = obj.right_deck.set_iframe(
								urls.XUL_PATRON_BILLS,
								//+ '?patron_id=' + window.escape( obj.patron.id() ),
								{},
								{
									'patron_id' : obj.patron.id(),
									'url_prefix' : xulG.url_prefix,
									'on_money_change' : function(b) {
										//alert('test');
										netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
										//obj.summary_window.g.summary.retrieve(true);
										//obj.items_window.g.items.retrieve(true);
										obj.refresh_all();
									}
								}
							);
							netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
							obj.bill_window = get_contentWindow(f);
						}
					],
					'patron_name' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									( obj.patron.prefix() ? obj.patron.prefix() + ' ' : '') + 
									obj.patron.family_name() + ', ' + 
									obj.patron.first_given_name() + ' ' +
									( obj.patron.second_given_name() ? obj.patron.second_given_name() + ' ' : '' ) +
									( obj.patron.suffix() ? obj.patron.suffix() : '')
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
                    'cmd_verify_credentials' : [
                        ['command'],
                        function() {
                            var vframe = obj.right_deck.reset_iframe(
                                urls.XUL_VERIFY_CREDENTIALS,
                                {},
                                {
                                    'barcode' : obj.patron.card().barcode(),
                                    'usrname' : obj.patron.usrname()
                                }
                            );
                        } 
                    ],
                    'cmd_perm_editor' : [
                        ['command'],
                        function() {
                             var frame = obj.right_deck.reset_iframe( urls.XUL_USER_PERM_EDITOR + '?ses=' + window.escape(ses()) + '&usr=' + obj.patron.id(), {}, {});
                        }
                    ],
                    'cmd_standing_penalties' : [
                        ['command'],
                        function() {
                            function penalty_interface() {
                                try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible( document.getElementById("PatronNavBar_messages" ) ); } catch(E) {};
							    obj.reset_nav_styling('cmd_standing_penalties');
                                return obj.right_deck.reset_iframe(
                                    urls.XUL_STANDING_PENALTIES,
                                    {},
                                    {
                                        'patron' : obj.patron,
                                        'refresh' : function() { 
                                            obj.refresh_all(); 
                                        }
                                    }
                                );
                            }
                            penalty_interface();
                        } 
                    ]
				}
			}
		);

        var x = document.getElementById("PatronNavBar_checkout");
        x.addEventListener( 'focus', function(xx) { return function() { try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible(xx); } catch(E) {}; } }(x), false);
        var x = document.getElementById("PatronNavBar_refresh");
        x.addEventListener( 'focus', function(xx) { return function() { try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible(xx); } catch(E) {}; } }(x), false);
        var x = document.getElementById("PatronNavBar_items");
        x.addEventListener( 'focus', function(xx) { return function() { try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible(xx); } catch(E) {}; } }(x), false);
        var x = document.getElementById("PatronNavBar_holds");
        x.addEventListener( 'focus', function(xx) { return function() { try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible(xx); } catch(E) {}; } }(x), false);
        var x = document.getElementById("PatronNavBar_other");
        x.addEventListener( 'focus', function(xx) { return function() { try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible(xx); } catch(E) {}; } }(x), false);
        var x = document.getElementById("PatronNavBar_edit");
        x.addEventListener( 'focus', function(xx) { return function() { try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible(xx); } catch(E) {}; } }(x), false);
        var x = document.getElementById("PatronNavBar_bills");
        x.addEventListener( 'focus', function(xx) { return function() { try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible(xx); } catch(E) {}; } }(x), false);
        var x = document.getElementById("PatronNavBar_messages");
        x.addEventListener( 'focus', function(xx) { return function() { try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible(xx); } catch(E) {}; } }(x), false);

		if (obj.barcode || obj.id) {
			if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
				try { window.xulG.set_tab_name($("patronStrings").getString('staff.patron.display.init.retrieving_patron')); } catch(E) { alert(E); }
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
			obj.controller.view.patron_name.setAttribute('value', $("patronStrings").getString('staff.patron.display.init.retrieving'));
			document.documentElement.setAttribute('class','');
			var frame = obj.left_deck.set_iframe(
				urls.XUL_PATRON_SUMMARY,
				{},
				{
                    'display_window' : window,
					'barcode' : obj.barcode,
					'id' : obj.id,
                    'refresh' : function() { obj.refresh_all(); },
					'on_finished' : function(patron) {

						obj.patron = patron; obj.controller.render();

						obj.controller.view.cmd_patron_refresh.setAttribute('disabled','false');
						obj.controller.view.cmd_patron_checkout.setAttribute('disabled','false');
						obj.controller.view.cmd_patron_items.setAttribute('disabled','false');
						obj.controller.view.cmd_patron_holds.setAttribute('disabled','false');
						obj.controller.view.cmd_patron_bills.setAttribute('disabled','false');
						obj.controller.view.cmd_patron_edit.setAttribute('disabled','false');

						if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
							try { 
								window.xulG.set_tab_name(
									$("patronStrings").getString('staff.patron.display.tab_name')
										+ ' ' + patron.family_name() + ', ' + patron.first_given_name() + ' ' 
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

						obj.network.simple_request(
							'FM_AHR_COUNT_RETRIEVE.authoritative',
							[ ses(), patron.id() ],
							function(req) {
								try {
									var msg = ''; obj.stop_checkouts = false;
									if (patron.alert_message())
										msg += $("patronStrings").getFormattedString('staff.patron.display.init.network_request.alert_message', [patron.alert_message()]);
									//alert('obj.barcode = ' + obj.barcode);
									if (obj.barcode) {
										if (patron.cards()) for (var i = 0; i < patron.cards().length; i++) {
											//alert('card #'+i+' == ' + js2JSON(patron.cards()[i]));
											if ( (patron.cards()[i].barcode()==obj.barcode) && ( ! get_bool(patron.cards()[i].active()) ) ) {
												msg += $("patronStrings").getString('staff.patron.display.init.network_request.inactive_card');
												obj.stop_checkouts = true;
											}
										}
									}
									if (get_bool(patron.barred())) {
										msg += $("patronStrings").getString('staff.patron.display.init.network_request.account_barred');
										obj.stop_checkouts = true;
									}
									if (!get_bool(patron.active())) {
										msg += $("patronStrings").getString('staff.patron.display.init.network_request.account_inactive');
										obj.stop_checkouts = true;
									}
									if (patron.expire_date()) {
										var now = new Date();
										now = now.getTime()/1000;

										var expire_parts = patron.expire_date().substr(0,10).split('-');
										expire_parts[1] = expire_parts[1] - 1;

										var expire = new Date();
										expire.setFullYear(expire_parts[0], expire_parts[1], expire_parts[2]);
										expire = expire.getTime()/1000

										if (expire < now) {
											msg += $("patronStrings").getString('staff.patron.display.init.network_request.account_expired');
										obj.stop_checkouts = true;
										}
									}
								    var penalties = obj.patron.standing_penalties();
								    for (var i = 0; i < penalties.length; i++) {
                                        if (penalties[i].standing_penalty().block_list()) {
                                            msg += obj.OpenILS.data.hash.aou[ penalties[i].org_unit() ].shortname() + ' : ' + penalties[i].standing_penalty().label() + '<br/>';
                                        }
                                    }
									var holds = req.getResultObject();
									if (holds.ready && holds.ready > 0) {
										msg += $("patronStrings").getFormattedString('staff.patron.display.init.holds_ready', [holds.ready]);
									}
									if (msg) {
										if (msg != obj.old_msg) {
											//obj.error.yns_alert(msg,'Alert Message','OK',null,null,'Check here to confirm this message.');
											document.documentElement.firstChild.focus();
											var data_url = window.escape("<img src='" + xulG.url_prefix('/xul/server/skin/media/images/stop_sign.png') + "'/>" + '<h1>'
												+ $("patronStrings").getString('staff.patron.display.init.network_request.window_title') + '</h1><blockquote><p>' + msg + '</p>\r\n\r\n<pre>'
												+ $("patronStrings").getString('staff.patron.display.init.network_request.window_message') + '</pre></blockquote>');
											obj.right_deck.set_iframe('data:text/html,'+data_url,{},{});
											obj.old_msg = msg;
                                            obj.msg_url = data_url;
										} else {
											obj.error.sdump('D_TRACE',$("patronStrings").getFormattedString('staff.patron.display.init.network_request.dump_error_message', [msg]));
										}
									}
									if (obj.stop_checkouts && obj.checkout_window) {
										setTimeout( function() {
											try {
												netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
												obj.checkout_window.g.checkout.check_disable();
											} catch(E) { }
										}, 1000);
									}
								} catch(E) {
									obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.display.init.network_request.error_showing_alert'),E);
								}
							}
						);

					},
					'on_error' : function(E) {
						try {
							var error;
							if (typeof E.ilsevent != 'undefined') {
								error = E.textcode;
							} else {
								error = js2JSON(E).substr(0,100);
							}
							location.href = urls.XUL_PATRON_BARCODE_ENTRY + '?error=' + window.escape(error);
						} catch(F) {
							alert(F);
						}
					}
				}
			);
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			obj.summary_window = get_contentWindow(frame);
		} else {
			obj.render_search_form(params);
		}
	},

	'reset_nav_styling' : function(btn) {
        try {
            this.controller.view.cmd_patron_checkout.setAttribute('style','');
            this.controller.view.cmd_patron_items.setAttribute('style','');
            this.controller.view.cmd_patron_edit.setAttribute('style','');
            this.controller.view.cmd_patron_other.setAttribute('style','');
            this.controller.view.cmd_patron_holds.setAttribute('style','');
            this.controller.view.cmd_patron_bills.setAttribute('style','');
            this.controller.view.cmd_standing_penalties.setAttribute('style','');
            this.controller.view[ btn ].setAttribute('style','background: blue; color: white;');
        } catch(E) {
            alert(E);
        }
	},

	'render_search_form' : function(params) {
		var obj = this;
			if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
				try { window.xulG.set_tab_name($("patronStrings").getString('staff.patron.display.render_search_form.patron_search')); } catch(E) { alert(E); }
			}

			obj.controller.view.PatronNavBar.selectedIndex = 0;
			obj.controller.view.cmd_patron_retrieve.setAttribute('disabled','true');
			obj.controller.view.cmd_patron_merge.setAttribute('disabled','true');
			obj.controller.view.cmd_search_form.setAttribute('disabled','true');

		    var horizontal_interface = String( obj.OpenILS.data.hash.aous['ui.circ.patron_summary.horizontal'] ) == 'true';
			var loc = horizontal_interface ? urls.XUL_PATRON_HORIZONTAL_SEARCH_FORM : urls.XUL_PATRON_SEARCH_FORM; 
			var my_xulG = {
				'clear_left_deck' : function() {
					setTimeout( function() {
						obj.left_deck.clear_all_except(loc);
						obj.render_search_form(params);
					}, 0);
				},
				'on_submit' : function(query) {
					obj.controller.view.cmd_patron_retrieve.setAttribute('disabled','true');
			        obj.controller.view.cmd_patron_merge.setAttribute('disabled','true');
					var list_frame = obj.right_deck.reset_iframe(
						urls.XUL_PATRON_SEARCH_RESULT, // + '?' + query,
						{},
						{
							'query' : query,
							'on_select' : function(list) {
								if (!list) return;
								if (list.length < 1) return;
								obj.controller.view.cmd_patron_retrieve.setAttribute('disabled','false');
								if (list.length > 1) obj.controller.view.cmd_patron_merge.setAttribute('disabled','false');
								obj.controller.view.cmd_search_form.setAttribute('disabled','false');
								obj.retrieve_ids = list;
								obj.controller.view.patron_name.setAttribute('value',$("patronStrings").getString('staff.patron.display.init.retrieving'));
								document.documentElement.setAttribute('class','');
								setTimeout(
									function() {
										var frame = obj.left_deck.set_iframe(
											urls.XUL_PATRON_SUMMARY + '?id=' + window.escape(list[0]),
											{},
											{
												//'id' : list[0],
												'on_finished' : function(patron) {
													obj.patron = patron;
													obj.controller.render();
												}
											}
										);
										netscape.security.PrivilegeManager.enablePrivilege(
											"UniversalXPConnect"
										);
										obj.summary_window = get_contentWindow(frame);
										obj.patron = obj.summary_window.g.summary.patron;
										obj.controller.render('patron_name');
									}, 0
								);
							}
						}
					);
					netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
					obj.search_result = get_contentWindow(list_frame);
				}
			};

			if (params['query']) {
				my_xulG.query = JSON2js(params['query']);
				if (params.doit) my_xulG.doit = 1;
			}

			var form_frame = obj.left_deck.set_iframe(
				loc,
				{},
				my_xulG
			);
			netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
			obj.search_window = get_contentWindow(form_frame);
			obj._checkout_spawned = true;
	},

	'_checkout_spawned' : false,

	'refresh_deck' : function(url) {
		var obj = this;
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		for (var i = 0; i < obj.right_deck.node.childNodes.length; i++) {
			try {
				var f = obj.right_deck.node.childNodes[i];
				var w = get_contentWindow(f);
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
		obj.controller.view.patron_name.setAttribute('value', $("patronStrings").getString('staff.patron.display.init.retrieving'));
		document.documentElement.setAttribute('class','');
		try { obj.summary_window.refresh(); } catch(E) { obj.error.sdump('D_ERROR', E + '\n'); }
		try { obj.refresh_deck(); } catch(E) { obj.error.sdump('D_ERROR', E + '\n'); }
	},
}

dump('exiting patron/display.js\n');
