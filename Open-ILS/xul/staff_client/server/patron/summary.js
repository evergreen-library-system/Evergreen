dump('entering patron.summary.js\n');

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

		obj.session = params['session'];
		obj.barcode = params['barcode'];
		obj.id = params['id'];

		JSAN.use('OpenILS.data'); this.OpenILS = {}; 
		obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'});

		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				control_map : {
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'patron_name' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.family_name() + ', ' + obj.patron.first_given_name()
								);
								e.setAttribute('style','background-color: lime');
								//FIXME//bills should become a virtual field
								if (obj.patron.bills.length > 0)
									e.setAttribute('style','background-color: yellow');
								if (obj.patron.standing() == 2)
									e.setAttribute('style','background-color: lightred');

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
					'patron_standing' : [
						['render'],
						function(e) {
							return function() {
								e.setAttribute('value',
									obj.OpenILS.data.hash.cst[
										obj.patron.standing()
									].value()
								);
							};
						}
					],
					'patron_credit' : [
						['render'],
						function(e) {
							return function() { 
								JSAN.use('util.money');
								e.setAttribute('value',
									util.money.cents_as_dollars(
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
								JSAN.use('util.money');
								var total = 0;
								//FIXME//adjust when .bills becomes a virtual field
								for (var i = 0; i < obj.patron.bills.length; i++) {
									total += util.money.dollars_float_to_cents_integer( 
										obj.patron.bills[i].balance_owed() 
									);
								}
								e.setAttribute('value',
									util.money.cents_as_dollars( total )
								);
							};
						}
					],
					'patron_checkouts' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.checkouts().length	
								);
							};
						}
					],
					'patron_overdue' : [
						['render'],
						function(e) {
							return function() { 
								//FIXME//Get Bill to do this correctly on server side
								JSAN.use('util.date');
								var total = 0;
								for (var i = 0; i < obj.patron.checkouts().length; i++) {
									var circ = obj.patron.checkouts()[i];
									var due_date = circ.due_date();
									due_date = due_date.substr(0,4) 
										+ due_date.substr(5,2) + due_date.substr(8,2);
									var today = util.date.formatted_date( new Date() , '%Y%m%d' );
									if (today > due_date) total++;
								}
								e.setAttribute('value',
									total
								);
							};
						}
					],
					'patron_holds' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.hold_requests().length
								);
							};
						}
					],
					'patron_holds_available' : [
						['render'],
						function(e) {
							return function() { 
								var total = 0;
								for (var i = 0; i < obj.patron.hold_requests().length; i++) {
									var hold = obj.patron.hold_requests()[i];
									if (hold.capture_time()) total++;
								}
								e.setAttribute('value',
									total
								);
							};
						}
					],
					'patron_surveys' : [
						['render'],
						function(e) {
							return function() {
								while(e.lastChild){e.removeChild(e.lastChild);} /* empty vbox */
								JSAN.use('util.date'); JSAN.use('util.functional');
								var surveys = obj.OpenILS.data.list.asv;
								var sr = obj.patron.survey_responses();
								for (var i  = 0; i < surveys.length; i++) {
									var survey = surveys[i];
									var hbox = document.createElement('hbox');
									e.appendChild(hbox);
									var sname = document.createElement('label');
									sname.setAttribute('value',survey.name());
									hbox.appendChild(sname);
									var responses = sr[survey.id()];
									var vbox = document.createElement('vbox');
									hbox.appendChild(vbox);
									var sdate = document.createElement('label');
									sdate.setAttribute('value','Not Taken');
									vbox.appendChild(sdate);
									if (responses && responses.length > 0) {
										var response = responses.pop(); // last response
										var date;
										if (response.effective_date()) {
											date = util.date.formatted_date( response.effective_date(), '%D' );
										} else {
											date = util.date.formatted_date( response.answer_date(), '%D' );
										}
										sdate.setAttribute('value',date);
										var answer = util.functional.find_id_object_in_list( // first answer
											util.functional.find_id_object_in_list(
												survey.questions(),
												response.question()
											).answers(),
											response.answer()
										).answer();
										var ans = document.createElement('label');
										ans.setAttribute('value',answer);
										vbox.appendChild(ans);
									}
								}
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
								e.setAttribute('value',
									obj.patron.ident_value()
								);
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
								e.setAttribute('value',
									obj.patron.ident_value2()
								);
							};
						}
					],
					'patron_date_of_birth' : [
						['render'],
						function(e) {
							return function() { 
								e.setAttribute('value',
									obj.patron.dob()
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
							};
						}
					]
				}
			}
		);

		obj.retrieve();

	},

	'retrieve' : function() {

		try {

			var obj = this;

			var chain = [];

			// Retrieve the patron
			chain.push(
				function() {
					try {
						var robj;
						if (obj.barcode && obj.barcode != 'null') {
							robj = obj.network.request(
								api.FM_AU_RETRIEVE_VIA_BARCODE.app,
								api.FM_AU_RETRIEVE_VIA_BARCODE.method,
								[ obj.session, obj.barcode ]
							);
						} else if (obj.id && obj.id != 'null') {
							robj = obj.network.request(
								api.FM_AU_RETRIEVE_VIA_ID.app,
								api.FM_AU_RETRIEVE_VIA_ID.method,
								[ obj.session, obj.id ]
							);
						} else {
							throw('summary: No barcode or id');
						}
						if (robj) {

							if (instanceOf(robj,au)) {

								obj.patron = robj;

							} else if (typeof robj.ilsevent != 'undefined') {

								if (robj.ilsevent == 0) {

									// are we moving toward a payload here?

								} else {
									var error = robj.ilsevent + ' : ' 
										+ obj.error.get_ilsevent( robj.ilsevent );
									throw(error);
								}
							} else {

								throw('result is not an au fm object');
							}
						} else {

							throw('result == false');
						}

					} catch(E) {
						var error = ('patron.summary.retrieve : ' + js2JSON(E));
						obj.error.sdump('D_ERROR',error);
						throw(error);
					}
				}
			);

			// Retrieve the bills
			chain.push(
				function() {
					try {
						var bills = obj.network.request(
							api.FM_MOBTS_HAVING_BALANCE.app,
							api.FM_MOBTS_HAVING_BALANCE.method,
							[ obj.session, obj.patron.id() ]
						);
						//FIXME// obj.patron.bills( bills );
						obj.patron.bills = bills;
					} catch(E) {
						var error = ('patron.summary.retrieve : ' + js2JSON(E));
						obj.error.sdump('D_ERROR',error);
						throw(error);
					}
				}
			);

			// Retrieve the checkouts
			chain.push(
				function() {
					try {
						var checkouts = obj.network.request(
							api.FM_CIRC_RETRIEVE_VIA_USER.app,
							api.FM_CIRC_RETRIEVE_VIA_USER.method,
							[ obj.session, obj.patron.id() ]
						);
						obj.patron.checkouts( checkouts );
					} catch(E) {
						var error = ('patron.summary.retrieve : ' + js2JSON(E));
						obj.error.sdump('D_ERROR',error);
						throw(error);
					}
				}
			);

			// Retrieve the holds
			chain.push(
				function() {
					try {
						var holds = obj.network.request(
							api.FM_AHR_RETRIEVE.app,
							api.FM_AHR_RETRIEVE.method,
							[ obj.session, obj.patron.id() ]
						);
						obj.patron.hold_requests( holds );
					} catch(E) {
						var error = ('patron.summary.retrieve : ' + js2JSON(E));
						obj.error.sdump('D_ERROR',error);
						throw(error);
					}
				}
			);

			// Retrieve the survey responses for required surveys
			chain.push(
				function() {
					try {
						var surveys = obj.OpenILS.data.list.asv;
						var survey_responses = {};
						for (var i = 0; i < surveys.length; i++) {
							var s = obj.network.request(
								api.FM_ASVR_RETRIEVE.app,
								api.FM_ASVR_RETRIEVE.method,
								[ obj.session, surveys[i].id(), obj.patron.id() ]
							);
							survey_responses[ i ] = s;
						}
						obj.patron.survey_responses( survey_responses );
					} catch(E) {
						var error = ('patron.summary.retrieve : ' + js2JSON(E));
						obj.error.sdump('D_ERROR',error);
						throw(error);
					}
				}
			);

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
				//location.href = urls.XUL_PATRON_BARCODE_ENTRY + '?session=' + window.escape(obj.session);
				obj.patron = new au();
					obj.patron.checkouts( [] );
					obj.patron.hold_requests( [] );
					obj.patron.bills = [];
					var home_ou = new aou();
					obj.patron.home_ou( home_ou );
					var card = new ac(); card.barcode( obj.barcode );
					obj.patron.card( card );
					obj.patron.family_name( 'Could not retrieve patron' );
				var error = ('FIXME: Need better alert and error handling.\nProblem with barcode: ' 
					+ obj.barcode + '\n' + E);

				if (typeof window.xulG == 'object' && typeof window.xulG.on_error == 'function') {
					obj.error.sdump('D_PATRON_SUMMARY',
						'patron.summary: Calling external .on_error()\n');
					window.xulG.on_error(error);
				} else {
					obj.error.sdump('D_PATRON_SUMMARY','patron.summary: No external .on_error()\n');
				}

			}
			this.exec.chain( chain );

		} catch(E) {
			var error = ('patron.summary.retrieve : ' + js2JSON(E));
			this.error.sdump('D_ERROR',error);
			if (typeof window.xulG == 'object' && typeof window.xulG.on_error == 'function') {
				window.xulG.on_error(error);
			} else {
				alert(error);
			}
		}
	}
}

dump('exiting patron.summary.js\n');
