dump('entering cat/util.js\n');

if (typeof cat == 'undefined') var cat = {};
cat.util = {};

cat.util.EXPORT_OK	= [ 
	'spawn_copy_editor',
];
cat.util.EXPORT_TAGS	= { ':all' : cat.util.EXPORT_OK };

cat.util.spawn_copy_editor = function(list) {
	var obj = {};
	JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
	JSAN.use('util.network'); obj.network = new util.network();
	JSAN.use('util.error'); obj.error = new util.error();

	var copies = util.functional.map_list(
		list,
		function (acp_id) {
			return obj.network.simple_request('FM_ACP_RETRIEVE',[acp_id]);
		}
	);

	var edit = 0;
	try {
		edit = obj.network.request(
			api.PERM_MULTI_ORG_CHECK.app,
			api.PERM_MULTI_ORG_CHECK.method,
			[ 
				ses(), 
				obj.data.list.au[0].id(), 
				util.functional.map_list(
					copies,
					function (o) {
						return obj.network.simple_request('FM_ACN_RETRIEVE',[o.call_number()]).owning_lib();
					}
				),
				[ 'UPDATE_COPY', 'UPDATE_BATCH_COPY' ]
			]
		).length == 0 ? 1 : 0;
	} catch(E) {
		obj.error.sdump('D_ERROR','batch permission check: ' + E);
	}

	var title = list.length == 1 ? 'Copy' : 'Copies';

	JSAN.use('util.window'); var win = new util.window();
	obj.data.temp = '';
	obj.data.stash('temp');
	var w = win.open(
		window.xulG.url_prefix(urls.XUL_COPY_EDITOR)
			+'?copy_ids='+window.escape(js2JSON(list))
			+'&edit='+edit,
		title,
		'chrome,modal,resizable'
	);
	/* FIXME -- need to unique the temp space, and not rely on modalness of window */
	obj.data.stash_retrieve();
	copies = JSON2js( obj.data.temp );
	obj.error.sdump('D_CAT','in cat/copy_status, copy editor, copies =\n<<' + copies + '>>');
	if (edit=='1' && copies!='' && typeof copies != 'undefined') {
		try {
			var r = obj.network.request(
				api.FM_ACP_FLESHED_BATCH_UPDATE.app,
				api.FM_ACP_FLESHED_BATCH_UPDATE.method,
				[ ses(), copies ]
			);
			/* FIXME -- revisit the return value here */
		} catch(E) {
			obj.error.standard_unexpected_error_alert('copy update error',E);
		}
	}
}

dump('exiting cat/util.js\n');
