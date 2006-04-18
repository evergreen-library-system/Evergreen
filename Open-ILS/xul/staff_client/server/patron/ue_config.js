/* -----------------------------------------------------------------------
	----------------------------------------------------------------------- */

var SC_FETCH_ALL		= 'open-ils.circ:open-ils.circ.stat_cat.actor.retrieve.all';
var SC_CREATE_MAP		= 'open-ils.circ:open-ils.circ.stat_cat.actor.user_map.create';
var SV_FETCH_ALL		= 'open-ils.circ:open-ils.circ.survey.retrieve.all';
var FETCH_ID_TYPES	= 'open-ils.actor:open-ils.actor.user.ident_types.retrieve';
var FETCH_GROUPS		= 'open-ils.actor:open-ils.actor.groups.tree.retrieve';
var UPDATE_PATRON		= 'open-ils.actor:open-ils.actor.patron.update';
var defaultState		= 'GA';
var defaultCountry	= 'USA';
var CSS_INVALID_DATA = 'invalid_value';

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
						removeCSSClass(field.widget.node, CSS_INVALID_DATA);
					else
						addCSSClass(field.widget.node, CSS_INVALID_DATA);
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

/* Adds all of the addresses attached to the patron object
	to the fields array */
var uEditAddrTemplate;
function uEditBuildAddrs(patron) {
	var tbody = $('ue_address_tbody');
	uEditAddrTemplate = 
		tbody.removeChild($('ue_address_template'));
	for( var a in patron.addresses() ) 
		uEditBuildAddrFields( patron, patron.addresses()[a]);
}


/* Creates a new blank address, adds it to the user
	and the fields array */
var uEditVirtualAddrId = -1;
function uEditCreateNewAddr() {
	var addr = new aua();

	addr.id(uEditVirtualAddrId--);
	addr.isnew(1);
	addr.usr(patron.id());
	addr.state(defaultState);
	addr.country(defaultCountry);

	if(patron.addresses().length == 0) {
		patron.mailing_address(addr);
		patron.billing_address(addr);
	}

	uEditBuildAddrFields(patron, addr);
	patron.addresses().push(addr);
}




function uEditDeleteAddr( tbody, row, address ) {
	if(!confirm($('ue_delete_addr_warn').innerHTML)) return;
	if(address.isnew()) { 
		patron.addresses(
			grep( patron.addresses(), 
				function(i) {
					return (i.id() != address.id());
				}
			)
		);
	} else {
		address.isdeleted(1);
	}
	tbody.removeChild(row);

	var bid = patron.billing_address();
	bid = (typeof bid == 'object') ? bid.id() : bid;

	var mid = patron.mailing_address();
	mid = (typeof mid == 'object') ? mid.id() : mid;


	/* -----------------------------------------------------------------------
		if we're deleting a billing or mailing address 
		make sure some other address is automatically
		assigned as the billing or mailng address 
		----------------------------------------------------------------------- */

	if( bid == address.id() ) {
		for( var a in patron.addresses() ) {
			var addr = patron.addresses()[a];
			if(!addr.isdeleted()) {
				var node = uEditFindAddrInput('billing', addr.id());
				node.checked = true;
				uEditAddrTypeClick(node, 'billing');
				break;
			}
		}
	}

	if( mid == address.id() ) {
		for( var a in patron.addresses() ) {
			var addr = patron.addresses()[a];
			if(!addr.isdeleted()) {
				var node = uEditFindAddrInput('mailing', addr.id());
				node.checked = true;
				uEditAddrTypeClick(node, 'mailing');
				break;
			}
		}
	}
}


function uEditFindAddrInput(type, id) {
	var tbody = $('ue_address_tbody');
	var rows = tbody.getElementsByTagName('tr');
	for( var r in rows ) {
		var row = rows[r];
		if(row.parentNode != tbody) continue;
		var node = $n(row, 'ue_addr_'+type+'_yes');
		if( node.getAttribute('address') == id )
			return node;
	}
}


function uEditAddrTypeClick(input, type) {
	var tbody = $('ue_address_tbody');
	var rows = tbody.getElementsByTagName('tr');
	for( var r in rows ) {
		var row = rows[r];
		if(row.parentNode != tbody) continue;
		var node = $n(row, 'ue_addr_'+type+'_yes');
		removeCSSClass(node.parentNode,'addr_info_checked');
	}

	addCSSClass(input.parentNode,'addr_info_checked');
	patron[type+'_address'](input.getAttribute('address'));
	patron.ischanged(1);
}




/* Creates the field entries for an address object. */
function uEditBuildAddrFields(patron, address) {

	var tbody = $('ue_address_tbody');
	var row	= tbody.appendChild(
		uEditAddrTemplate.cloneNode(true));

	$n(row, 'ue_addr_delete').onclick = 
		function() { uEditDeleteAddr(tbody, row, address); }

	if( address.id() == patron.billing_address().id() ) 
		$n(row, 'ue_addr_billing_yes').checked = true;

	if( address.id() == patron.mailing_address().id() ) 
		$n(row, 'ue_addr_mailing_yes').checked = true;

	$n(row, 'ue_addr_billing_yes').setAttribute('address', address.id());
	$n(row, 'ue_addr_mailing_yes').setAttribute('address', address.id());

	var fields = [
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
		},
		{ 
			required : false,
			object	: address, 
			key		: 'street2', 
			widget	: {
				base	: row,
				name	: 'ue_addr_street2',
				type	: 'input',
			}
		},
		{ 
			required : false,
			object	: address, 
			key		: 'street2', 
			widget	: {
				base	: row,
				name	: 'ue_addr_street2',
				type	: 'input',
			}
		},
		{ 
			required : true,
			object	: address, 
			key		: 'city', 
			widget	: {
				base	: row,
				name	: 'ue_addr_city',
				type	: 'input',
			}
		},
		{ 
			required : false,
			object	: address, 
			key		: 'county', 
			widget	: {
				base	: row,
				name	: 'ue_addr_county',
				type	: 'input',
			}
		},
		{ 
			required : true,
			object	: address, 
			key		: 'state', 
			widget	: {
				base	: row,
				name	: 'ue_addr_state',
				type	: 'input',
			}
		},
		{ 
			required : true,
			object	: address, 
			key		: 'country', 
			widget	: {
				base	: row,
				name	: 'ue_addr_country',
				type	: 'input',
			}
		},
		{ 
			required : true,
			object	: address, 
			key		: 'post_code',
			widget	: {
				base	: row,
				name	: 'ue_addr_zip',
				type	: 'input',
				regex	: /^\d{5}$/
			}
		},
		{ 
			required : false,
			object	: address, 
			key		: 'within_city_limits',
			widget	: {
				base	: row,
				name	: 'ue_addr_inc_yes',
				type	: 'checkbox',
			}
		},
		{ 
			required : false,
			object	: address, 
			key		: 'valid',
			widget	: {
				base	: row,
				name	: 'ue_addr_valid_yes',
				type	: 'checkbox',
			}
		}
	];

	for( var f in fields ) {
		dataFields.push(fields[f]);
		uEditActivateField(fields[f]);
	}
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

	$('ue_profile')
	*/

