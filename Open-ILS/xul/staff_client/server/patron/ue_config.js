/* -----------------------------------------------------------------------
	----------------------------------------------------------------------- */
const SC_FETCH_ALL		= 'open-ils.circ:open-ils.circ.stat_cat.actor.retrieve.all';
const SC_CREATE_MAP		= 'open-ils.circ:open-ils.circ.stat_cat.actor.user_map.create';
const SV_FETCH_ALL		= 'open-ils.circ:open-ils.circ.survey.retrieve.all';
const FETCH_ID_TYPES		= 'open-ils.actor:open-ils.actor.user.ident_types.retrieve';
const FETCH_GROUPS		= 'open-ils.actor:open-ils.actor.groups.tree.retrieve';
const FETCH_NET_LEVELS	= 'open-ils.actor:open-ils.actor.net_access_level.retrieve.all';
const UPDATE_PATRON		= 'open-ils.actor:open-ils.actor.patron.update';
const PATRON_SEARCH		= 'open-ils.actor:open-ils.actor.patron.search.advanced';
const ZIP_SEARCH			= 'open-ils.search:open-ils.search.zip';
const APPROVE_ADDR		= 'open-ils.actor:open-ils.actor.user.pending_address.approve';
const FETCH_ADDR_MEMS	= 'open-ils.actor:open-ils.actor.address.members';
const FETCH_GRP_MEMS		= 'open-ils.actor:open-ils.actor.usergroup.members.retrieve';
const CREATE_USER_NOTE	= 'open-ils.actor:open-ils.actor.note.create';
const CHECK_BARCODE		= 'open-ils.actor:open-ils.actor.barcode.exists';
const defaultState		= 'GA';
const defaultCountry		= 'USA';
const defaultNetAccess	= 'None';
const defaultNetLevel   = 1;
const CSS_INVALID_DATA	= 'invalid_value';

// if no org setting exists
const DEFAULT_ADULT_AGE			= '18 years';

//const GUARDIAN_NOTE		= 'SYSTEM: Parent/Guardian';

var dataFields;
const numRegex		= /^\d+$/;
const wordRegex	= /^[\w-]+$/;
const unameRegex	= /^\w[\.\w\@-]*$/;
const ssnRegex		= /^\d{3}-\d{2}-\d{4}$/;
const dlRegex		= /^[a-zA-Z]{2}-\w+/; /* driver's license */
const phoneRegex	= /^\d{3}-\d{3}-\d{4}(| \S+.*)$/i;
const nonumRegex	= /^[^\d\s]+[\d]*$/; /* no numbers, no beginning whitespace */
const dateRegex	= /^\d{4}-\d{2}-\d{2}/;
const zipRegex		= /^\d{5}(-\d{4}|-?$)/; /* 12345 or 12345-6789 */

var barredAlerted = false;


function uEditUsrnameBlur(field) {
	var usrname = uEditNodeVal(field);
	if (!usrname) { return; }
	var req = new Request(CHECK_USERNAME, SESSION, usrname);
	req.callback( 
		function(r) {
			var res = r.getResultObject();
			if( res !== null && res != patron.id() ) {
				field.widget.onblur = null; /* prevent alert storm */
				alertId('ue_dup_username');
				field.widget.onblur = uEditUsrnameBlur;
				setTimeout( 
					function() {
						field.widget.node.focus();
						field.widget.node.select();
					}, 10 
				);
			}
		}
	);
	req.send();
}


function uEditBarcodeBlur(field) {
	var barcode = uEditNodeVal(field);
	if(!barcode) return;
	_debug("blurring card with new value " + barcode);
	var req = new Request(CHECK_BARCODE, SESSION, barcode);
	req.callback( 
		function(r) {
			var res = r.getResultObject();
			if( res == 1 ) {
				field.widget.onblur = null; /* prevent alert storm */
				alertId('ue_dup_barcode');
				field.widget.onblur = uEditBarcodeBlur;
				setTimeout( 
					function() {
						field.widget.node.focus();
						field.widget.node.select();
					}, 10 
				);
			} else {
				var node = uEditFindFieldByWId("ue_username");
				if(!node.widget.node.value) {
					node.widget.node.value = barcode;
					node.widget.node.onchange();
				}
			}
		}
	);
	req.send();
}


function uEditDefineData(patron) {

	var fields = [
		{
			required : true,
			object	: patron.card(),
			key		: 'barcode',
			errkey	: 'ue_bad_barcode',
			widget	: {
				id		: 'ue_barcode',
				regex	: wordRegex,
				type	: 'input',
				onblur : uEditBarcodeBlur
			}
		},
		{
			required : true,
			object	: patron,
			key		: 'usrname',
			errkey	: 'ue_bad_username',
			widget	: {
				id		: 'ue_username',
				regex	: unameRegex,
				type	: 'input',
				onblur : uEditUsrnameBlur
			}
		},
		{
			required : (patron.isnew()) ? true : false,
			object	: patron,
			key		: 'passwd',
			errkey	: 'ue_bad_password',
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
			required : (patron.isnew()) ? true : false,
			object	: patron,
			key		: 'passwd',
			errkey	: 'ue_bad_password',
			widget	: {
				id		: 'ue_password2',
				type	: 'input',
				onpostchange : function(field, newval) {
					var pw1f = uEditFindFieldByWId('ue_password1');
					var pw1 = uEditNodeVal(pw1f);
					field.widget.regex = new RegExp('^'+pw1+'$');
					if( pw1 ) field.required = true;
					else {
						if(!patron.isnew())
							field.required = false;
					}
				}
			}
		},
		{
			required : true,
			object	: patron,
			key		: 'first_given_name',
			errkey	: 'ue_bad_firstname',
			widget	: {
				id		: 'ue_firstname',
				regex	: nonumRegex,
				type	: 'input',
				onblur : function(field) {
					uEditCheckNamesDup('first', field );
				}
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'second_given_name',
			errkey	: 'ue_bad_middlename',
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
			errkey	: 'ue_bad_lastname',
			widget	: {
				id		: 'ue_lastname',
				regex	: nonumRegex,
				type	: 'input',
				onblur : function(field) {
					uEditCheckNamesDup('last', field );
				}
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
					$('ue_suffix_selector').onchange = function() {
						uEditFindFieldByKey('suffix').widget.node.onchange();
					}
				},
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'alias',
			widget	: {
				id		: 'ue_alias',
				type	: 'input',
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'dob',
			errkey	: 'ue_bad_dob',
			widget	: {
				id			: 'ue_dob',
				regex		: dateRegex,
				type		: 'input',
				onpostchange	: function(field) { uEditCheckDOB(field); },
				onblur	: function(field) { uEditCheckDOB(field); }
			}
		},
		{
			required : true,
			object	: patron,
			key		: 'ident_type',
			errkey	: 'ue_no_ident',
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
				onblur : function(field) {
					uEditCheckIdentDup(field);
				}
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'ident_value2',
			widget	: {
				id			: 'ue_secondary_ident',
				type		: 'input'
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'email',
			errkey	: 'ue_bad_email',
			widget	: {
				id			: 'ue_email',
				type		: 'input',
				regex		:  /.+\@.+\..+/,  /* make me better */
				onblur	: function(field) {
					var val = uEditNodeVal(field);
					if( val && val != field.oldemail ) {
						uEditRunDupeSearch('email',
							{ email : { value : val, group : 0 } });
						field.oldemail = val;
					}
				}
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'day_phone',
			errkey	: 'ue_bad_phone',
			widget	: {
				id			: 'ue_day_phone',
				type		: 'input',
				regex		:  phoneRegex,
                onblur      : function() {
                    if(uEditUsePhonePw)
                        uEditMakePhonePw();
                },
                onpostchange: function(field, newval) {
                    /*  if this is a new patron and we are using the phone number for
                        the password and the staff edits the phone number after entering
                        it (think typos), update the password too */
                    if(uEditUsePhonePw && patron.isnew() && patron.passwd() != newval) {
                        patron.passwd(null);
                        uEditMakePhonePw();
                    }
                }
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'evening_phone',
			errkey	: 'ue_bad_phone',
			widget	: {
				id			: 'ue_night_phone',
				type		: 'input',
				regex		:  phoneRegex,
                onblur      : function() {
                    if(uEditUsePhonePw)
                        uEditMakePhonePw();
                }
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'other_phone',
			errkey	: 'ue_bad_phone',
			widget	: {
				id			: 'ue_other_phone',
				type		: 'input',
				regex		:  phoneRegex,
                onblur      : function() {
                    if(uEditUsePhonePw)
                        uEditMakePhonePw();
                }
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
		{
			required : true,
			object	: patron,
			key		: 'expire_date',
			errkey	: 'ue_bad_expire',
			widget	: {
				id			: 'ue_expire',
				type		: 'input',
				regex		:  dateRegex,
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'active',
			widget	: {
				id			: 'ue_active',
				type		: 'checkbox',
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'juvenile',
			widget	: {
				id			: 'ue_juvenile',
				type		: 'checkbox',
				onpostchange	: function(field) { uEditCheckDOB(uEditFindFieldByKey('dob')); },
				onblur	: function(field) { uEditCheckDOB(uEditFindFieldByKey('dob')); }
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'barred',
			widget	: {
				id			: 'ue_barred',
				type		: 'checkbox',
				onpostchange : function(field, val) {
					var afield = uEditFindFieldByKey('alert_message');
					if( val ) {
						if( !barredAlerted ) {
							barredAlerted = true;
							alertId('ue_made_barred');
						}
						afield.required = true;	
					} else {
						afield.required = false;
					}
				}
			}
		},
		{
			required : true,
			object	: patron,
			key		: 'profile',
			errkey	: 'ue_no_profile',
			widget	: {
				id			: 'ue_profile',
				type		: 'select',
				regex		: numRegex,
				onpostchange : function(field, value) {
					var type			= groupsCache[value];
					if(!type) return;
					var interval	= type.perm_interval();

					/* interval_to_seconds expects 'M' for months, 'm' for minutes */
					interval			= interval.replace(/mon/, 'Mon'); 
					var intsecs		= parseInt(interval_to_seconds(interval));

					var expdate		= new Date();
					var exptime		= expdate.getTime();
					exptime			+= intsecs * 1000;
					expdate.setTime(exptime);

					_debug("profile change (interval= '"+interval+"', seconds="+intsecs+")\n\tgenerated a date of " + expdate);

					var year			= expdate.getYear() + 1900;
					var month		= (expdate.getMonth() + 1) + '';
					var day			= (expdate.getDate()) + '';

					if(!month.match(/\d{2}/)) month = '0' + month;
					if(!day.match(/\d{2}/)) day = '0' + day;


					var node = $('ue_expire');
					node.value = year+'-'+month+'-'+day;

					_debug("profile change formatted date to "+ node.value);
					node.onchange();
				}
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'net_access_level',
			widget	: {
				id		: 'ue_net_level',
				type	: 'select'
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'master_account',
			widget	: {
				id			: 'ue_group_lead',
				type		: 'checkbox',
			}
		},
		{
			required : true,
			object	: patron,
			key		: 'claims_returned_count',
			widget	: {
				id			: 'ue_claims_returned',
				type		: 'input',
				regex		: numRegex,
				disabled : true
			}
		},
		{
			required : false,
			object	: patron,
			key		: 'alert_message',
			widget	: {
				id			: 'ue_alert_message',
				type		: 'input',
			}
		}
	];

	for( var f in fields ) 
		dataFields.push(fields[f]);

	uEditBuildAddrs(patron);
	uEditBuildPatronSCM(patron);
}

var uEditOldFirstName;
var uEditOldMiddleName; /* future */
var uEditOldLastName;
function uEditCheckNamesDup(type, field) {
	var newval = uEditNodeVal(field);
	if(!newval) return;

	var dosearch = false;

	if(type =='first') {
		if( newval != uEditOldFirstName )
			dosearch = true;
		uEditOldFirstName = newval;
	}

	if(type =='last') {
		if( newval != uEditOldLastName )
			dosearch = true;
		uEditOldLastName = newval;
	}

	if( dosearch && uEditOldFirstName && uEditOldLastName ) {
		var search_hash = {};
		search_hash['first_given_name'] = { value : uEditOldFirstName, group : 0 };
		search_hash['family_name'] = { value : uEditOldLastName, group : 0 };
		uEditRunDupeSearch('names', search_hash);
	}
}

var uEditOldIdentValue;
function uEditCheckIdentDup(field) {
	var newval = uEditNodeVal(field);
	if( newval && newval != uEditOldIdentValue ) {
		/* searches all ident_value fields */
		var search_hash  = { ident : { value : newval, group : 2 } };
		uEditRunDupeSearch('ident', search_hash);
		uEditOldIdentValue = newval;
	}
}


/* Adds all of the addresses attached to the patron object
	to the fields array */
var uEditAddrTemplate;
function uEditBuildAddrs(patron) {
	var tbody = $('ue_address_tbody');
	if(!uEditAddrTemplate)
		uEditAddrTemplate = tbody.removeChild($('ue_address_template'));
	for( var a in patron.addresses() ) 
		uEditBuildAddrFields( patron, patron.addresses()[a]);
}


function uEditDeleteAddr( tbody, row, address, detach ) {
	if(!confirm($('ue_delete_addr_warn').innerHTML)) return;
	if(address.isnew()) { 
		patron.addresses(
			grep( patron.addresses(), 
				function(i) {
					return (i.id() != address.id());
				}
			)
		);
        if(!patron.addresses())
            patron.addresses([]);

		/* XXX */
		for( var f in dataFields ) {
			if( dataFields[f].object == address ) {
				dataFields[f] = null;
			}
		}

		dataFields = compactArray(dataFields);

	} else {

		if( detach ) { /* remove the offending address from the list */
			patron.addresses(
				grep( 
					patron.addresses(), 
					function(i) {
						return (i.id() != address.id());
					}
				)
			);
            if(!patron.addresses()) {                                      
                patron.addresses([]);                                      
                patron.billing_address(null);                              
                patron.mailing_address(null);
                patron.ischanged(1);
            }


		} else {
			address.isdeleted(1);
		}
	}

	tbody.removeChild(row);

	var bid = patron.billing_address();
    bid = (bid != null && typeof bid == 'object') ? bid.id() : bid;

	var mid = patron.mailing_address();
    mid = (mid != null && typeof mid == 'object') ? mid.id() : mid;


	/* -----------------------------------------------------------------------
		if we're deleting a billing or mailing address 
		make sure some other address is automatically
		assigned as the billing or mailng address 
		----------------------------------------------------------------------- */

	if( bid == address.id() ) {
		for( var a in patron.addresses() ) {
			var addr = patron.addresses()[a];
			if(!addr.isdeleted() && addr.id() != address.id()) {
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
			if(!addr.isdeleted() && addr.id() != address.id()) {
				var node = uEditFindAddrInput('mailing', addr.id());
				node.checked = true;
				uEditAddrTypeClick(node, 'mailing');
				break;
			}
		}
	}

}

function uEditApproveAddr( tbody, row, address ) {
    if(!confirm($('ue_add_approve_confirm').innerHTML)) return;
    var req = new Request(APPROVE_ADDR, SESSION, address);
    req.callback(
        function(r) {
            var oldId = r.getResultObject();
            if(oldId != null) {
                // remove the replaced address 
		        patron.addresses(
			        grep( patron.addresses(), 
				        function(i) { return (i.id() != oldId); }
			        )
		        );
                // update the ID on the new address
                address.id(oldId);
                address.replaces(null);
                address.pending('f');
                removeChildren($('ue_address_tbody'));
	            uEditBuildAddrs(patron);
            }
        }
    );
    req.send();
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

	uEditCheckSharedAddr(patron, address, tbody, row);
    
    // see if this is a pending address
    if( isTrue(address.pending()) ) {
        var button = $n(row, 'ue_addr_approve');
        unHideMe(button);
        button.onclick = function() { uEditApproveAddr( tbody, row, address ); }
        var oldaddr = grep(patron.addresses(), function(a){return (a.id() == address.replaces());});
        if(oldaddr) {
            oldaddr = oldaddr[0];
            unHideMe($n(row, 'ue_addr_replaced_row')); 
            $n(row, 'ue_addr_replaced_div').innerHTML = 
                $("patronStrings").getFormattedString(
                    'web.staff.patron.ue.uedit_show_addr_replacement', [
                    oldaddr.address_type(),
                    oldaddr.street1(),
                    oldaddr.street2(),
                    oldaddr.city(),
                    oldaddr.state(),
                    oldaddr.post_code() 
                ]);
        }
    }

	$n(row, 'ue_addr_delete').onclick = 
		function() { 
			uEditDeleteAddr(tbody, row, address); 
			uEditCheckErrors();
		};

	if( patron.billing_address() &&
			address.id() == patron.billing_address().id() ) 
		$n(row, 'ue_addr_billing_yes').checked = true;

	if( patron.mailing_address() &&
			address.id() == patron.mailing_address().id() ) 
		$n(row, 'ue_addr_mailing_yes').checked = true;

	$n(row, 'ue_addr_billing_yes').setAttribute('address', address.id());
	$n(row, 'ue_addr_mailing_yes').setAttribute('address', address.id());

	/* currently, non-owners cannot edit an address */
	var disabled = (address.usr() != patron.id())

	var fields = [
		{ 
			required : false,
			object	: address, 
			key		: 'address_type', 
			widget	: {
				base	: row,
				name	: 'ue_addr_label',
				type	: 'input',
				disabled : disabled,
			}
		},
		{ 
			required : true,
			object	: address, 
			key		: 'street1', 
			errkey	: 'ue_bad_addr_street',
			widget	: {
				base	: row,
				name	: 'ue_addr_street1',
				type	: 'input',
				disabled : disabled,
			}
		},
		{ 
			required : false,
			object	: address, 
			key		: 'street2', 
			errkey	: 'ue_bad_addr_street',
			widget	: {
				base	: row,
				name	: 'ue_addr_street2',
				type	: 'input',
				disabled : disabled,
			}
		},
		{ 
			required : true,
			object	: address, 
			key		: 'city', 
			errkey	: 'ue_bad_addr_city',
			widget	: {
				base	: row,
				name	: 'ue_addr_city',
				type	: 'input',
				disabled : disabled,
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
				disabled : disabled,
			}
		},
		{ 
			required : true,
			object	: address, 
			key		: 'state', 
			errkey	: 'ue_bad_addr_state',
			widget	: {
				base	: row,
				name	: 'ue_addr_state',
				type	: 'input',
				disabled : disabled,
			}
		},
		{ 
			required : true,
			object	: address, 
			key		: 'country', 
			errkey	: 'ue_bad_addr_country',
			widget	: {
				base	: row,
				name	: 'ue_addr_country',
				type	: 'input',
				disabled : disabled,
			}
		},
		{ 
			required : true,
			object	: address, 
			key		: 'post_code',
			errkey	: 'ue_bad_addr_zip',
			widget	: {
				base	: row,
				name	: 'ue_addr_zip',
				type	: 'input',
				disabled : disabled,
				regex	: zipRegex,
				onblur : function(f) {
					var v = uEditNodeVal(f);
					var req = new Request(ZIP_SEARCH, v);
					req.callback( 
						function(r) {
							var info = r.getResultObject();
							if(!info) return;
							var state = $n(f.widget.base, 'ue_addr_state');
							var county = $n(f.widget.base, 'ue_addr_county');
							var city = $n(f.widget.base, 'ue_addr_city');
							state.value = info.state;
							state.onchange();
							county.value = info.county;
							county.onchange();
							city.value = info.city;
							city.onchange();
						}
					);
					req.send();
				}
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
				disabled : disabled,
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
				disabled : disabled,
			}
		}
	];

	for( var f in fields ) {
		dataFields.push(fields[f]);
		uEditActivateField(fields[f]);
	}
}

function uEditBuildPatronSCM(patron) {
	/* get the list of pre-defined maps */
	var fields = uEditFindFieldsByKey('stat_cat_entry');
	var map;
	var newmaps = [];

	/* for each user stat cat, pop it off the list,
	updated the existing stat map field to match
	the popped map and shove the existing stat
	map field onto the user's list of stat maps */
	while( (map = patron.stat_cat_entries().pop()) ) {

		var field = grep(fields, 
			function(item) {
				return (item.object.stat_cat() == map.stat_cat());
			}
		);

		if(field) {
			var val = map.stat_cat_entry();
			field = field[0];
			$n(field.widget.base, field.widget.name).value = val;
			setSelector($n(field.widget.base, 'ue_stat_cat_selector'), val );
			field.object.stat_cat_entry(val);
			field.object.id(map.id());
			newmaps.push(field.object);
		}
	}

	for( var m in newmaps ) 
		patron.stat_cat_entries().push(newmaps[m]);
}


function uEditBuildSCMField(statcat, row) {

	var map = new actscecm();
	map.stat_cat(statcat.id());
	map.target_usr(patron.id());

	var field = {
		required : false,
		object	: map,
		key		: 'stat_cat_entry',
		widget	: {
			base	: row,
			name	: 'ue_stat_cat_newval',
			type	: 'input',

			onpostchange : function( field, newval ) {

				/* see if the current map already resides in 
					the patron entry list */
				var exists = grep( patron.stat_cat_entries(),
					function(item) {
						return (item.stat_cat() == statcat.id()); 
					}
				);

				if(newval) {
					map.isdeleted(0);
					setSelector($n(row, 'ue_stat_cat_selector'), newval);
				}

				if(exists) {
					if(!newval) {

						/* if the map is new but currently contains no value
							remove it from the set of new maps */
						if(map.isnew()) {
							patron.stat_cat_entries(
								grep( patron.stat_cat_entries(),
									function(item) {
										return (item.stat_cat() != map.stat_cat());
									}
								)
							);

						} else {
							map.isdeleted(1);
							map.ischanged(0);
						}
					} 

				} else {

					/* map does not exist in the map array but now has data */
					if(newval) { 
						map.isnew(1);
						if(!patron.stat_cat_entries())
							patron.stat_cat_entries([]);
						patron.stat_cat_entries().push(map);
					}
				}
			}
		}
	}

	dataFields.push(field);
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
		vfield.errkey = 'ue_bad_ident_ssn';
		unHideMe($(type+'_ident_ssn_help'));

	} else {

		if(name.match(/driver/i)) {
			vfield.widget.regex = dlRegex;
			vfield.errkey = 'ue_bad_ident_dl';
			unHideMe($(type+'_ident_dl_help'));
			if(!uEditNodeVal(vfield))
				vfield.widget.node.value = defaultState + '-';

		} else {
			vfield.widget.regex = null;
			vfield.errkey = null;
		}
	}

	/* focus then valdate the value field */
	vfield.widget.node.onchange();
	vfield.widget.node.focus();
}


/* checks to see if the given address is shared by others.
 * if so, the address row is styled and ...
 */

function uEditCheckSharedAddr(patron, address, tbody, row) {

	if( address.isnew() || (patron.isnew() && !clone) ) return;

	var req = new Request(FETCH_ADDR_MEMS, SESSION, address.id());
	req.callback( 
		function(r) {

			var members = r.getResultObject();
			var shared = false;

			for( var m in members ) {
				var id = members[m];

				if( id != patron.id() ) {

					addCSSClass(row.getElementsByTagName('table')[0], 'shared_address');
					unHideMe($n(row, 'shared_row'));
					$n(row, 'ue_addr_delete').disabled = true;

					if( address.usr() != patron.id() ) {
						var button = $n(row, 'ue_addr_detach');
						unHideMe(button);
						button.onclick = 
							function() { uEditDeleteAddr( tbody, row, address, true ); }
					}

					shared = true;
					break;
				}
			}

			if( shared ) {

				/* if this is a shared address, set the owner field and 
					give the staff a chance to edit the owner if it's not this user */

				var nnode = $n(row, 'addr_owner_name');
				var link = $n(row, 'addr_owner');
				var id = address.usr();
			
				if( id == patron.id() ) {
			
					nnode.appendChild(text(
						patron.first_given_name() + ' ' + patron.family_name()));
					hideMe($n(row, 'owner_link_div'));
			
				} else {
			
					var ses = cgi.param('ses'); 
					if (xulG) if (xulG.ses) ses = xulG.ses;
					if (xulG) if (xulG.params) if (xulG.params.ses) ses = xulG.params.ses;
					link.onclick = 
						function() { window.xulG.spawn_editor({ses:ses,usr:id}) };
				
					if( userCache[id] ) {
                        var usr = userCache[id];
						nnode.appendChild(text(
							usr.first_given_name() + ' ' +  usr.family_name()));
				
					} else {
				
						fetchFleshedUser( id, 
							function(usr) {
								userCache[usr.id()] = usr;
								nnode.appendChild(text(
									usr.first_given_name() + ' ' + usr.family_name()));
							}
						);
					}
				}
			}
		}
	);

	req.send();
}




var __lastdob;
function uEditCheckDOB(field) {

	var dob = uEditNodeVal(field);
    var ident_field = uEditFindFieldByKey('ident_value2');

    if(dob) {

        /* don't bother if the data isn't valid */
        if(!dob.match(field.widget.regex)) 
            return;

        if( dob == __lastdob ) return;

        __lastdob = dob;

        var parts = dob.split(/-/);
        parts[2] = parts[2].replace(/[T ].*/,'');
        dob = buildDate( parts[0], parts[1], parts[2] );

        var today = new Date();

        if(!dob || dob > today) {
            addCSSClass(field.widget.node, CSS_INVALID_DATA);
            alertId('ue_bad_date');
            return;
        }

        var base = new Date();
        var age;
        if(orgSettings['global.juvenile_age_threshold'])
            age = orgSettings['global.juvenile_age_threshold'].value;
        else age = DEFAULT_ADULT_AGE;
        base.setTime(base.getTime() - Number(interval_to_seconds(age) + '000'));


        unHideMe(ident_field.widget.node.parentNode.parentNode.parentNode);
        if( dob < base ) { /* patron is of age */
            ident_field.required = false;
	        uEditFindFieldByKey('juvenile').widget.node.checked = false;
            if(!uEditNodeVal(ident_field))
                hideMe(ident_field.widget.node.parentNode.parentNode.parentNode);
            return;
        }

    } else {
        // no DOB and we are not flagged as a juvenile
        if(uEditFindFieldByKey('juvenile').widget.node.checked == false) {
            if(!uEditNodeVal(ident_field))
                hideMe(ident_field.widget.node.parentNode.parentNode.parentNode);
            return;
        }
    }

    unHideMe(ident_field.widget.node.parentNode.parentNode.parentNode);
    if(!uEditFindFieldByKey('juvenile').widget.node.checked)
	    uEditFindFieldByKey('juvenile').widget.node.checked = true;
	ident_field.required = true;
	uEditCheckErrors();
}



