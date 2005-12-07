dump('entering patron/display.js\n');

if (typeof patron == 'undefined') patron = {};
patron.display = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('main.window'); this.window = new main.window();
	JSAN.use('main.network'); this.network = new main.network();
	this.w = window;
}

patron.display.prototype = {

	'init' : function( params ) {

		var obj = this;

		obj.session = params['session'];
		obj.barcode = params['barcode'];

		JSAN.use('OpenILS.data'); this.OpenILS = {}; 
		obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init(true);

		JSAN.use('util.deck');  obj.deck = new util.deck('patron_deck');

		JSAN.use('main.controller'); obj.controller = new main.controller();
		obj.controller.init(
			{
				control_map : {
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_patron_refresh' : [
						['command'],
						function(ev) {
							obj.controller.view.patron_name.setAttribute(
								'value','Retrieving...'
							);
							obj.retrieve();
						}
					],
					'cmd_patron_checkout' : [
						['command'],
						function(ev) {
							obj.deck.set_iframe(
								'/xul/server/circ/checkout.xul?session='
								+ window.escape( obj.session )
								+ '&patron_id='
								+ window.escape( obj.patron.id() )
							);
							dump('obj.deck.node.childNodes.length = ' + obj.deck.node.childNodes.length + '\n');
						}
					],
					'cmd_patron_items' : [
						['command'],
						function(ev) {
							obj.deck.set_iframe('data:text/html,<h1>Items Here</h1>');
							dump('obj.deck.node.childNodes.length = ' + obj.deck.node.childNodes.length + '\n');
						}
					],
					'cmd_patron_holds' : [
						['command'],
						function(ev) {
							obj.deck.set_iframe('data:text/html,<h1>Holds Here</h1>');
							dump('obj.deck.node.childNodes.length = ' + obj.deck.node.childNodes.length + '\n');
						}
					],
					'cmd_patron_bills' : [
						['command'],
						function(ev) {
							obj.deck.set_iframe('data:text/html,<h1>Bills Here</h1>');
							dump('obj.deck.node.childNodes.length = ' + obj.deck.node.childNodes.length + '\n');
						}
					],
					'cmd_patron_edit' : [
						['command'],
						function(ev) {
							obj.deck.set_iframe('data:text/html,<h1>Edit Here</h1>');
							dump('obj.deck.node.childNodes.length = ' + obj.deck.node.childNodes.length + '\n');
						}
					],
					'cmd_patron_info' : [
						['command'],
						function(ev) {
							obj.deck.set_iframe('data:text/html,<h1>Info Here</h1>');
							dump('obj.deck.node.childNodes.length = ' + obj.deck.node.childNodes.length + '\n');
						}
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
									obj.patron.checkouts.length	
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
									var item = obj.patron.checkouts()[i];
									var due_date = item.circ.due_date();
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
									obj.patron.hold_requests.length
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

		var patron;
		try {

			var obj = this;

			var chain = [];

			// Retrieve the patron
			chain.push(
				function() {
					try {
						var patron = obj.network.request(
							'open-ils.actor',
							'open-ils.actor.user.fleshed.retrieve_by_barcode',
							[ obj.session, obj.barcode ]
						);
						if (patron) {

							if (instanceOf(patron,au)) {

								obj.patron = patron;

							} else {

								throw('patron is not an au fm object');
							}
						} else {

							throw('patron == false');
						}

					} catch(E) {
						var error = ('patron.display.retrieve : ' + js2JSON(E));
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
							'open-ils.actor',
							'open-ils.actor.user.transactions.have_balance',
							[ obj.session, obj.patron.id() ]
						);
						//FIXME// obj.patron.bills( bills );
						obj.patron.bills = bills;
					} catch(E) {
						var error = ('patron.display.retrieve : ' + js2JSON(E));
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
							'open-ils.circ',
							'open-ils.circ.actor.user.checked_out',
							[ obj.session, obj.patron.id() ]
						);
						obj.patron.checkouts( checkouts );
					} catch(E) {
						var error = ('patron.display.retrieve : ' + js2JSON(E));
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
							'open-ils.circ',
							'open-ils.circ.holds.retrieve',
							[ obj.session, obj.patron.id() ]
						);
						obj.patron.hold_requests( holds );
					} catch(E) {
						var error = ('patron.display.retrieve : ' + js2JSON(E));
						obj.error.sdump('D_ERROR',error);
						throw(error);
					}
				}
			);

			// Update the screen
			chain.push( function() { obj.controller.render(); } );

			// Do it
			JSAN.use('util.exec'); obj.exec = new util.exec();
			obj.exec.on_error = function(E) {
				location.href = '/xul/server/patron/patron_barcode_entry.xul?session=' + window.escape(obj.session);
				alert('FIXME: Need better alert and error handling.\nProblem with barcode.\n' + E);
			}
			this.exec.chain( chain );

		} catch(E) {
			var error = ('patron.display.retrieve : ' + js2JSON(E));
			this.error.sdump('D_ERROR',error);
			alert(error);
		}
	}
}

dump('exiting patron/display.js\n');
