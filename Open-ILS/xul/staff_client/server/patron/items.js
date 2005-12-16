dump('entering patron.items.js\n');

if (typeof patron == 'undefined') patron = {};
patron.items = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	this.OpenILS = {}; JSAN.use('OpenILS.data'); this.OpenILS.data = new OpenILS.data(); this.OpenILS.data.init({'via':'stash'});
}

patron.items.prototype = {

	'init' : function( params ) {

		var obj = this;

		obj.session = params['session'];
		obj.patron_id = params['patron_id'];

		JSAN.use('circ.util');
		var columns = circ.util.columns( 
			{ 
				'title' : { 'hidden' : false, 'flex' : '3' },
				'xact_start' : { 'hidden' : false },
				'due_date' : { 'hidden' : false },
				'renewal_remaining' : { 'hidden' : false },
			} 
		);

		JSAN.use('util.list'); obj.list = new util.list('item_list');
		obj.list.init(
			{
				'columns' : columns,
				'map_row_to_column' : circ.util.std_map_row_to_column(),
			}
		);
		
		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				'control_map' : {
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_item_print' : [
						['command'],
						function() {
						}
					],
					'cmd_item_reprint' : [
						['command'],
						function() {
						}
					],
				}
			}
		);

	},

	'retrieve' : function() {
		if (window.xulG && window.xulG.checkouts) {
			this.checkouts = window.xulG.checkouts;
		} else {
			this.checkouts = this.network.request(
				api.blob_checkouts_retrieve.app,
				api.blob_checkouts_retrieve.method,
				[ this.session, this.patron_id ]
			);
				
		}
		for (var i in this.checkouts) {
			this.list.append(
				{
					'row' : {
						'my' : {
							'circ' : this.checkouts[i].circ,
							'mvr' : this.checkouts[i].record,
							'acp' : this.checkouts[i].copy
						}
					}
				}
			);
		}
	},
}

dump('exiting patron.items.js\n');
