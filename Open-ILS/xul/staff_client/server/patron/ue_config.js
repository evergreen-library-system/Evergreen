/* -----------------------------------------------------------------------
	----------------------------------------------------------------------- */

var SC_FETCH_ALL		= 'open-ils.circ:open-ils.circ.stat_cat.actor.retrieve.all';
var SC_CREATE_MAP		= 'open-ils.circ:open-ils.circ.stat_cat.actor.user_map.create';
var SV_FETCH_ALL		= 'open-ils.circ:open-ils.circ.survey.retrieve.all';
var FETCH_ID_TYPES	= 'open-ils.actor:open-ils.actor.user.ident_types.retrieve';
var FETCH_GROUPS		= 'open-ils.actor:open-ils.actor.groups.tree.retrieve';
var UPDATE_PATRON		= 'open-ils.actor:open-ils.actor.patron.update';
var defaultState		= 'GA';

/* if they don't have these perms, they shouldn't be here */
var myPerms = [ 'CREATE_USER', 'UPDATE_USER', 'CREATE_PATRON_STAT_CAT_ENTRY_MAP' ];

var dataFields;
var numRegex	= /^\d+$/;
var wordRegex	= /^\w+$/;
var ssnRegex	= /^\d{3}-\d{2}-\d{4}$/;
var dlRegex		= /^[a-zA-Z]{2}-\w+/; /* driver's license */
var phoneRegex	= /\d{3}-\d{3}-\d{4}/;
var nonumRegex	= /^\D+$/;


function uEditDefineData(patron, identTypes, groups, statCats, surveys ) {
	
	dataFields = [
		{
			required : true,
			object	: patron.card(),
			key		: 'barcode',
			widget	: {
				id		: 'ue_barcode',
				regex	: wordRegex,
				type	: 'input'
			}
		},
		{
			required : true,
			object	: patron,
			key		: 'usrname',
			widget	: {
				id		: 'ue_username',
				regex	: nonumRegex,
				type	: 'input'
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'passwd',
			widget	: {
				id		: 'ue_password1',
				type	: 'input',
				onpostchange : function(field, newval) {
					var pw2 = uEditFindFieldByWId('ue_password2');
					/* tell the second passsword input to re-validate */
					pw2.widget.node.onchange();
				}

			}
		},
		{
			required : false,
			object	: patron,
			key		: 'passwd',
			widget	: {
				id		: 'ue_password2',
				type	: 'input',
				onpostchange : function(field, newval) {
					var pw1f = uEditFindFieldByWId('ue_password1');
					var pw1 = uEditNodeVal(pw1f);
					if( pw1 == newval ) 
						removeCSSClass(field.widget.node, 'invalid_value');
					else
						addCSSClass(field.widget.node, 'invalid_value');
				}
			}
		},
		{
			required : true,
			object	: patron,
			key		: 'first_given_name',
			widget	: {
				id		: 'ue_firstname',
				regex	: nonumRegex,
				type	: 'input'
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'second_given_name',
			widget	: {
				id		: 'ue_middlename',
				regex	: nonumRegex,
				type	: 'input'
			}
		},
		{
			required : true,
			object	: patron,
			key		: 'family_name',
			widget	: {
				id		: 'ue_lastname',
				regex	: nonumRegex,
				type	: 'input'
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'suffix',
			widget	: {
				id			: 'ue_suffix',
				type		: 'input',
				onload	: function(val) {
					setSelector($('ue_suffix_selector'), val);
				}
			}
		},
		{
			required : true,
			object	: patron,
			key		: 'dob',
			widget	: {
				id			: 'ue_dob',
				regex		: /^\d{4}-\d{2}-\d{2}/,
				type		: 'input',
			}
		},
		{
			required : true,
			object	: patron,
			key		: 'ident_type',
			widget	: {
				id		: 'ue_primary_ident_type',
				regex	: numRegex,
				type	: 'select',
				onpostchange : function(field, newval) 
					{ _uEditIdentPostchange('primary', field, newval); }
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'ident_value',
			widget	: {
				id			: 'ue_primary_ident',
				type		: 'input',
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'ident_type2',
			widget	: {
				id		: 'ue_secondary_ident_type',
				regex	: numRegex,
				type	: 'select',
				onpostchange : function(field, newval) 
					{ _uEditIdentPostchange('secondary', field, newval); }
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'ident_value2',
			widget	: {
				id			: 'ue_secondary_ident',
				type		: 'input',
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'email',
			widget	: {
				id			: 'ue_email',
				type		: 'input',
				regex		:  /.+\@.+\..+/ /* make me better */
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'day_phone',
			widget	: {
				id			: 'ue_day_phone',
				type		: 'input',
				regex		:  phoneRegex,
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'evening_phone',
			widget	: {
				id			: 'ue_night_phone',
				type		: 'input',
				regex		:  phoneRegex,
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'other_phone',
			widget	: {
				id			: 'ue_other_phone',
				type		: 'input',
				regex		:  phoneRegex,
			}
		},
		{
			required : true,
			object	: patron,
			key		: 'home_ou',
			widget	: {
				id			: 'ue_org_selector',
				type		: 'select',
				regex		:  numRegex,
			}
		},
	];

	uEditBuildAddrs(patron);
}

function uEditBuildAddrs(patron) {
	var tbody = $('ue_address_tbody');
	var row = tbody.removeChild($('ue_address_template'));

	for( var a in patron.addresses() ) {
		var newrow = tbody.appendChild(row.cloneNode(true));
		var fields = uEditBuildAddrFields( 
			patron, patron.addresses()[a], newrow ); 

		for( var f in fields ) dataFields.push(fields[f]);
	}
}

function uEditBuildAddrFields(patron, address, row) {

	return [
		{ 
			required : false,
			object	: address, 
			key		: 'address_type', 
			widget	: {
				base	: row,
				name	: 'ue_addr_label',
				type	: 'input',
			}
		},
		{ 
			required : true,
			object	: address, 
			key		: 'street1', 
			widget	: {
				base	: row,
				name	: 'ue_addr_street1',
				type	: 'input',
			}
		}
	];
}




/** Run this after a new ident type is selected */
function _uEditIdentPostchange(type, field, newval) {

	if(!newval) return;

	/* When the ident type is changed, we change the
	regex on the ident_value to match the selected type */
	var vfname = 'ident_value';
	if(type == 'secondary') vfname = 'ident_value2';
	var vfield = uEditFindFieldByKey(vfname);
	var name = identTypesCache[uEditNodeVal(field)].name();

	hideMe($(type+'_ident_ssn_help'));
	hideMe($(type+'_ident_dl_help'));

	if(name.match(/ssn/i)) {
		vfield.widget.regex = ssnRegex;
		unHideMe($(type+'_ident_ssn_help'));

	} else {

		if(name.match(/driver/i)) {
			vfield.widget.regex = dlRegex;
			unHideMe($(type+'_ident_dl_help'));

		} else {
			vfield.widget.regex = null;
		}
	}

	/* focus then valdate the value field */
	vfield.widget.node.onchange();
	vfield.widget.node.focus();
}




	/*
	$('ue_expire')
	$('ue_active')
	$('ue_barred')
	$('ue_claims_returned')
	$('ue_alert_message')

	$('ue_primary_ident_type')
	$('ue_secondary_ident_type')
	$('ue_org_selector')
	$('ue_profile')
	
	$('ue_day_phone_area')
	$('ue_day_phone_prefix')
	$('ue_day_phone_suffix')
	$('ue_night_phone_area')
	$('ue_night_phone_prefix')
	$('ue_night_phone_suffix')
	$('ue_other_phone_area')
	$('ue_other_phone_prefix')
	$('ue_other_phone_suffix')


	$n(row, 'ue_addr_label').value	= addr.address_type();
	$n(row, 'ue_addr_street1').value	= addr.street1();
	$n(row, 'ue_addr_street2').value = addr.street2();
	$n(row, 'ue_addr_city').value		= addr.city();
	$n(row, 'ue_addr_county').value	= addr.county();
	$n(row, 'ue_addr_state').value	= addr.state();
	$n(row, 'ue_addr_zip').value		= addr.post_code();
	$n(row, 'ue_addr_country').value	= addr.country();
	*/

