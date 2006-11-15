		function $(id) { return document.getElementById(id); }
		function $c(tag) { return document.createElement(tag); }
		function $w(e,msg) { 
			if (typeof e != 'object') e = $(e); 
			switch(e.nodeName) {
				case 'description' :
					e.appendChild( document.createTextNode( msg ) );
				break;
				case 'label' : 
				default:
					e.setAttribute('value',msg);
				break;
			}
		}

/*********************************************************************************************************/
/* Main entry point */

		function my_init() {
			try {
				netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		                if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
				JSAN.errorLevel = "die"; // none, warn, or die
				JSAN.addRepository('/xul/server/');
				JSAN.use('util.error'); g.error = new util.error();
				g.error.sdump('D_TRACE','my_init() for patron/barcode_entry.xul');
				JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});

				JSAN.use('util.network'); g.network = new util.network();
				JSAN.use('util.barcode');
				JSAN.use('util.print'); g.print = new util.print();

				g.cgi = new CGI();

				/************************************************************/
				/* set up the non-cat menu */

				JSAN.use('util.widgets'); JSAN.use('util.functional'); JSAN.use('util.fm_utils');
				var items = [ [ 'or choose a non-barcoded option' , 'barcode' ] ].concat(
						util.functional.map_list(
							util.functional.filter_list(
								g.data.list.cnct,
								function(o) {
									return util.fm_utils.compare_aou_a_is_b_or_ancestor(o.owning_lib(), g.data.list.au[0].ws_ou());
								}
							).sort(

								function(a,b) {
									try { 
										return util.fm_utils.sort_func_aou_by_depth_and_then_string(
											[ a.owning_lib(), a.name() ],
											[ b.owning_lib(), b.name() ]
										);
									} catch(E) {
										alert('error in noncat sorting: ' + E);
										return 0;
									}
								}

							),
							function(o) {
								return [ g.data.hash.aou[ o.owning_lib() ].shortname() + ' : ' + o.name(), o.id() ];
							}
						)
				);
				g.error.sdump('D_TRACE','items = ' + js2JSON(items));
				var ml = util.widgets.make_menulist(
					items
				);
				$("checkout_menu_placeholder").appendChild( ml );
				ml.setAttribute('id','checkout_menulist');
				ml.setAttribute('accesskey','');
				ml.addEventListener(
					'command',
					function(ev) {
						var tb = $('checkout_barcode_entry_textbox');
						var db = $('checkout_duedate_menu');
						if (ev.target.value == 'barcode') {
							db.value = db.getAttribute('default_value') || db.value;
							db.disabled = false;
							tb.disabled = false;
							tb.value = '';
							tb.focus();
						} else {
							db.setAttribute('default_value',db.value);
							db.value = 'Normal';
							db.disabled = true;
							tb.disabled = true;
							tb.value = 'Non-Cataloged';
						}
					}, false
				);

				/************************************************************/
				/* set up the patron barcode textbox */

				var tb = $('barcode_tb');
				tb.addEventListener(
					'keypress',
					function(ev) {
						if (ev.keyCode == 13 || ev.keyCode == 77) {
							setTimeout(
								function() {
									submit();
								}, 0
							);
						}
					},
					false
				);
				tb.focus();

				/************************************************************/
				/* set up the item barcode textbox */

				$('checkout_barcode_entry_textbox').addEventListener(
					'keypress',
					function(ev) {
						if (ev.keyCode == 13 || ev.keyCode == 77) {
							setTimeout(
								function() {
									submit_item();
								}, 0
							);
						}
					},
					false
				);

				$('checkout_top_ui').hidden = ! $('quick_checkout').checked;	
	
				$("checkout_barcode_entry_textbox").disabled = true;
				$("checkout_duedate_menu").disabled = true;
				$("checkout_menulist").disabled = true;
				$("checkout_submit").disabled = true;
				$("done").disabled = true;
				$("retrieve_patron").disabled = true;
				$("strict_barcode").disabled = true;
				$("enable_print").disabled = true;

				if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
					try { window.xulG.set_tab_name('Check Out'); } catch(E) { alert(E); }
				}

				if (g.cgi.param('error')) { 
					var error = g.cgi.param('error');
					alert(error);
				}

			} catch(E) {
				var err_msg = "!! This software has encountered an error.  Please tell your friendly " +
					"system administrator or software developer the following:\n" + E + '\n';
				try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); }
				alert(err_msg);
			}
		}


/*********************************************************************************************************/
/* test for a specific event in array or scalar */

		function test_event(list,ev) {
			if (typeof list.ilsevent != 'undefined' ) {
				if (list.ilsevent == ev) {
					return list;
				} else {
					return false;
				}
			} else {
				for (var i = 0; i < list.length; i++) {
					if (typeof list[i].ilsevent != 'undefined') {
						if (list[i].ilsevent == ev) return list[i];
					}
				}
				return false;
			}
		}

/*********************************************************************************************************/
/* look for a valid checkdigit if the strict barcode check is enabled */

		function test_barcode(bc) {
			var x = document.getElementById('strict_barcode');
			if (x && x.checked != true) return true;
			var good = util.barcode.check(bc);
			if (good) {
				return true;
			} else {
				if ( 1 == g.error.yns_alert(
							'Bad checkdigit; possible mis-scan.  Use this barcode ("' + bc + '") anyway?',
							'Bad Barcode',
							'Cancel',
							'Accept Barcode',
							null,
							'Check here to confirm this action',
							'/xul/server/skin/media/images/bad_barcode.png'
				) ) {
					return true;
				} else {
					return false;
				}
			}
		}

/*********************************************************************************************************/
/* check and convert the value in the due_date widget */

		function test_date(node) {
			JSAN.use('util.date');
			try {
				if (node.value == 'Normal') return true;
				var pattern = node.value.match(/Today \+ (\d+) days/);
				if (pattern) {
					var today = new Date();
					var todayPlus = new Date(); todayPlus.setTime( today.getTime() + 24*60*60*1000*pattern[1] );
					node.value = util.date.formatted_date(todayPlus,"%F");
				}
				if (! util.date.check('YYYY-MM-DD',node.value) ) { throw('Invalid Date'); }
				if (util.date.check_past('YYYY-MM-DD',node.value) ) { throw('Due date needs to be after today.'); }
				if ( util.date.formatted_date(new Date(),'%F') == node.value) { throw('Due date needs to be after today.'); }
				return true;
			} catch(E) {
				alert(E);
				node.value = 'Normal';
				return true;
			}
		}

/*********************************************************************************************************/
/* process the checkout submission -- first pass */

		function submit_item() {
			try {
		
				var checkout_params = {};

				JSAN.use('util.sound'); var sound = new util.sound();

				try { test_date($('checkout_duedate_menu')); } catch(E) { return; }
				if ($('checkout_duedate_menu').value != 'Normal') {
					checkout_params.due_date = $('checkout_duedate_menu').value;
				}

				switch( $('checkout_menulist').value ) {

					case 'barcode' :
						var tb = $('checkout_barcode_entry_textbox');
						var barcode = tb.value; barcode = String( barcode ).replace( /\s+/g, '' );
						if (!barcode) { sound.circ_bad(); /*add_msg('No item barcode entered.');*/ tb.select(); tb.focus(); return; }
						var row = $c('row'); 
						if ($('spacer').nextSibling) {
							$('rows').insertBefore(row,$('spacer').nextSibling); 
						} else {
							$('rows').appendChild(row);
						}
						row.setAttribute('name','lineitem');
						var bc_label = $c('label'); row.appendChild(bc_label); $w(bc_label,barcode);
						var dd_label = $c('label'); row.appendChild(dd_label); 
						var tt_label = $c('description'); row.appendChild(tt_label);
						addCSSClass(bc_label,'line_item'); addCSSClass(dd_label,'line_item'); addCSSClass(tt_label,'line_item');

						if ( test_barcode(barcode) ) { 
							sound.circ_good(); 
							checkout_params.patron_id = g.patron_id;
							checkout_params.barcode = barcode;
							process_barcoded_item( checkout_params,dd_label,tt_label);
						} else {
							$w(dd_label,'Bad Barcode');
							addCSSClass(dd_label,'bad_barcode');
							sound.circ_bad(); 
						}

						tb.value = ''; tb.select(); tb.focus();
					break;

					default:
						alert('non-cat quick checkout not yet implemented');
					break;

				}

			} catch(E) {
				g.error.standard_unexpected_error_alert('barcode_entry.xul:submit_item()',E);
				$('checkout_barcode_entry_textbox').focus();
				$('checkout_barcode_entry_textbox').select();
			}
		}

/*********************************************************************************************************/
/* process the checkout submission -- second pass, barcoded item */

	function process_barcoded_item(checkout_params,dd_label,tt_label) {
		try {
			addCSSClass(dd_label,'checking_barcode');
			$w(dd_label,'Checking...');
			g.network.simple_request(
				checkout_params.precat ? 'CHECKOUT' : 'CHECKOUT_FULL',
				[ ses(), checkout_params ],
				function(req) {
					try {
						removeCSSClass(dd_label,'checking_barcode');
						$w(dd_label,'');
						process_barcoded_item_callback(req,checkout_params,dd_label,tt_label);
					} catch(E) {
						g.error.standard_unexpected_error_alert('barcode_entry.xul:process_barcoded('+checkout_params+'),callback wrapper',E);
						$('checkout_barcode_entry_textbox').focus();
						$('checkout_barcode_entry_textbox').select();
					}
				},
				{
					'title' : 'Override Checkout Failure?',
					'overridable_events' : [ 
						1212 /* PATRON_EXCEEDS_OVERDUE_COUNT */,
						1213 /* PATRON_BARRED */,
						1215 /* CIRC_EXCEEDS_COPY_RANGE */,
						7002 /* PATRON_EXCEEDS_CHECKOUT_COUNT */,
						7003 /* COPY_CIRC_NOT_ALLOWED */,
						7004 /* COPY_NOT_AVAILABLE */, 
						7006 /* COPY_IS_REFERENCE */, 
						7010 /* COPY_ALERT_MESSAGE */,
						7013 /* PATRON_EXCEEDS_FINES */,
						7016 /* ITEM_ON_HOLDS_SHELF */,
					],
					'text' : {
						'1212' : function(r) { return 'Item: ' + checkout_params.barcode; },
						'1213' : function(r) { return 'Item: ' + checkout_params.barcode; },
						'1215' : function(r) { return 'Item: ' + checkout_params.barcode; },
						'7002' : function(r) { return 'Item: ' + checkout_params.barcode; },
						'7003' : function(r) { return 'Item: ' + checkout_params.barcode; },
						'7004' : function(r) {
							return 'Status: ' + r.payload.status().name() + '\nItem: ' + checkout_params.barcode;
						},
						'1212' : function(r) { return 'Item: ' + checkout_params.barcode; },
						'7010' : function(r) {
							return 'Alert: ' + r.payload + '\nItem: ' + checkout_params.barcode;
						},
						'7013' : function(r) { return 'Item: ' + checkout_params.barcode; },
						'7016' : function(r) { return 'Item: ' + checkout_params.barcode; },
					}
				}
			);
		} catch(E) {
			g.error.standard_unexpected_error_alert('barcode_entry.xul:process_barcoded('+checkout_params+')',E);
			$('checkout_barcode_entry_textbox').focus();
			$('checkout_barcode_entry_textbox').select();
		}
	}

	function process_barcoded_item_callback(req,checkout_params,dd_label,tt_label) {
		try {
			var checkout = req.getResultObject();

			if (typeof checkout.ilsevent != 'undefined') checkout = [ checkout ];

			if (test_event(checkout, 0 /* SUCCESS */)) {

				removeCSSClass(dd_label,'bad_barcode'); removeCSSClass(tt_label,'bad_barcode');
				var dd = String(checkout[0].payload.circ.due_date()).substr(0,10);
				var tt = checkout[0].payload.record ? checkout[0].payload.record.title() : checkout[0].payload.copy.dummy_title(); 
				$w(dd_label, dd);
				util.widgets.remove_children(tt_label);
				$w(tt_label, tt);
				if ($('enable_print').checked) {
					var print_params = { 
						'patron' : g.patron, 
						'lib' : g.data.hash.aou[ g.data.list.au[0].ws_ou() ],
						'staff' : g.data.list.au[0],
						//'header' : g.data.print_list_templates.checkout.header,
						'line_item' : g.data.print_list_templates.checkout.line_item,
						//'footer' : g.data.print_list_templates.checkout.footer,
						'type' : g.data.print_list_templates.checkout.type,
						'list' : [ { 'barcode' : checkout_params.barcode, 'title' : tt, 'due_date' : dd } ],
						'silent' : true,
						'print_strategy' : 'dos.print',
					};
					g.print.tree_list( print_params );
				}
			} else if (
				test_event(checkout, 1212 /* PATRON_EXCEEDS_OVERDUE_COUNT */) ||
				test_event(checkout, 1213 /* PATRON_BARRED */) ||
				test_event(checkout, 1215 /* CIRC_EXCEEDS_COPY_RANGE */) ||
				test_event(checkout, 7002 /* PATRON_EXCEEDS_CHECKOUT_COUNT */) ||
				test_event(checkout, 7003 /* COPY_CIRC_NOT_ALLOWED */) ||
				test_event(checkout, 7004 /* COPY_NOT_AVAILABLE */) || 
				test_event(checkout, 7006 /* COPY_IS_REFERENCE */) || 
				test_event(checkout, 7010 /* COPY_ALERT_MESSAGE */) ||
				test_event(checkout, 7016 /* ITEM_ON_HOLDS_SHELF */) ||
				test_event(checkout, 7013 /* PATRON_EXCEEDS_FINES */) 
			) {
				addCSSClass(dd_label,'bad_barcode'); addCSSClass(tt_label,'bad_barcode');
				$w(dd_label,'Failed');
				for (var i = 0; i < checkout.length; i++) $w(tt_label,checkout[i].textcode + ' ');
			} else if (test_event(checkout,1202 /* ITEM_NOT_CATALOGED */)) {

				/**************************************************************************************/
				/* offer pre-cat checkout */

				$w(dd_label,'Pre-Cat?');

				if ( 1 == g.error.yns_alert(
					'Mis-scan or non-cataloged item.  Checkout ("' + checkout_params.barcode + '") as a pre-cataloged item?',
					'Alert',
					'Cancel',
					'Pre-Cat',
					null,
					'Check here to confirm this action',
					'/xul/server/skin/media/images/book_question.png'
				) ) {

					g.data.dummy_title = ''; g.data.dummy_author = ''; g.data.stash('dummy_title','dummy_author');
					JSAN.use('util.window'); var win = new util.window();
					win.open(urls.XUL_PRE_CAT, 'dummy_fields', 'chrome,resizable,modal');
					g.data.stash_retrieve();

					checkout_params.permit_key = checkout[0].payload;
					checkout_params.dummy_title = g.data.dummy_title;
					checkout_params.dummy_author = g.data.dummy_author;
					checkout_params.precat = 1;

					if (checkout_params.dummy_title != '') { 
						process_barcoded_item( checkout_params, dd_label, tt_label ); 
					} else { 
						throw(checkout); 
					}

				} else {
					throw(checkout);
				}
			} else if (test_event(checkout, 1702 /* OPEN_CIRCULATION_EXISTS */)) {

				/**************************************************************************************/
				/* offer to checkin an already circulating item */

				addCSSClass(dd_label,'bad_barcode'); $w(dd_label,'Check In?');
				addCSSClass(tt_label,'bad_barcode'); for (var i = 0; i < checkout.length; i++) $w(tt_label,checkout[i].textcode + ' ');
				g.network.simple_request('FM_ACP_RETRIEVE_VIA_BARCODE',[checkout_params.barcode],
					function(req) {
						try {
							var my_copy = req.getResultObject();
							if (typeof my_copy.ilsevent != 'undefined') throw(my_copy);
							g.network.simple_request('FM_CIRC_RETRIEVE_VIA_COPY',[ses(),my_copy.id(),1],
								function(rreq) {
									try {
										var my_circ = rreq.getResultObject();
										if (typeof my_circ.ilsevent != 'undefined') throw(my_copy);
										my_circ = my_circ[0];
										var due_date = my_circ.due_date() ? my_circ.due_date().substr(0,10) : null;
										JSAN.use('util.date'); var today = util.date.formatted_date(new Date(),'%F');
										var msg = 'This item ("' + checkout_params.barcode + '") is already circulating.';
										if (due_date) if (today > due_date) msg += '\nIt was due on ' + due_date + '.\n';
										var r = g.error.yns_alert(
											msg, 'Check Out Failed','Cancel','Checkin then Checkout', 
											due_date ? (today > due_date ? 'Forgiving Checkin then Checkout' : null) : null,
											'Check here to confirm this message'
										);
										JSAN.use('circ.util');
										switch(r) {
											case 1:
												circ.util.checkin_via_barcode( ses(), { 'barcode' : checkout_params.barcode } );
												process_barcoded_item( checkout_params, dd_label, tt_label ); 
											break;
											case 2:
												circ.util.checkin_via_barcode( ses(), { 'barcode' : checkout_params.barcode }, due_date );
												process_barcoded_item( checkout_params, dd_label, tt_label ); 
											break;
										}
									} catch(E) {
										addCSSClass(dd_label,'bad_barcode'); addCSSClass(tt_label,'bad_barcode');
										$w(dd_label,'Error');
										if (E.length) {
											for (var i = 0; i < E.length; i++) $w(tt_label,E[i].textcode + ' ');
										} else {
											$w(tt_label,E);
										}
									}
								}
							);
						} catch(E) {
							addCSSClass(dd_label,'bad_barcode'); addCSSClass(tt_label,'bad_barcode');
							$w(dd_label,'Error');
							if (E.length) {
								for (var i = 0; i < E.length; i++) $w(tt_label,E[i].textcode + ' ');
							} else {
								$w(tt_label,E);
							}
						}
					}
				);
			} else if (test_event(checkout, 7014 /* COPY_IN_TRANSIT */)) {

				/**************************************************************************************/
				/* offer to abort an existing transit for the item attempting to be checked out */

				addCSSClass(dd_label,'bad_barcode'); $w(dd_label,'Abort transit?');
				addCSSClass(tt_label,'bad_barcode'); for (var i = 0; i < checkout.length; i++) $w(tt_label,checkout[i].textcode + ' ');
				var r = g.error.yns_alert('This item ("' + checkout_params.barcode + '") is in transit.','Check Out Failed','Cancel','Abort Transit then Checkout',null,'Check here to confirm this message');
				switch(r) {
					case 1:
						var robj = g.network.simple_request('FM_ATC_VOID',[ ses(), { 'barcode' : checkout_params.barcode } ]);
						if (typeof robj.ilsevent == 'undefined') {
							process_barcoded_item( checkout_params, dd_label, tt_label ); 
						} else {
							throw(robj);
						}
					break;
				}
			} else {
				throw(checkout);
			}

		} catch(E) {
			addCSSClass(dd_label,'bad_barcode'); addCSSClass(tt_label,'bad_barcode');
			$w(dd_label,'Error');
			if (E.length) {
				for (var i = 0; i < E.length; i++) $w(tt_label,E[i].textcode + ' ');
			} else {
				$w(tt_label,E);
			}
			//g.error.standard_unexpected_error_alert('Error in barcode_entry.js:process_barcoded_item_callack()',E);
		}
	}
	
/*********************************************************************************************************/
/* process the patron submission */

		function submit() {
			var tb;
			try {
				JSAN.use('util.sound'); var sound = new util.sound();
				tb = $('barcode_tb');
				var barcode = tb.value;

				barcode = String( barcode ).replace( /\s+/g, '' );

				if (!barcode) { sound.bad(); add_msg('No barcode entered.'); tb.select(); tb.focus(); return; }

				tb.disabled = true; $('submit_cb').disabled = true; $('quick_checkout').disabled = true;
				$('progress').setAttribute('hidden','false');
				g.network.simple_request('PATRON_BARCODE_EXISTS',[ ses(), barcode ],
					function(req) {
						$('progress').setAttribute('hidden','true');
						var robj = req.getResultObject();
						if (typeof robj.ilsevent != 'undefined') {
							tb.disabled = false; tb.select(); tb.focus(); $('submit_cb').disabled = false; $('quick_checkout').disabled = false;
							sound.bad();
							add_msg('Problem retrieving ' + barcode + '.  Please report this message: \n' + js2JSON(robj));
							return;
						} else if (robj == 0) {
							tb.disabled = false; tb.select(); tb.focus(); $('submit_cb').disabled = false; $('quick_checkout').disabled = false;
							sound.bad(); 
							add_msg('Barcode ' + barcode + ' not found.');
							return;
						}

						sound.good(); g.barcode = barcode;

						if ($('quick_checkout').checked) {
							g.network.simple_request(
								'FM_AU_RETRIEVE_VIA_BARCODE',
								[ ses(), barcode ],
								function(req) {
									var p = req.getResultObject();	
									g.patron = p;
									$w('patron_name',
										p.family_name() + ', ' + p.first_given_name() + ' ' +
										( p.second_given_name() ? p.second_given_name() : '' )
									);
									JSAN.use('patron.util'); patron.util.set_penalty_css(p);
									alert_message(p);

									g.patron_id = p.id();
									/**/
									util.widgets.remove_children( 'status' );
									$("checkout_barcode_entry_textbox").disabled = false;
									$("checkout_barcode_entry_textbox").focus();
									$("checkout_duedate_menu").disabled = false;
									$("checkout_menulist").disabled = false;
									$("checkout_submit").disabled = false;
									$("done").disabled = false;
									$("retrieve_patron").disabled = false;
									$("strict_barcode").disabled = false;
									$("enable_print").disabled = false;
									/**/
								}
							);
						} else {
							retrieve_patron(true);
						}
					}
				);
			} catch(E) {
				tb.select(); tb.focus();
				g.error.standard_unexpected_error_alert('barcode_entry.xul:submit()',E);
			}
		}

/*********************************************************************************************************/
/* finish with simple checkout and go back to patron submission form */

		function done() {
			try {
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
				$w('patron_name','');
				g.barcode = '';
				var nl = document.getElementsByAttribute('name','lineitem');
				var remove_these = [];
				for (var i = 0; i < nl.length; i++) remove_these.push( nl[i] ); // a nodelist is not a simple array we can safely delete the dom nodes from
				for (var i = 0; i < remove_these.length; i++) remove_these[i].parentNode.removeChild( remove_these[i] );
				$("checkout_barcode_entry_textbox").value = ''; $("checkout_menulist").value = 'barcode';
				$("checkout_barcode_entry_textbox").disabled = true; $("checkout_duedate_menu").disabled = true;
				$("checkout_menulist").disabled = true; $("checkout_submit").disabled = true;
				$('barcode_tb').disabled = false; $('barcode_tb').value = ''; $('barcode_tb').select(); $('barcode_tb').focus(); $('submit_cb').disabled = false;
				$('quick_checkout').disabled = false; $("done").disabled = true; $("retrieve_patron").disabled = true;
				$("strict_barcode").disabled = true; $("enable_print").disabled = true;

			} catch(E) {
				g.error.standard_unexpected_error_alert('barcode_entry.xul:done()',E);
			}
		}

/*********************************************************************************************************/
/* take a patron object and alert any needed messages based on the patron */

		function alert_message(patron) {
				g.network.simple_request(
					'FM_AHR_COUNT_RETRIEVE',
					[ ses(), patron.id() ],
					function(req) {
						try {
							var msg = ''; g.stop_checkouts = false;
							if (patron.alert_message()) msg += '"' + patron.alert_message() + '"\n';
							if (g.barcode) {
								if (patron.cards()) for (var i = 0; i < patron.cards().length; i++) {
									//alert('card #'+i+' == ' + js2JSON(patron.cards()[i]));
									if ( (patron.cards()[i].barcode()==g.barcode) && ( ! get_bool(patron.cards()[i].active()) ) ) {
										msg += 'Patron account retrieved with an INACTIVE card.\n';
										g.stop_checkouts = true;
									}
								}
							}
							if (get_bool(patron.barred())) {
								msg += 'Patron account is BARRED.\n';
								g.stop_checkouts = true;
							}
							if (!get_bool(patron.active())) {
								msg += 'Patron account is INACTIVE.\n';
								g.stop_checkouts = true;
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
									msg += 'Patron account is EXPIRED.\n';
									g.stop_checkouts = true;
								}
							}
							var holds = req.getResultObject();
							if (holds.ready && holds.ready > 0) msg += 'Holds available: ' + holds.ready;
							if (msg) {
								g.error.yns_alert(msg,'Alert Message','OK',null,null,'Check here to confirm this message.');
							}
						} catch(E) {
							g.error.standard_unexpected_error_alert('Error showing patron alert and holds availability.',E);
						}
					}
				);
		}

/*********************************************************************************************************/
/* append text to an error section onscreen */

		function add_msg(text) {
			var x = $('status');
			var d = $c('description');
			x.appendChild(d);
			$w(d,text);
			d.setAttribute('style','color: red');
		}

/*********************************************************************************************************/
/* Open the usual patron display in current tab */

		function spawn(barcode) {
			try {
				var loc = urls.XUL_PATRON_DISPLAY; // + '?barcode=' + window.escape(barcode);

				if (typeof window.xulG == 'object' && typeof window.xulG.set_tab == 'function') {

					window.xulG.set_tab( loc, {}, { 'barcode' : barcode } );
				} else {

					location.href = loc + '?barcode=' + window.escape(barcode);
;
				}
			} catch(E) {
				g.error.standard_unexpected_error_alert('spawning patron display',E);
			}
		}

/*********************************************************************************************************/
/* Open the usual patron display */

		function retrieve_patron(same_tab) {
			try {
				if (same_tab) {
					if (typeof window.xulG == 'object' && typeof window.xulG.set_tab == 'function') {
						var url = urls.XUL_PATRON_DISPLAY; 
						window.xulG.set_tab( url, {}, { 'barcode' : g.barcode });
					}
				} else {
					if (typeof window.xulG == 'object' && typeof window.xulG.new_tab == 'function') {
						var url = urls.XUL_PATRON_DISPLAY; 
						window.xulG.new_tab( url, {}, { 'barcode' : g.barcode });
					}
				}
			} catch(E) {
				g.error.standard_unexpected_error_alert('Error retrieving patron',E);
			}
		}

/*********************************************************************************************************/
/* used by the menu/tab code for determining focus upon a tab switch */

		function default_focus() { try { setTimeout( function() { if (g.barcode) $('checkout_barcode_entry_textbox').focus(); else $('barcode_tb').focus(); }, 0); } catch(E) {} }

