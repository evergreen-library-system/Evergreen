dump('entering admin/offline_manage_xacts.js\n');

if (typeof admin == 'undefined') admin = {};
admin.offline_manage_xacts = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
}

admin.offline_manage_xacts.prototype = {

	'init' : function( params ) {

		var obj = this;

		JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});

		JSAN.use('util.list'); obj.list = new util.list('session_tree');
		obj.list.init( {
			'columns' : [
				{ 'id' : 'desc', 'label' : 'Description', 'render' : "my.desc", 'flex' : '2' },
				{ 'id' : 'count', 'label' : 'Upload Count', 'render' : "my.meta.length", 'flex' : '1' },
				{ 'id' : 'complete', 'label' : 'Processed?', 'render' : "my.complete == 0 ? 'No' : 'Yes'", 'flex' : '1' },
				{ 'id' : 'seskey', 'label' : 'Session', 'render' : "my.session", 'hidden' : 'true', 'flex' : '1' },
			],
			'map_row_to_column' : function(row,col) {
				var my = row; var value;
				try { value = eval( col.render ); } catch(E) { obj.error.sdump('D_ERROR',E); value = '???'; }
				return value;
			},
		} );

		obj.retrieve_seslist();
		obj.render_seslist();

		document.getElementById('create').addEventListener('command',function() { obj.create_ses(); },false);

	},

	'create_ses' : function() {

		var obj = this;

		var desc = window.prompt('Please enter a description:','','Create an Offline Transaction Session');
		if (desc=='') { return; }

		obj.data.stash_retrieve();

		var url  = xulG.url_prefix(urls.XUL_OFFLINE_MANAGE_XACTS_CGI)
			+ "?ses=" + window.escape(obj.data.session)
			+ "&createses=1" 
			+ "&org=" + window.escape(obj.data.list.au[0].ws_ou())
			+ "&desc=" + window.escape(desc)
			+ "&raw=1";
		var x = new XMLHttpRequest();
		x.open("GET",url,false);
		x.send(null);

		var robj = JSON2js(x.responseText);
		if (robj.ilsevent == 0) {
			obj.retrieve_seslist(); obj.render_seslist();
		} else {
			alert('Error: ' + x.responseText);
		}

	},

	'retrieve_seslist' : function() {

		var obj = this;

		obj.data.stash_retrieve();

		var url = xulG.url_prefix(urls.XUL_OFFLINE_MANAGE_XACTS_CGI) 
			+ "?ses=" + window.escape(obj.data.session)
			+ "&seslist=1"
			+ "&org=" + window.escape(obj.data.list.au[0].ws_ou())
			+ "&raw=1";
		var x = new XMLHttpRequest();
		x.open("GET",url,false);
		x.send(null);

		obj.seslist = JSON2js( x.responseText );
		dump(url + ' = ' + x.responseText + '\n' );
	},

	'render_seslist' : function() {

		var obj = this;

		obj.list.clear();

		var funcs = [];
		for (var i = 0; i < obj.seslist.length; i++) {
			funcs.push( 
				function(row){ 
					return function(){
						obj.list.append( { 'retrieve_id' : row.session, 'row' : row } );
					};
				}(obj.seslist[i]) 
			);
		}
		JSAN.use('util.exec'); var exec = new util.exec();
		exec.chain( funcs );
	},
}

dump('exiting admin/offline_manage_xacts.js\n');
