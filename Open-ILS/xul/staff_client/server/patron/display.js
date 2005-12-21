dump('entering patron/display.js\n');

if (typeof patron == 'undefined') patron = {};
patron.display = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.window'); this.window = new util.window();
	JSAN.use('util.network'); this.network = new util.network();
	this.w = window;
}

patron.display.prototype = {

	'init' : function( params ) {

		var obj = this;

		obj.session = params['session'];
		obj.barcode = params['barcode'];

		JSAN.use('OpenILS.data'); this.OpenILS = {}; 
		obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'});

		JSAN.use('util.deck'); 
		obj.right_deck = new util.deck('patron_right_deck');
		obj.left_deck = new util.deck('patron_left_deck');

		function spawn_checkout_interface() {
			obj.right_deck.set_iframe(
				urls.remote_checkout
				+ '?session=' + window.escape( obj.session )
				+ '&patron_id=' + window.escape( obj.patron.id() ),
				{},
				{ 
					'on_checkout' : function(checkout) {
						var c = obj.summary_window.g.summary.patron.checkouts();
						c.push( checkout );
						obj.summary_window.g.summary.patron.checkouts( c );
						obj.summary_window.g.summary.controller.render('patron_checkouts');
					}
				}
			);
			dump('obj.right_deck.node.childNodes.length = ' + obj.right_deck.node.childNodes.length + '\n');
		}

		JSAN.use('util.controller'); obj.controller = new util.controller();
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
							try { obj.summary_window.refresh(); } catch(E) { dump(E + '\n'); }
							try { obj.refresh_deck(); } catch(E) { dump(E + '\n'); }
						}
					],
					'cmd_patron_checkout' : [
						['command'],
						spawn_checkout_interface
					],
					'cmd_patron_items' : [
						['command'],
						function(ev) {
							obj.right_deck.set_iframe(
								urls.remote_patron_items
								+ '?session=' + window.escape( obj.session )
								+ '&patron_id=' + window.escape( obj.patron.id() ),
								{},
								{
									'checkouts' : obj.patron.checkouts()
								}
							);
							dump('obj.right_deck.node.childNodes.length = ' + obj.right_deck.node.childNodes.length + '\n');
						}
					],
					'cmd_patron_holds' : [
						['command'],
						function(ev) {
							obj.right_deck.set_iframe(
								urls.remote_patron_holds	
								+ '?session=' + window.escape( obj.session )
								+ '&patron_id=' + window.escape( obj.patron.id() ),
								{},
								{
									//FIXME//'holds' : obj.patron.holds()
								}
							);
							dump('obj.right_deck.node.childNodes.length = ' + obj.right_deck.node.childNodes.length + '\n');
						}
					],
					'cmd_patron_bills' : [
						['command'],
						function(ev) {
							obj.right_deck.set_iframe(
								urls.remote_patron_bills
								+ '?session=' + window.escape( obj.session )
								+ '&patron_id=' + window.escape( obj.patron.id() ),
								{},
								{
									//FIXME//'bills' : obj.patron.bills()
								}
							);
							dump('obj.right_deck.node.childNodes.length = ' + obj.right_deck.node.childNodes.length + '\n');
						}
					],
					'cmd_patron_edit' : [
						['command'],
						function(ev) {
							obj.right_deck.set_iframe(
								urls.remote_patron_edit
								+ '?ses=' + window.escape( obj.session )
								+ '&usr=' + window.escape( obj.patron.id() ),
								{}, {}
							);
							dump('obj.right_deck.node.childNodes.length = ' + obj.right_deck.node.childNodes.length + '\n');
						}
					],
					'cmd_patron_info' : [
						['command'],
						function(ev) {
							obj.right_deck.set_iframe(urls.remote_patron_info);
							dump('obj.right_deck.node.childNodes.length = ' + obj.right_deck.node.childNodes.length + '\n');
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
								if (obj.summary_window) {
									//FIXME//bills should become a virtual field
									if (obj.summary_window.g.summary.patron.bills.length > 0)
										e.setAttribute('style','background-color: yellow');
									if (obj.summary_window.g.summary.patron.standing() == 2)
										e.setAttribute('style','background-color: lightred');
								}

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

		if (obj.barcode) {
			obj.controller.view.PatronNavBar.selectedIndex = 1;
			obj.controller.view.patron_name.setAttribute('value','Retrieving...');
			var frame = obj.left_deck.set_iframe(
				urls.remote_patron_summary
				+'?session=' + window.escape(obj.session)
				+'&barcode=' + window.escape(obj.barcode), 
				{},
				{
					'on_finished' : function(patron) {
						obj.patron = patron; obj.controller.render();
						if (!obj._checkout_spawned) {
							spawn_checkout_interface();
							obj._checkout_spawned = true;
						}
					}
				}
			);
			obj.summary_window = frame.contentWindow;
		} else {
			obj.controller.view.PatronNavBar.selectedIndex = 0;
			var form_frame = obj.left_deck.set_iframe(
				urls.remote_patron_search_form
				+'?session=' + window.escape(obj.session),
				{},
				{
					'on_submit' : function(query) {
						var list_frame = obj.right_deck.reset_iframe(
							urls.remote_patron_search_result
							+'?session=' + window.escape(obj.session) + '&' + query,
							{},
							{
							}
						);
						obj.search_result = list_frame.contentWindow;
					}
				}
			);
			obj.search_window = form_frame.contentWindow;
			obj._checkout_spawned = true;
		}
	},

	'_checkout_spawned' : false,

	'refresh_deck' : function() {
		var obj = this;
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		for (var i = 0; i < obj.right_deck.node.childNodes.length; i++) {
			try {

				var f = obj.right_deck.node.childNodes[i];
				var w = f.contentWindow;
				if (typeof w.refresh == 'function') {
					w.refresh();
				}

			} catch(E) {
				dump('refresh_deck: ' + E + '\n');
			}
		}
	},
}

dump('exiting patron/display.js\n');
