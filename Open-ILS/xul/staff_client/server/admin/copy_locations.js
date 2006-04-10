var RETRIEVE_CL = 'open-ils.circ:open-ils.circ.copy_location.retrieve.all';
var CREATE_CL = 'open-ils.circ:open-ils.circ.copy_location.create';
var UPDATE_CL = 'open-ils.circ:open-ils.circ.copy_location.update';
var DELETE_CL = 'open-ils.circ:open-ils.circ.copy_location.delete';


var YES;
var NO;

var myPerms = [
	'CREATE_COPY_LOCATION',
	'UPDATE_COPY_LOCATION', 
	'DELETE_COPY_LOCATION',
	];

function clEditorInit() {
	cgi = new CGI();
	session = cgi.param('ses');
	if(!session) throw "User session is not defined!";
	fetchUser(session);
	$('user').appendChild(text(USER.usrname()));
	YES = $('yes').innerHTML;
	NO = $('no').innerHTML;

	setTimeout( 
		function() { 
			fetchHighestPermOrgs( SESSION, USER.id(), myPerms ); 
			$('cl_new_name').focus();
			clBuildNew();
			clGo(); 
		}, 20 );
}


function clHoldMsg() {
	alert($('cl_hold_msg').innerHTML);
}

function clGo() {	
	var req = new Request(RETRIEVE_CL, USER.ws_ou());
	req.callback(clDraw);
	req.send();
}

function clBuildNew() {
	org = PERMS['CREATE_COPY_LOCATION'];
	if(org == -1) return;
	var selector = $('cl_new_owner');
	org = findOrgUnit(org);
	buildOrgSel(selector, org, findOrgDepth(org));
	if(org.children() && org.children()[0]) 
		selector.disabled = false;

	var sub = $('sc_new_submit');
	sub.disabled = false;
	sub.onclick = clCreateNew;
}

function clCreateNew() {
	var cl = new acpl();
	cl.name( $('cl_new_name').value );
	cl.owning_lib( getSelectorVal( $('cl_new_owner')));
	cl.holdable( ($('cl_new_hold_yes').checked) ? 1 : 0 );
	cl.opac_visible( ($('cl_new_vis_yes').checked) ? 1 : 0 );
	cl.circulate( ($('cl_new_circulate_yes').checked) ? 1 : 0 );

	var req = new Request(CREATE_CL, SESSION, cl);
	req.send(true);
	var res = req.result();
	if(checkILSEvent(res)) throw res;
	clGo();
}

var rowTemplate;
function clDraw(r) {

	var cls = r.getResultObject();
	if(checkILSEvent(cls)) throw cls;

	var tbody = $('cl_tbody');
	if(!rowTemplate)
		rowTemplate = tbody.removeChild($('cl_row'));
	removeChildren(tbody);

	cls = cls.sort( function(a,b) {
			if( a.name().toLowerCase() > b.name().toLowerCase() ) return 1;
			if( a.name().toLowerCase() < b.name().toLowerCase() ) return -1;
			return 0;
		});

	for( var c in cls ) {
		var cl = cls[c];
		var row = rowTemplate.cloneNode(true);
		clBuildRow( tbody, row, cl );
		tbody.appendChild(row);
	}
}

function clBuildRow( tbody, row, cl ) {
	$n( row, 'cl_name').appendChild(text(cl.name()));
	$n( row, 'cl_owner').appendChild(text(findOrgUnit(cl.owning_lib()).name()));
	$n( row, 'cl_holdable').appendChild(text( (cl.holdable()) ? YES : NO ) );
	$n( row, 'cl_visible').appendChild(text( (cl.opac_visible()) ? YES : NO ) );
	$n( row, 'cl_circulate').appendChild(text( (cl.circulate()) ? YES : NO ) );

	var edit = $n( row, 'cl_edit');
	edit.onclick = function() { clEdit( cl, tbody, row ); };
	checkDisabled( edit, cl.owning_lib(), 'UPDATE_COPY_LOCATION');

	var del = $n( row, 'cl_delete' );
	del.onclick = function() { clDelete( cl, tbody, row ); };
	checkDisabled( del, cl.owning_lib(), 'DELETE_COPY_LOCATION');
}

function clEdit( cl, tbody, row ) {

	cleanTbody(tbody, 'edit');
	var r = $('cl_edit').cloneNode(true);
	r.setAttribute('edit','1');
	
	var name = $n(r, 'cl_edit_name');
	name.setAttribute('size', cl.name().length + 3);
	name.value = cl.name();

	$n(r, 'cl_edit_owner').appendChild(text(findOrgUnit(cl.owning_lib()).name()));

	var arr = _clOptions(r);
	if(cl.holdable()) arr[0].checked = true;
	else arr[1].checked = true;
	if(cl.opac_visible()) arr[2].checked = true;
	else arr[3].checked = true;
	if(cl.circulate()) arr[4].checked = true;
	else arr[5].checked = true;

	$n(r, 'cl_edit_cancel').onclick = function(){cleanTbody(tbody,'edit');}
	$n(r, 'cl_edit_commit').onclick = function(){clEditCommit( tbody, r, cl ); }

	insRow(tbody, row, r);
	name.focus();
	name.select();
}

function _clOptions(r) {
	var arr = [];
	arr[0] = $n( $n(r,'cl_edit_holdable_yes'), 'cl_edit_holdable');
	arr[1] = $n( $n(r,'cl_edit_holdable_no'), 'cl_edit_holdable');
	arr[2] = $n( $n(r,'cl_edit_visible_yes'), 'cl_edit_visible');
	arr[3] = $n( $n(r,'cl_edit_visible_no'), 'cl_edit_visible');
	arr[4] = $n( $n(r,'cl_edit_circulate_yes'), 'cl_edit_circulate');
	arr[5] = $n( $n(r,'cl_edit_circulate_no'), 'cl_edit_circulate');
	return arr;
}

function clEditCommit( tbody, r, cl ) {

	var arr = _clOptions(r);
	if(arr[0].checked) cl.holdable(1);
	else cl.holdable(0);
	if(arr[2].checked) cl.opac_visible(1);
	else cl.opac_visible(0);
	if(arr[4].checked) cl.circulate(1);
	else cl.circulate(0);
	cl.name($n(r, 'cl_edit_name').value);

	var req = new Request( UPDATE_CL, SESSION, cl );
	req.send(true);
	var res = req.result();
	if(checkILSEvent(res)) throw res;

	clGo();
}


function clDelete( cl, tbody, row ) {
	if(!confirm($('cl_delete_confirm').innerHTML)) return;
	var req = new Request( DELETE_CL, SESSION, cl.id() );
	req.send(true);
	var res = req.result();
	if(checkILSEvent(res)) throw res;

	clGo();
}


