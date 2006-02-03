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
	setTimeout( function() { 
		fetchHighestPermOrgs( SESSION, USER.id(), myPerms ); clGo(); }, 20 );
}


function clHoldMsg() {
	alert($('cl_hold_msg').innerHTML);
}

function clGo() {
	var req = new Request(RETRIEVE_CL, SESSION, USER.home_ou());
	req.callback(clDraw);
	req.send();
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
	$n( row, 'cl_edit').onclick = function() { clEdit( cl, tbody, row ); };
}

function clEdit( cl, tbody, row ) {

	cleanTbody(tbody, 'edit');
	var r = $('cl_new').cloneNode(true);
	r.setAttribute('edit','1');
	
	var name = $n(r, 'cl_new_name');
	name.setAttribute('size', cl.name().length + 3);
	name.value = cl.name();

	$n(r, 'cl_new_owner').appendChild(text(findOrgUnit(cl.owning_lib()).name()));

	var yhold = $n( $n(r,'cl_new_holdable_yes'), 'cl_new_holdable');
	var nhold = $n( $n(r,'cl_new_holdable_no'), 'cl_new_holdable');
	var yvis = $n( $n(r,'cl_new_visible_yes'), 'cl_new_visible');
	var nvis = $n( $n(r,'cl_new_visible_no'), 'cl_new_visible');
	var ycirc = $n( $n(r,'cl_new_circulate_yes'), 'cl_new_circulate');
	var ncirc = $n( $n(r,'cl_new_circulate_no'), 'cl_new_circulate');

	if(cl.holdable()) yhold.checked = true;
	else nhold.checked = true;
	if(cl.opac_visible()) yvis.checked = true;
	else nvis.checked = true;
	if(cl.circulate()) ycirc.checked = true;
	else ncirc.checked = true;

	$n(r, 'cl_new_cancel').onclick = function(){cleanTbody(tbody,'edit');}
	$n(r, 'cl_new_commit').onclick = function(){clEditCommit( tbody, cl ); }

	insRow(tbody, row, r);
	name.focus();
	name.select();
}

function clEditCommit( tbody, cl ) {
	alert("committing: " + cl.id());	
	cleanTbody(tbody,'edit');
}
