dump('entering circ/util.js\n');

if (typeof circ == 'undefined') var circ = {};
circ.util = {};

circ.util.EXPORT_OK	= [ 
	'columns'
];
circ.util.EXPORT_TAGS	= { ':all' : circ.util.EXPORT_OK };

circ.util.columns = function(modify) {
	
	function getString(s) { return obj.OpenILS.data.entities[s]; }

	var c = [
		{
			'id' : 'acp_id', 'label' : getString('staff.acp_label_id'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.id()'
		},
		{
			'id' : 'circ_id', 'label' : getString('staff.circ_label_id'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.circ.id()'
		},
		{
			'id' : 'mvr_doc_id', 'label' : getString('staff.mvr_label_doc_id'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.mvr.doc_id()'
		},
		{
			'id' : 'barcode', 'label' : getString('staff.acp_label_barcode'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.barcode()'
		},
		{
			'id' : 'call_number', 'label' : getString('staff.acp_label_call_number'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.call_number()'
		},
		{
			'id' : 'copy_number', 'label' : getString('staff.acp_label_copy_number'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.copy_number()'
		},
		{
			'id' : 'location', 'label' : getString('staff.acp_label_location'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.location()'
		},
		{
			'id' : 'loan_duration', 'label' : getString('staff.acp_label_loan_duration'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.loan_duration()'
		},
		{
			'id' : 'circ_lib', 'label' : getString('staff.acp_label_circ_lib'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.circ_lib()'
		},
		{
			'id' : 'fine_level', 'label' : getString('staff.acp_label_fine_level'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.fine_level()'
		},
		{
			'id' : 'deposit', 'label' : getString('staff.acp_label_deposit'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.deposit()'
		},
		{
			'id' : 'deposit_amount', 'label' : getString('staff.acp_label_deposit_amount'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.deposit_amount()'
		},
		{
			'id' : 'price', 'label' : getString('staff.acp_label_price'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.price()'
		},
		{
			'id' : 'circ_as_type', 'label' : getString('staff.acp_label_circ_as_type'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.circ_as_type()'
		},
		{
			'id' : 'circ_modifier', 'label' : getString('staff.acp_label_circ_modifier'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.acp.circ_modifier()'
		},
		{
			'id' : 'xact_start', 'label' : getString('staff.circ_label_xact_start'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.circ.xact_start()'
		},
		{
			'id' : 'xact_finish', 'label' : getString('staff.circ_label_xact_finish'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.circ.xact_finish()'
		},
		{
			'id' : 'due_date', 'label' : getString('staff.circ_label_due_date'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.circ.due_date().substr(0,10)'
		},
		{
			'id' : 'title', 'label' : getString('staff.mvr_label_title'), 'flex' : 2,
			'primary' : false, 'hidden' : true, 'render' : 'my.mvr.title()'
		},
		{
			'id' : 'author', 'label' : getString('staff.mvr_label_author'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'my.mvr.author()'
		},
		{
			'id' : 'renewal_remaining', 'label' : getString('staff.circ_label_renewal_remaining'), 'flex' : 0,
			'primary' : false, 'hidden' : true, 'render' : 'my.circ.renewal_remaining()'
		},
		{
			'id' : 'status', 'label' : getString('staff.acp_label_status'), 'flex' : 1,
			'primary' : false, 'hidden' : true, 'render' : 'obj.OpenILS.data.hash.ccs[ my.acp.status() ].name()'
		},
	];
	for (var i = 0; i < c.length; c++) {
		if (modify[ c[i].id ]) {
			for (var j in modify) {
				c[i][j] = modify[j];
			}
		}
	}
	return c;
}

dump('exiting circ/util.js\n');
