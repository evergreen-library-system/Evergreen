var FM_TABLE_DISPLAY = {
	acp : {
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
	acpn : {
		name : 'title',
		fields : [
			'pub',
			'title',
			'value'
		]
	},
	asc : {
		name : 'name',
		fields : [
			'owner',
			'opac_visible',
			'name'
		]
	},
	ascecm : {
		fields : [ 'stat_cat', 'stat_cat_entry' ]
	},
	ccs : {
		name : 'name'
	},
	acpl : {
		name : 'name',
		fields : [
			'circulate',
			'holdable',
			'owning_lib',
			'opac_visible'
		]
	},
	au : {
		name : 'usrname',
		fields : [
			'card',
			'email',
			'prefix',
			'first_given_name',
			'second_given_name',
			'family_name',
			'suffix',
			'day_phone',
			'home_ou',
			'dob'
		]
	},
	aws : {
		name : 'name'
	},
	mwps : {
		fields : [
			'workstation',
			'cash_payment',
			'check_payment',	
			'credit_card_payment'
		]
	},

	mups : {
		fields : [
			'usr',
			'credit_payment',
			'forgive_payment',
			'work_payment'
		]
	}
}
