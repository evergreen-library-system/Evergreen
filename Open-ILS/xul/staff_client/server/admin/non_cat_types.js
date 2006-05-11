var FETCH_NON_CAT_TYPES = "open-ils.circ:open-ils.circ.non_cat_types.retrieve.all";
var CREATE_NON_CAT_TYPE = "open-ils.circ:open-ils.circ.non_cat_type.create";
var UPDATE_NON_CAT_TYPE = "open-ils.circ:open-ils.circ.non_cat_type.update";
var DELETE_NON_CAT_TYPE = 'open-ils.circ:open-ils.circ.non_cataloged_type.delete';
var myPerms = [ 
	'CREATE_NON_CAT_TYPE', 
	'UPDATE_NON_CAT_TYPE',
	'DELETE_NON_CAT_TYPE' ];

function ncEditorInit() {
	fetchUser();
	$('nc_user').appendChild(text(USER.usrname()));
	setTimeout( function() { 
		fetchHighestPermOrgs( SESSION, USER.id(), myPerms );
		ncBuildNew();
		ncFetchTypes(); }, 20 );
}


function ncBuildNew() {

	var name = $('nc_new_name');
	name.focus();
	setEnterFunc(name, ncCreateNew );

	var org = findOrgUnit(PERMS['CREATE_NON_CAT_TYPE']);
	var mydepth = findOrgDepth(org);
	if( mydepth == -1 ) return;

	var selector = $('nc_new_owner');
	buildOrgSel(selector, org, mydepth );
	if(org.children() && org.children()[0]) 
		selector.disabled = false;

	$('nc_new_submit').disabled = false;
	$('nc_new_submit').onclick = ncCreateNew;
}


function ncFetchTypes() {
	var req = new Request( FETCH_NON_CAT_TYPES, USER.home_ou() );	
	req.callback(ncDisplayTypes);
	req.send();
}

function ncCreateNew() {
	var name = $('nc_new_name').value;
	if(!name) return;
	var org = getSelectorVal($('nc_new_owner'));
	var req = new Request(CREATE_NON_CAT_TYPE, SESSION, name, org );
	req.send(true);
	var res = req.result();
	if(checkILSEvent(res)) throw res;
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
			if( a.name().toLowerCase() > b.name().toLowerCase() ) return 1;	
			if( a.name().toLowerCase() < b.name().toLowerCase() ) return -1;	
			return 0;
		});


	for( var idx = 0; idx != types.length; idx++ ) {
		var type = types[idx];
		var org = findOrgUnit( type.owning_lib() );
		var row = rowTemplate.cloneNode(true);
		row.id = 'nc_row_' + type.id();
		$n(row, 'nc_name').appendChild(text(type.name()));
		$n(row, 'nc_owner').appendChild( text( org.name() ));
		ncSetRowCallbacks( type, org, tbody, row );
		tbody.appendChild(row);
	}
}

function ncSetRowCallbacks( type, owner, tbody, row ) {

	checkDisabled( $n(row, 'nc_edit'), owner, 'UPDATE_NON_CAT_TYPE');

	/*
	mydepth = findOrgDepth( PERMS['DELETE_NON_CAT_TYPE'] );
	if( mydepth != -1 && mydepth <= tdepth ) $n(row, 'nc_delete').disabled = false;
	*/
	checkDisabled( $n(row, 'nc_delete'), owner, 'DELETE_NON_CAT_TYPE' );

	$n(row, 'nc_edit').onclick = 
		function() { ncEditType( tbody, row, type ); };

	$n(row, 'nc_delete').onclick = 
		function() { ncDeleteType( tbody, row, type ); };
}

function ncEditType( tbody, row, type ) {
	cleanTbody(row.parentNode, 'edit');
	var row = $('nc_edit_row_temaplate').cloneNode(true);

	var name = $n(row, 'nc_edit_name');
	name.value = type.name();

	$n(row, 'nc_edit_submit').onclick = function() { 
		var name = $n(row, 'nc_edit_name').value;
		ncEditSubmit( type, name );
	};

	$n(row, 'nc_edit_cancel').onclick = 
		function(){cleanTbody(row.parentNode, 'edit'); }

	var r = $('nc_row_' + type.id());
	if(r.nextSibling) tbody.insertBefore( row, r.nextSibling );
	else{ tbody.appendChild(row); }

	name.focus();
	name.select();
}

function ncEditSubmit( type, name ) {
	if(!name) return;
	type.name(name);
	var req = new Request( UPDATE_NON_CAT_TYPE, SESSION, type );
	req.send(true);
	var res = req.result();
	if(checkILSEvent(res)) throw res;
	ncFetchTypes();
}

function ncDeleteType( tbody, row, type ) {
	if( ! confirm($('nc_delete_confirm').innerHTML) ) return;
	var req = new Request(DELETE_NON_CAT_TYPE, SESSION, type.id());
	req.callback( 
		function(r) {
			var res = r.getResultObject();
			if(checkILSEvent(res)) alertILSEvent(res);
			ncFetchTypes();
		}
	);
	req.send();
}




