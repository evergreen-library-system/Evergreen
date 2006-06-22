var FETCH_CLOSED_DATES	= 'open-ils.actor:open-ils.actor.org_unit.closed.retrieve.all';
var FETCH_CLOSED_DATE	= 'open-ils.actor:open-ils.actor.org_unit.closed.retrieve';
var CREATE_CLOSED_DATE	= 'open-ils.actor:open-ils.actor.org_unit.closed.create';
var DELETE_CLOSED_DATE	= 'open-ils.actor:open-ils.actor.org_unit.closed.delete';

var cdRowTemplate;
var cdAllDayTemplate;
var cdAllMultiDayTemplate;

var cdTbody;
var cdDateCache = {};

var selectedStart;
var selectedEnd;

var cdBaseOrg;


var myPerms = [ 
	'actor.org_unit.closed_date.delete',
	'actor.org_unit.closed_date.create',
	];

function cdEditorInit() {

	/* set the various template rows */
	cdTbody = $('cd_tbody');
	cdRowTemplate					= cdTbody.removeChild($('cd_row'));
	cdAllDayTemplate				= cdTbody.removeChild($('cd_allday_row'));
	cdAllMultiDayTemplate		= cdTbody.removeChild($('cd_allmultiday_row'));

	cdInitCals();

	fetchUser();
	$('cd_user').appendChild(text(USER.usrname()));

	setTimeout( 
		function() { 
			fetchHighestPermOrgs( SESSION, USER.id(), myPerms );
			cdBuildOrgs();
			cdDrawRange();
		}, 
		20 
	);
}

function cdCurrentOrg() {
	var selector = $('cd_orgs');
	return getSelectorVal(selector);
}

function cdBuildOrgs() {
	var org = findOrgUnit(PERMS['actor.org_unit.closed_date.create']);
	if( !org || org == -1 ) org = findOrgUnit(USER.ws_ou());
	var type = findOrgType(org.ou_type()) ;

	var selector = $('cd_orgs');
	buildOrgSel(selector, org, type.depth());
	if(!type.can_have_users()) selector.options[0].disabled = true;

	selector.onchange = function() { cdDrawRange(); };

	cdBaseOrg = org;
	var gotoOrg = USER.ws_ou();
	if( ! setSelector( selector, gotoOrg ) ) {
		gotoOrg = USER.home_ou();
		setSelector( selector, gotoOrg );
	}

	var neworg = findOrgUnit(PERMS['actor.org_unit.closed_date.create']);
	if(!neworg || neworg == -1 || !orgIsMine(neworg, findOrgUnit(cdCurrentOrg()))) {
		$('cd_new_allday').disabled = true;
		$('cd_new_multiday').disabled = true;
		$('cd_new').disabled = true;
	}

	return gotoOrg;
}

function cdInitCals() {

	Calendar.setup({
		inputField  : "cd_edit_allday_start_date",
		ifFormat    : "%Y-%m-%d",
		button      : "cd_edit_allday_start_date_img",
		align       : "Tl",
		singleClick : true
	});

	Calendar.setup({
		inputField  : "cd_edit_allmultiday_start_date",
		ifFormat    : "%Y-%m-%d",
		button      : "cd_edit_allmultiday_start_date_img",
		align       : "Tl",
		singleClick : true
	});

	Calendar.setup({
		inputField  : "cd_edit_allmultiday_end_date",
		ifFormat    : "%Y-%m-%d",
		button      : "cd_edit_allmultiday_end_date_img",
		align       : "Tl",
		singleClick : true
	});

	Calendar.setup({
		inputField  : "cd_edit_end_date",
		ifFormat    : "%Y-%m-%d",
		button      : "cd_edit_end_date_img",
		align       : "Tl",
		singleClick : true
	});

	Calendar.setup({
		inputField  : "cd_edit_start_date",
		ifFormat    : "%Y-%m-%d",
		button      : "cd_edit_start_date_img",
		align       : "Tl",
		singleClick : true
	});


}

function cdDrawRange( start, end ) {
	start = (start) ? start : new Date().getYear() + 1900 + '-01-01';
	end = (end) ? end : '3001-01-01';

	selectedStart = start;
	selectedEnd = end;

	var req = new Request(
		FETCH_CLOSED_DATES, SESSION, 
		{
			orgid			: cdCurrentOrg(),
			start_date	: start,
			end_date		: end,
			idlist		: 0
		}
	);

	req.callback( cdBuild );
	req.send();  
}

/* adds one row in the display table per date */
function cdBuild(r) {
	var dates = r.getResultObject();
	removeChildren(cdTbody);
	for( var d = 0; d < dates.length; d++ ) {
		var date = dates[d];
		var row = cdBuildRow( date );
		cdTbody.appendChild(row);
	}
}

function cdDateToHours(date) {
	var d = new Date.W3CDTF();
	d.setW3CDTF(date.replace(/\.\d+/,'') + ":00");

	var h = d.getHours() +'';
	var m = d.getMinutes() +'';
	var s = d.getSeconds() +'';

	if(h.length == 1) h = '0'+h;
	if(m.length == 1) m = '0'+m;
	if(s.length == 1) s = '0'+s;

	return  h + ':' + m + ':' + s;
}

function cdDateToDate(date) {
	var d = new Date.W3CDTF();
	d.setW3CDTF(date.replace(/\.\d+/,'') + ":00");

	var y = d.getFullYear()+'';
	var m = (d.getMonth() + 1)+'';
	var d = d.getDate()+'';

	if(m.length == 1) m = '0'+m;
	if(d.length == 1) d = '0'+d;

	return  y + '-' + m + '-' + d;
}


/* fleshes a single date */
function cdBuildRow( date ) {

	cdDateCache[date.id()] = date;

	var sh = cdDateToHours(date.close_start());
	var sd = cdDateToDate(date.close_start());
	var eh = cdDateToHours(date.close_end());
	var ed = cdDateToDate(date.close_end());

	var row;
	var flesh = false;

	if( sh == '00:00:00' && eh == '23:59:59' ) {

		if( sd == ed ) {
			row = cdAllDayTemplate.cloneNode(true);
			$n(row, 'start_date').appendChild(text(sd));

		} else {
			row = cdAllMultiDayTemplate.cloneNode(true);
			$n(row, 'start_date').appendChild(text(sd));
			$n(row, 'end_date').appendChild(text(ed));
		}

	} else {

		row = cdRowTemplate.cloneNode(true);	
		cdEditFleshRow(row, date);
	}

	$n(row,'delete').onclick = function() { cdDelete(row, date); };
	$n(row, 'note').appendChild(text(date.reason()));

	/* if we don't have delete perms for this location, disable the button */
	var delorg = findOrgUnit(PERMS['actor.org_unit.closed_date.delete']);
	if(!orgIsMine(delorg, findOrgUnit(cdCurrentOrg()))) $n(row,'delete').disabled = true;

	return row;
}

function cdEditFleshRow(row, date) {
	$n(row, 'start_time').appendChild(text(cdDateToHours(date.close_start())));
	$n(row, 'start_date').appendChild(text(cdDateToDate(date.close_start())));
	$n(row, 'end_time').appendChild(text(cdDateToHours(date.close_end())));
	$n(row, 'end_date').appendChild(text(cdDateToDate(date.close_end())));
}


function cdShowEditRow(id) {
	cdCancelEdit();
	unHideMe($(id));
	unHideMe($('cd_edit_submit'));
	unHideMe($('cd_edit_note_row'));
}

function cdCancelEdit() {
	hideMe($('cd_edit_row'));
	hideMe($('cd_edit_allday_row'));
	hideMe($('cd_edit_allmultiday_row'));
	hideMe($('cd_edit_submit'));
	hideMe($('cd_edit_note_row'));
}




function cdDelete(row, date) {
	if(!confirmId('cd_confirm_delete')) return;
	var req = new Request(DELETE_CLOSED_DATE, SESSION, date.id() );
	req.callback(
		function(r) {
			var res = r.getResultObject();
			if( checkILSEvent(res) ) alertILSEvent(res);
			cdDrawRange(selectedStart, selectedEnd);
		}
	)
	req.send();
}


/* getW3CDTF */

function cdVerifyDate(d) {
	return d && d.match(/\d{4}-\d{2}-\d{2}/);
}

function cdVerifyTime(t) {
	return t && t.match(/\d{2}:\d{2}:\d{2}/);
}

function cdDateStrToDate( str ) {

	var date = new Date.W3CDTF();
	var data = str.split(/ /);

	var year = data[0];
	var time	= data[1];

	if(!cdVerifyDate(year)) return alertId('cd_invalid_date');
	if(!cdVerifyTime(time)) return alertId('cd_invalid_time');

	var yeardata = year.split(/-/);
	var timedata = time.split(/:/);

	date.setFullYear(yeardata[0]);
	date.setMonth(yeardata[1] - 1);
	date.setDate(yeardata[2]);

	date.setHours(timedata[0]);
	date.setMinutes(timedata[1]);
	date.setSeconds(timedata[2]);

	return date;
}

function cdNew() {

	var start;
	var end;

	if( ! $('cd_edit_allday_row').className.match(/hide_me/) ) {

		var date = $('cd_edit_allday_start_date').value;
		start = cdDateStrToDate(date + ' 00:00:00');
		end = cdDateStrToDate(date + ' 23:59:59');

	} else if( ! $('cd_edit_allmultiday_row').className.match(/hide_me/) ) {

		var sdate = $('cd_edit_allmultiday_start_date').value;
		var edate = $('cd_edit_allmultiday_end_date').value;
		start = cdDateStrToDate(sdate + ' 00:00:00');
		end = cdDateStrToDate(edate + ' 23:59:59');

	} else {

		var sdate = $('cd_edit_start_date').value;
		var edate = $('cd_edit_end_date').value;
		var stime;
		var etime;

		if($('cd_edit_start_time_allday').checked) {
			stime = '00:00';
		} else {
			stime = $('cd_edit_start_time').value;
		}

		stime += ':00';

		if($('cd_edit_end_time_allday').checked) {
			etime = '23:59:59';
		} else {
			etime = $('cd_edit_end_time').value;
			etime += ':00';
		}

		start = cdDateStrToDate(sdate + ' ' + stime);
		end = cdDateStrToDate(edate + ' ' + etime);
	}

	cdCreate(start, end, $('cd_edit_note').value);
}

function cdCreate(start, end, note) {

	var date = new aoucd();

	date.close_start(start.getW3CDTF());
	date.close_end(end.getW3CDTF());
	date.org_unit(cdCurrentOrg());
	date.reason(note);

	var req = new Request(CREATE_CLOSED_DATE, SESSION, date);
	req.callback(
		function(r) {
			var res = r.getResultObject();
			if( checkILSEvent(res) ) alertILSEvent(res);
			cdDrawRange(selectedStart, selectedEnd);
		}
	);
	req.send();
}



