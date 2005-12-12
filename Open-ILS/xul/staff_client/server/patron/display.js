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
		obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'});

		JSAN.use('util.deck'); 
		obj.right_deck = new util.deck('patron_right_deck');
		obj.left_deck = new util.deck('patron_left_deck');

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
							obj.summary_window.g.summary.retrieve();
						}
					],
					'cmd_patron_checkout' : [
						['command'],
						function(ev) {
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
					],
					'cmd_patron_items' : [
						['command'],
						function(ev) {
							obj.right_deck.set_iframe(urls.remote_patron_items);
							dump('obj.right_deck.node.childNodes.length = ' + obj.right_deck.node.childNodes.length + '\n');
						}
					],
					'cmd_patron_holds' : [
						['command'],
						function(ev) {
							obj.right_deck.set_iframe(urls.remote_patron_holds);
							dump('obj.right_deck.node.childNodes.length = ' + obj.right_deck.node.childNodes.length + '\n');
						}
					],
					'cmd_patron_bills' : [
						['command'],
						function(ev) {
							obj.right_deck.set_iframe(urls.remote_patron_bills);
							dump('obj.right_deck.node.childNodes.length = ' + obj.right_deck.node.childNodes.length + '\n');
						}
					],
					'cmd_patron_edit' : [
						['command'],
						function(ev) {
							obj.right_deck.set_iframe(urls.remote_patron_edit);
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
				}
			}
		);

		if (obj.barcode) {
			var frame = obj.left_deck.set_iframe(
				urls.remote_patron_summary
				+'?session=' + window.escape(obj.session)
				+'&barcode=' + window.escape(obj.barcode), 
				{},
				{
					'on_finished' : function(patron) {
						obj.patron = patron; obj.controller.render();
					}
				}
			);
			obj.summary_window = frame.contentWindow;
		} else {
			var frame = obj.left_deck.set_iframe(
				urls.remote_patron_search_form
				+'?session=' + window.escape(obj.session),
				{},
				{
				}
			);
			obj.search_window = frame.contentWindow;	
		}
	},
}

dump('exiting patron/display.js\n');
