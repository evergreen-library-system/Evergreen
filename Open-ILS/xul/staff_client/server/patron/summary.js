dump('entering patron.summary.js\n');

function $(id) { return document.getElementById(id); }

if (typeof patron == 'undefined') patron = {};
patron.summary = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.window'); this.window = new util.window();
	JSAN.use('util.network'); this.network = new util.network();
	this.w = window;
}

patron.summary.prototype = {

	'init' : function( params ) {

		var obj = this;

		obj.barcode = params['barcode'];
		obj.id = params['id'];
		if (params['show_name']) {
			document.getElementById('patron_name').hidden = false;
			document.getElementById('patron_name').setAttribute('hidden','false');
		}

		JSAN.use('OpenILS.data'); this.OpenILS = {}; 
		obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'});

		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				control_map : {
					'cmd_broken' : [
						['command'],
						function() { alert($("commonStrings").getString('common.unimplemented')); }
					],
					'patron_alert' : [
						['render'],
						function(e) {
							return function() {
								JSAN.use('util.widgets');
								util.widgets.remove_children( e );
								if (obj.patron.alert_message()) {
									e.appendChild(
										document.createTextNode(
											obj.patron.alert_message()
										)
									);
									e.parentNode.hidden = false;
								} else {
									e.parentNode.hidden = true;
								}
							};
						}
					],
					'patron_usrname' : [
						['render'],
						function(e) {
							return function() {
								e.setAttribute('value',obj.patron.usrname());
							};
						}
					],
					'patron_profile' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.OpenILS.data.hash.pgt[
										obj.patron.profile()
									].name()
								);
							};
						}
					],
					'patron_net_access' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									$("patronStrings").getString('staff.patron.summary.patron_net_access') + 
									' ' + obj.OpenILS.data.hash.cnal[
										obj.patron.net_access_level()
									].name()
								);
							};
						}
					],
					'patron_standing' : [
						['render'],
						function(e) {
							return function() {
							/*
								e.setAttribute('value',
									obj.OpenILS.data.hash.cst[
										obj.patron.standing()
									].value()
								);
							*/
								var e2 = document.getElementById('patron_standing_penalties');
								JSAN.use('util.widgets');
								util.widgets.remove_children(e2);
								var penalties = obj.patron.standing_penalties();
								for (var i = 0; i < penalties.length; i++) {

									var row = document.createElement('row');
									var label = document.createElement('label');

									//x.setAttribute('value',penalties[i].penalty_type());
									label.setAttribute('value',penalties[i].standing_penalty().label());
									row.appendChild(label);

                                    // XXX check a permission here? How to fire the remove action ??? XXX
                                    if (penalties[i].standing_penalty().id() >= 100) {
    									var button = document.createElement('button');
	    								button.setAttribute('label', $("patronStrings").getString('staff.patron.summary.standing_penalty.remove'));
		    							row.appendChild(button);
                                    }

                                    if (penalties[i].standing_penalty().block_list().match(/RENEW/)) addCSSClass(label,'PENALTY_RENEW');
                                    if (penalties[i].standing_penalty().block_list().match(/HOLD/)) addCSSClass(label,'PENALTY_HOLD');
                                    if (penalties[i].standing_penalty().block_list().match(/CIRC/)) addCSSClass(label,'PENALTY_CIRC');

									e2.appendChild(row);
                                    e2.parentNode.parentNode.hidden = false;
								}
							};
						}
					],
					'patron_credit' : [
						['render'],
						function(e) {
							return function() { 
								JSAN.use('util.money');
								e.setAttribute('value',
									'$' + 
									util.money.sanitize(
										obj.patron.credit_forward_balance()
									)
								);
							};
						}
					],
					'patron_bill' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value','...');
								obj.network.simple_request(
									'FM_MOUS_RETRIEVE.authoritative',
									[ ses(), obj.patron.id() ],
									function(req) {
										JSAN.use('util.money');
										var robj = req.getResultObject();
										e.setAttribute('value', $("patronStrings").getFormattedString('staff.patron.summary.patron_bill.money', [util.money.sanitize( robj.balance_owed() )]));
									}
								);
								/*
								obj.network.simple_request(
									'FM_MBTS_IDS_RETRIEVE_ALL_HAVING_BALANCE.authoritative',
									[ ses(), obj.patron.id() ],
									function(req) {
										JSAN.use('util.money');
										var list = req.getResultObject();
										if (typeof list.ilsevent != 'undefined') {
											e.setAttribute('value', '??? See Bills');
											return;
										}
										var sum = 0;
										for (var i = 0; i < list.length; i++) {
											var robj = typeof list[i] == 'object' ? list[i] : obj.network.simple_request('FM_MBTS_RETRIEVE.authoritative',[ses(),list[i]]);
											sum += util.money.dollars_float_to_cents_integer( robj.balance_owed() );
										} 
										if (sum > 0) addCSSClass(document.documentElement,'PATRON_HAS_BILLS');
										JSAN.use('util.money');
										e.setAttribute('value', '$' + util.money.sanitize( util.money.cents_as_dollars( sum ) ));
									}
								);
								*/
							};
						}
					],
					'patron_checkouts' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value','...');
								var e2 = document.getElementById( 'patron_overdue' ); if (e2) e2.setAttribute('value','...');
								var e3 = document.getElementById( 'patron_claimed_returned' ); if (e3) e3.setAttribute('value','...');
								var e4 = document.getElementById( 'patron_long_overdue' ); if (e4) e4.setAttribute('value','...');
								var e5 = document.getElementById( 'patron_lost' ); if (e5) e5.setAttribute('value','...');
								var e6 = document.getElementById( 'patron_noncat' ); if (e6) e6.setAttribute('value','...');
								obj.network.simple_request(
									'FM_CIRC_COUNT_RETRIEVE_VIA_USER.authoritative',
									[ ses(), obj.patron.id() ],
									function(req) {
										try {
											var robj = req.getResultObject();
											e.setAttribute('value', robj.out + robj.overdue + robj.claims_returned + robj.long_overdue );
											if (e2) e2.setAttribute('value', robj.overdue	);
											if (e3) e3.setAttribute('value', robj.claims_returned	);
											if (e4) e4.setAttribute('value', robj.long_overdue	);
											if (e5) e5.setAttribute('value', robj.lost	);
										} catch(E) {
											alert(E);
										}
									}
								);
								obj.network.simple_request(
									'FM_ANCC_RETRIEVE_VIA_USER.authoritative',
									[ ses(), obj.patron.id() ],
									function(req) {
										var robj = req.getResultObject();
										if (e6) e6.setAttribute('value',robj.length);
									}
								);
							};
						}
					],
					'patron_overdue' : [
						['render'],
						function(e) {
							return function() { 
								/* handled by 'patron_checkouts' */
							};
						}
					],
					'patron_holds' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value','...');
								var e2 = document.getElementById('patron_holds_available');
								if (e2) e2.setAttribute('value','...');
								obj.network.simple_request(
									'FM_AHR_COUNT_RETRIEVE.authoritative',
									[ ses(), obj.patron.id() ],
									function(req) {
										e.setAttribute('value',
											req.getResultObject().total
										);
										if (e2) e2.setAttribute('value',
											req.getResultObject().ready
										);
									}
								);
							};
						}
					],
					'patron_holds_available' : [
						['render'],
						function(e) {
							return function() { 
								/* handled by 'patron_holds' */
							};
						}
					],
					'patron_card' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.card().barcode()
								);
							};
						}
					],
					'patron_ident_type_1' : [
						['render'],
						function(e) {
							return function() { 
								var ident_string = '';
								var ident = obj.OpenILS.data.hash.cit[
									obj.patron.ident_type()
								];
								if (ident) ident_string = ident.name()
								e.setAttribute('value',
									ident_string
								);
							};
						}
					],
					'patron_ident_value_1' : [
						['render'],
						function(e) {
							return function() { 
								var val = obj.patron.ident_value();
								val = val.replace(/.+(\d\d\d\d)$/,'xxxx$1');
								e.setAttribute('value', val);
							};
						}
					],
					'patron_ident_type_2' : [
						['render'],
						function(e) {
							return function() { 
								var ident_string = '';
								var ident = obj.OpenILS.data.hash.cit[
									obj.patron.ident_type2()
								];
								if (ident) ident_string = ident.name()
								e.setAttribute('value',
									ident_string
								);
							};
						}
					],
					'patron_ident_value_2' : [
						['render'],
						function(e) {
							return function() { 
								var val = obj.patron.ident_value2();
								val = val.replace(/.+(\d\d\d\d)$/,'xxxx$1');
								e.setAttribute('value', val);
							};
						}
					],
					'patron_date_of_exp' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									$("patronStrings").getString('staff.patron.summary.expires_on') + ' ' + (
										obj.patron.expire_date() ?
										obj.patron.expire_date().substr(0,10) :
										'<Unset>'
									)
								);
							};
						}
					],
					'patron_date_of_birth' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.dob() ?
									obj.patron.dob().substr(0,10) :
									'<Unset>'
								);
							};
						}
					],
					'patron_day_phone' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.day_phone()
								);
							};
						}
					],
					'patron_evening_phone' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.evening_phone()
								);
							};
						}
					],
					'patron_other_phone' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.other_phone()
								);
							};
						}
					],
					'patron_email' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.email()
								);
							};
						}
					],
					'patron_alias' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.alias()
								);
							};
						}
					],
					'patron_photo_url' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('src',
									obj.patron.photo_url()
								);
							};
						}
					],
					'patron_library' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.OpenILS.data.hash.aou[
										obj.patron.home_ou()
									].shortname()
								);
								e.setAttribute('tooltiptext',
									obj.OpenILS.data.hash.aou[
										obj.patron.home_ou()
									].name()
								);
							};
						}
					],
					'patron_last_library' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.OpenILS.data.hash.aou[
										obj.patron.home_ou()
									].shortname()
								);
								e.setAttribute('tooltiptext',
									obj.OpenILS.data.hash.aou[
										obj.patron.home_ou()
									].name()
								);
							};
						}
					],
					'patron_mailing_address_street1' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.mailing_address().street1()
								);
								if (!get_bool(obj.patron.mailing_address().valid())){e.setAttribute('style','color: red');}
							};
						}
					],
					'patron_mailing_address_street2' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.mailing_address().street2()
								);
								if (!get_bool(obj.patron.mailing_address().valid())){e.setAttribute('style','color: red');}
							};
						}
					],
					'patron_mailing_address_city' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.mailing_address().city()
								);
								if (!get_bool(obj.patron.mailing_address().valid())){e.setAttribute('style','color: red');}
							};
						}
					],
					'patron_mailing_address_state' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.mailing_address().state()
								);
								if (!get_bool(obj.patron.mailing_address().valid())){e.setAttribute('style','color: red');}
							};
						}
					],
					'patron_mailing_address_post_code' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.mailing_address().post_code()
								);
								if (!get_bool(obj.patron.mailing_address().valid())){e.setAttribute('style','color: red');}
							};
						}
					],
					'patron_physical_address_street1' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.billing_address().street1()
								);
								if (!get_bool(obj.patron.billing_address().valid())){e.setAttribute('style','color: red');}
							};
						}
					],
					'patron_physical_address_street2' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.billing_address().street2()
								);
								if (!get_bool(obj.patron.billing_address().valid())){e.setAttribute('style','color: red');}
							};
						}
					],
					'patron_physical_address_city' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.billing_address().city()
								);
								if (!get_bool(obj.patron.billing_address().valid())){e.setAttribute('style','color: red');}
							};
						}
					],
					'patron_physical_address_state' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.billing_address().state()
								);
								if (!get_bool(obj.patron.billing_address().valid())){e.setAttribute('style','color: red');}
							};
						}
					],
					'patron_physical_address_post_code' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.billing_address().post_code()
								);
								if (!get_bool(obj.patron.billing_address().valid())){e.setAttribute('style','color: red');}
							};
						}
					]
				}
			}
		);

		obj.retrieve();

		try {
			var caption = document.getElementById("PatronSummaryContact_caption");
			var arrow = document.getAnonymousNodes(caption)[0];
			var gb_content = document.getAnonymousNodes(caption.parentNode)[1];
			arrow.addEventListener(
				'click',
				function() {
					setTimeout(
						function() {
							//alert('setting shrink_state to ' + gb_content.hidden);
							//caption.setAttribute('shrink_state',gb_content.hidden);
							netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
							JSAN.use('util.file'); var file = new util.file('patron_id_shrink');
							file.set_object(String(gb_content.hidden)); file.close();
						}, 0
					);
				}, false
			);
			//var shrink_state = caption.getAttribute('shrink_state');
			var shrink_state = false;
			netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
			JSAN.use('util.file'); var file = new util.file('patron_id_shrink');
			if (file._file.exists()) {
				shrink_state = file.get_object(); file.close();
			}
			//alert('shrink_state retrieved as ' + shrink_state);
			if (shrink_state != 'false' && shrink_state) {
				JSAN.use('util.widgets');
				//alert('clicking the widget');
				util.widgets.click( arrow );
			}
		} catch(E) {
			obj.error.sdump('D_ERROR','with shrink_state in summary.js: ' + E);
		}
	},

	'retrieve' : function() {

		try {

			var obj = this;

			var chain = [];

			// Retrieve the patron
				function blah_retrieve() {
					try {
						var robj;
						if (obj.barcode && obj.barcode != 'null') {
							robj = obj.network.simple_request(
								'FM_AU_RETRIEVE_VIA_BARCODE.authoritative',
								[ ses(), obj.barcode ]
							);
						} else if (obj.id && obj.id != 'null') {
							robj = obj.network.simple_request(
								'FM_AU_FLESHED_RETRIEVE_VIA_ID',
								[ ses(), obj.id ]
							);
						} else {
							throw($("patronStrings").getString('staff.patron.summary.retrieve.no_barcode'));
						}
						if (robj) {

							if (instanceOf(robj,au)) {

								obj.patron = robj;
								JSAN.use('patron.util');
								document.getElementById('patron_name').setAttribute('value',
									( obj.patron.prefix() ? obj.patron.prefix() + ' ' : '') + 
									obj.patron.family_name() + ', ' + 
									obj.patron.first_given_name() + ' ' +
									( obj.patron.second_given_name() ? obj.patron.second_given_name() + ' ' : '' ) +
									( obj.patron.suffix() ? obj.patron.suffix() : '')
								);
								patron.util.set_penalty_css(obj.patron);
								JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
								data.last_patron = obj.patron.id(); data.stash('last_patron');

							} else {

								throw(robj);

							}
						} else {

							throw(robj);

						}

					} catch(E) {
						throw(E);
					}
				};
				blah_retrieve();

			/*
			// Retrieve the survey responses for required surveys
			chain.push(
				function() {
					try {
						var surveys = obj.OpenILS.data.list.my_asv;
						var survey_responses = {};
						for (var i = 0; i < surveys.length; i++) {
							var s = obj.network.request(
								api.FM_ASVR_RETRIEVE.app,
								api.FM_ASVR_RETRIEVE.method,
								[ ses(), surveys[i].id(), obj.patron.id() ]
							);
							survey_responses[ surveys[i].id() ] = s;
						}
						obj.patron.survey_responses( survey_responses );
					} catch(E) {
						var error = ('patron.summary.retrieve : ' + js2JSON(E));
						obj.error.sdump('D_ERROR',error);
						throw(error);
					}
				}
			);
			*/

			// Update the screen
			chain.push( function() { obj.controller.render(); } );

			// On Complete

			chain.push( function() {

				if (typeof window.xulG == 'object' && typeof window.xulG.on_finished == 'function') {
					obj.error.sdump('D_PATRON_SUMMARY',
						'patron.summary: Calling external .on_finished()\n');
					window.xulG.on_finished(obj.patron);
				} else {
					obj.error.sdump('D_PATRON_SUMMARY','patron.summary: No external .on_finished()\n');
				}

			} );

			// Do it
			JSAN.use('util.exec'); obj.exec = new util.exec();
			obj.exec.on_error = function(E) {

				if (typeof window.xulG == 'object' && typeof window.xulG.on_error == 'function') {
					window.xulG.on_error(E);
				} else {
					alert(js2JSON(E));
				}

			}
			this.exec.chain( chain );

		} catch(E) {
			if (typeof window.xulG == 'object' && typeof window.xulG.on_error == 'function') {
				window.xulG.on_error(E);
			} else {
				alert(js2JSON(E));
			}
		}
	}
}

dump('exiting patron.summary.js\n');
