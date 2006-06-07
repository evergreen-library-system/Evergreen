var FETCH_CLOSED_DATES	= 'open-ils.actor:open-ils.actor.org_unit.closed.retrieve.all';
var FETCH_CLOSED_DATE	= 'open-ils.actor:open-ils.actor.org_unit.closed.retrieve';
var CREATE_CLOSED_DATE	= 'open-ils.actor:open-ils.actor.org_unit.closed.create';
var DELETE_CLOSED_DATE	= 'open-ils.actor:open-ils.actor.org_unit.closed.delete';

var cdEditRowTemplate;
var cdRowTemplate;
var cdTbody;


var myPerms = [ 
	'actor.org_unit.closed_date.delete',
	'actor.org_unit.closed_date.create',
	];

function cdEditorInit() {

	/* set the various template rows */
	cdTbody = $('cd_tbody');
	cdEditRowTemplate = cdTbody.removeChild($('cd_edit_row'));
	cdRowTemplate = cdTbody.removeChild($('cd_row'));

	fetchUser();
	$('cd_user').appendChild(text(USER.usrname()));

	setTimeout( 
		function() { 
			fetchHighestPermOrgs( SESSION, USER.id(), myPerms );
			cdDrawRange();
		}, 
		20 
	);
}

function cdDrawRange( start, end ) {
	start = (start) ? start : new Date().getYear() + 1900 + '-01-01';
	end = (end) ? end : '3001-01-01';

	var req = new Request(
		FETCH_CLOSED_DATES, SESSION, 
		{
			orgid			: USER.ws_ou(), 
			start_date	: start,
			end_date		: end,
			idlist		: 0
		}
	);

	req.callback( cdBuild );
	req.send();  
}

function cdBuild(r) {

	var dates = r.getResultObject();
	for( var d = 0; d < dates.length; d++ ) {
		var date = dates[d];
		var row = cdRowTemplate.cloneNode(true);
		$n(row, 'start_time').appendChild(text(date.close_start()));
		$n(row, 'start_date').appendChild(text(date.close_start()));
		$n(row, 'end_time').appendChild(text(date.close_end()));
		$n(row, 'end_date').appendChild(text(date.close_end()));
		cdTbody.appendChild(row);
	}
}

