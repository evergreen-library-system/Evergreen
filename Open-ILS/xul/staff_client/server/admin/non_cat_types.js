var FETCH_NON_CAT_TYPES = "open-ils.circ:open-ils.circ.non_cat_types.retrieve.all";
var CREATE_NON_CAT_TYPE = "open-ils.circ:open-ils.circ.non_cat_type.create";
var UPDATE_NON_CAT_TYPE = "open-ils.circ:open-ils.circ.non_cat_type.update";
var DELETE_NON_CAT_TYPE = 'open-ils.circ:open-ils.circ.non_cataloged_type.delete';
var myPerms = [ 
	'CREATE_NON_CAT_TYPE', 
	'UPDATE_NON_CAT_TYPE',
	'DELETE_NON_CAT_TYPE' ];

var focusOrg;

function ncEditorInit() {
	fetchUser();
	$('nc_user').appendChild(text(USER.usrname()));
	setTimeout( 
        function() { 
            fetchHighestWorkPermOrgs(SESSION, USER.id(), myPerms,
                function() {
                    ncSetupFocus();
		            ncBuildNew();
		            ncFetchTypes();
                }
            ); 
        }, 20 );
}

function ncSetupFocus() {
	var fselector = $('nc_org_filter');
    var org_list = OILS_WORK_PERMS.UPDATE_NON_CAT_TYPE;
    if(org_list.length == 0) 
        return;
	fselector.disabled = false;
	buildMergedOrgSel(fselector, org_list, 0, 'shortname');
    fselector.onchange = function() {
        focusOrg = getSelectorVal(fselector);
        ncBuildNew();
        ncFetchTypes();
    }
    
    focusOrg = USER.ws_ou();
    if(!orgIsMineFromSet(org_list, USER.ws_ou())) 
        focusOrg = org_list[0];
    setSelector(fselector, focusOrg);
}

function ncBuildNew() {

	var name = $('nc_new_name');
	name.focus();

    var org_list = OILS_WORK_PERMS.CREATE_NON_CAT_TYPE;
    if(org_list.length == 0) return;

	var selector = $('nc_new_owner');
	buildMergedOrgSel(selector, org_list, 0, 'shortname');
	selector.disabled = false;

	$('nc_new_submit').disabled = false;
	$('nc_new_submit').onclick = ncCreateNew;
}


function ncFetchTypes() {
	var req = new Request( FETCH_NON_CAT_TYPES, focusOrg );	
	req.callback(ncDisplayTypes);
	setTimeout(function(){req.send();}, 500);
}

function ncCreateNew() {
	var name = $('nc_new_name').value;
	if(!name) return;
	var org = getSelectorVal($('nc_new_owner'));
	var time = $('nc_new_interval_count').value;
	var type = getSelectorVal($('nc_new_interval_type'));
	var inh = $('nc_new_inhouse').checked ? 1 : null;

	var req = new Request(CREATE_NON_CAT_TYPE, SESSION, name, org, time + ' ' + type, inh );
	req.request.alertEvent = false;
	req.send(true);
	var res = req.result();

	if(checkILSEvent(res)) {
		if( res.textcode == 'NON_CAT_TYPE_EXISTS' )
			return alertId('nc_type_exists');
		alert(js2JSON(res));
	}

	alertId('nc_update_success');
	ncFetchTypes();
}


var rowTemplate;
function ncDisplayTypes(r) {

	var types = r.getResultObject();
	var tbody = $('nc_tbody');
	if(!rowTemplate) 
		rowTemplate = tbody.removeChild($('nc_row_template'));

	removeChildren(tbody);
	types = types.sort( 
		function(a,b) {
			try {
				if( a.name()+''.toLowerCase() > b.name()+''.toLowerCase() ) return 1;	
				if( a.name()+''.toLowerCase() < b.name()+''.toLowerCase() ) return -1;	
			} catch(e) {}
			return 0;
		});

	for( var idx = 0; idx != types.length; idx++ ) {

		var type = types[idx];
		var org = findOrgUnit( type.owning_lib() );
		var row = rowTemplate.cloneNode(true);


		row.id = 'nc_row_' + type.id();
		$n(row, 'nc_name').appendChild(text(type.name()));
		$n(row, 'nc_owner').appendChild(text(org.name()));
		$n(row, 'nc_inhouse').checked = isTrue(type.in_house());

		var idata = _splitInterval(type.circ_duration());
		$n(row, 'nc_interval_count').value = idata[0];
		setSelector( $n(row, 'nc_interval_type'), idata[1]);

		ncSetRowCallbacks( type, org, tbody, row );
		tbody.appendChild(row);
	}
}

/* this is a kind of brittle, but works with the data we create */
function _splitInterval( interval ) {
	interval = interval.split(/ /);
	var time = interval[0];
	var type = interval[1];
	 
	if( time.match(/:/) ) {
		var d = time.split(/:/);
		if(d[0] == '00') return [ d[1], 'minutes' ];
		if(d[0] != '00' && d[1] != '00')
			return [ parseInt(d[1]) + (d[0]*60), 'minutes' ];
		return [ d[0], 'hours' ]
	}

	if( type.match(/mi/i) ) return [ time, 'minutes' ];
	if( type.match(/h/i) ) return [ time, 'hours' ];
	if( type.match(/d/i) ) return [ time, 'days' ];
	if( type.match(/w/i) ) return [ time, 'weeks' ];
	if( type.match(/mo/i) ) return [ time, 'months' ];
}

function ncSetRowCallbacks( type, owner, tbody, row ) {

	checkPermOrgDisabled($n(row, 'nc_edit'), owner, 'UPDATE_NON_CAT_TYPE');

	checkPermOrgDisabled($n(row, 'nc_delete'), owner, 'DELETE_NON_CAT_TYPE');

	$n(row, 'nc_edit').onclick = 
		function() { ncEditType( tbody, row, type ); };

	$n(row, 'nc_delete').onclick = 
		function() { ncDeleteType( tbody, row, type ); };
}

function ncEditType( tbody, row, type ) {
	cleanTbody(row.parentNode, 'edit');
	var row = $('nc_edit_row_template').cloneNode(true);

	var name = $n(row, 'nc_edit_name');
	name.value = type.name();

	var idata = _splitInterval(type.circ_duration());
	$n(row, 'nc_edit_interval_count').value = idata[0];
	setSelector( $n(row, 'nc_edit_interval_type'), idata[1]);

	$n(row, 'nc_edit_inhouse').checked = isTrue(type.in_house());
	$n(row, 'nc_edit_owner').appendChild(text( findOrgUnit(type.owning_lib()).name() ));

	$n(row, 'nc_edit_submit').onclick = function() { 
		var name = $n(row, 'nc_edit_name').value;
		var time = $n(row, 'nc_edit_interval_count').value;
		var tp = getSelectorVal($n(row, 'nc_edit_interval_type'));
		var inh = $n(row, 'nc_edit_inhouse').checked ? 't' : 'f';
		ncEditSubmit( type, name, time + ' ' + tp, inh );
	};

	$n(row, 'nc_edit_cancel').onclick = 
		function(){cleanTbody(row.parentNode, 'edit'); }

	var r = $('nc_row_' + type.id());
	if(r.nextSibling) tbody.insertBefore( row, r.nextSibling );
	else{ tbody.appendChild(row); }

	name.focus();
	name.select();
}

function ncEditSubmit( type, name, interval, inhouse ) {
	if(!name) return;
	type.name(name);
	type.circ_duration(interval);
	type.in_house(inhouse);
	var req = new Request( UPDATE_NON_CAT_TYPE, SESSION, type );
	req.send(true);
	var res = req.result();
	if(checkILSEvent(res)) throw res;
	alertId('nc_update_success');
	ncFetchTypes();
}

function ncDeleteType( tbody, row, type ) {
	if( ! confirm($('nc_delete_confirm').innerHTML) ) return;
	var req = new Request(DELETE_NON_CAT_TYPE, SESSION, type.id());
	req.callback( 
		function(r) {
			var res = r.getResultObject();
			if(checkILSEvent(res)) alertILSEvent(res);
			alertId('nc_update_success');
			ncFetchTypes();
		}
	);
	req.send();
}




