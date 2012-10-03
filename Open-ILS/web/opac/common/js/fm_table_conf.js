var FM_TABLE_DISPLAY = {
	'acp' : {
		name : 'barcode',	
		fields : [
			'barcode',
			'call_number',
			'circ_modifier',
			'create_date',
			'edit_date',
			'fine_level',
			'holdable',
			'loan_duration',
			'location',
			'notes',
			'stat_cat_entry_copy_maps',
			'status' ],
		},
	'acpn' : {
		name : 'title',
		fields : [
			'pub',
			'title',
			'value'
		]
	},
	'asc' : {
		name : 'name',
		fields : [
			'owner',
			'opac_visible',
			'name'
		]
	},
	'ascecm' : {
		fields : [ 'stat_cat', 'stat_cat_entry' ]
	},
	'ccs' : {
		name : 'name'
	},
	'acpl' : {
		name : 'name',
		fields : [
			'circulate',
			'holdable',
			'owning_lib',
			'opac_visible'
		]
	},
	'au' : {
		name : 'usrname',
		fields : [
			'card',
			'email',
			'first_given_name',
			'family_name',
			'home_ou',
		]
	},
	'aws' : {
		name : 'name'
	},
	'mwps' : {
		fields : [
			'workstation',
			'cash_payment',
			'check_payment',	
			'credit_card_payment'
		],
		money : [
			'cash_payment',
			'check_payment',	
			'credit_card_payment'
		]
	},

	'mups' : {
		fields : [
			'usr',
			'credit_payment',
			'forgive_payment',
			'work_payment',
			'goods_payment'
		],
		money : [
			'credit_payment',
			'forgive_payment',
			'work_payment',
			'goods_payment'
		]
	},
	'rr' : {
		name : 'name',
		fields : [
			'name',
			'description',
			'template',
			'create_time',
			'recur',
			'recurrence',
			'owner',
		],
		sortdata : [ 'name', 1 ]
	},
	'rt' : {
		name : 'name',
		fields : [
			'name',
			'description',
			'create_time',
			'owner',
		],
		sortdata : [ 'name', 1 ]
	},
	'rs' : {
		fields : [
			'report',
			'run_time',
			'complete_time',
			'runner',
			'email',
			'folder',
			'error_text',
			'excel_format',
			'html_format',
			'csv_format',
		],
		bold : [
			'error_text',
		],
		sortdata : [ 'run_time', -1 ]
	}
}
