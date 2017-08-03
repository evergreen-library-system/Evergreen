dojo.require('fieldmapper.AutoIDL');
dojo.require('fieldmapper.Fieldmapper');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.Event');

var myPackageDir = 'open_ils_staff_client'; var IAMXUL = true; var g = {};
var FETCH_CLOSED_DATES    = 'open-ils.actor:open-ils.actor.org_unit.closed.retrieve.all';
var FETCH_CLOSED_DATE    = 'open-ils.actor:open-ils.actor.org_unit.closed.retrieve';
var CREATE_CLOSED_DATE    = 'open-ils.actor:open-ils.actor.org_unit.closed.create';
var DELETE_CLOSED_DATE    = 'open-ils.actor:open-ils.actor.org_unit.closed.delete';

var cdRowTemplate;
var cdAllDayTemplate;
var cdAllMultiDayTemplate;

var cdTbody;
var cdDateCache = {};
var orgTZ = {};

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
    cdRowTemplate                    = cdTbody.removeChild($('cd_row'));
    cdAllDayTemplate                = cdTbody.removeChild($('cd_allday_row'));
    cdAllMultiDayTemplate        = cdTbody.removeChild($('cd_allmultiday_row'));

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

    if( cdBaseOrg.children() && cdBaseOrg.children().length > 0 )
        unHideMe($('cd_apply_all_div'));

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

function cdDrawRange( start, end, alertSuccess ) {
    start = (start) ? start : new Date().getYear() + 1899 + '-01-01'; /* include last year's closed info for comparison */
    end = (end) ? end : '3001-01-01';

    if(alertSuccess) alertId('cd_update_success');

    selectedStart = start;
    selectedEnd = end;

    var req = new Request(
        FETCH_CLOSED_DATES, SESSION, 
        {
            orgid            : cdCurrentOrg(),
            start_date    : start,
            end_date        : end,
            idlist        : 0
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
        // super-closure!
        (function (date) {
            cdGetTZ(date.org_unit(), function () {
                var row = cdBuildRow( date );
                cdTbody.appendChild(row);
            })
        })(date);
    }
}

function cdDateToHours(date, org) {
    var date_obj = moment(date).tz(orgTZ[org]);
    var hrs = date_obj.hours();
    var mins = date_obj.minutes();
    // wee, strftime
    if (hrs < 10) hrs = '0' + hrs;
    if (mins < 10) mins = '0' + mins;
    return hrs + ':' + mins;
}

function cdDateToDate(date, org) {
    var date_obj = moment(date).tz(orgTZ[org]);
    return date_obj.format('YYYY-MM-DD');
}

function cdGetTZ(org, callback) {
    if (orgTZ[org]) {
        if (callback) callback();
        return;
    }

    fieldmapper.standardRequest(
        [   'open-ils.actor',
            'open-ils.actor.ou_setting.ancestor_default.batch'],
        {   async: true,
            params: [org, ['lib.timezone'], SESSION],
            oncomplete: function(r) {
                var data = r.recv().content();
                if(e = openils.Event.parse(data))
                    return alert(e);
                if (data['lib.timezone'] && data['lib.timezone'].value) {
                    orgTZ[org] = data['lib.timezone'].value;
                } else {
                    orgTZ[org] = OpenSRF.tz;
                }
                if (callback) callback();
            }
        }
    );
}


/* fleshes a single date */
function cdBuildRow( date ) {

    cdDateCache[date.id()] = date;

    var sh = cdDateToHours(date.close_start(), date.org_unit());
    var sd = cdDateToDate(date.close_start(), date.org_unit());
    var eh = cdDateToHours(date.close_end(), date.org_unit());
    var ed = cdDateToDate(date.close_end(), date.org_unit());

    var row;
    var flesh = false;

    if( isTrue(date.full_day()) ) {

        if( !isTrue(date.multi_day()) ) {
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
    $n(row, 'start_time').appendChild(text(cdDateToHours(date.close_start(), date.org_unit())));
    $n(row, 'start_date').appendChild(text(cdDateToDate(date.close_start(), date.org_unit())));
    $n(row, 'end_time').appendChild(text(cdDateToHours(date.close_end(), date.org_unit())));
    $n(row, 'end_date').appendChild(text(cdDateToDate(date.close_end(), date.org_unit())));
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
            cdDrawRange(selectedStart, selectedEnd, true);
        }
    )
    req.send();
}


function cdVerifyDate(d) {
    return d && d.match(/\d{4}-\d{2}-\d{2}/);
}

function cdVerifyTime(t) {
    return t && t.match(/\d{2}:\d{2}:\d{2}/);
}

function cdDateStrToDate( str, org, callback ) {
    if (!org) org = cdCurrentOrg();

    if (callback) { // async mode
        if (!orgTZ[org]) { // fetch then call again
            return cdGetTZ(org, function () {
                cdDateStrToDate( str, org, callback );
            });
        } else {
            var d = cdDateStrToDate( str, org );
            return callback(d);
        }
    }

    var date;
    if (orgTZ[org]) {
        date = moment(new Date()).tz(orgTZ[org]);
    } else {
         date = moment(new Date());
    }

    var data = str.replace(/\s+/, 'T').split(/T/);

    var year = data[0];
    var time = data[1];

    if(!cdVerifyDate(year)) return alertId('cd_invalid_date');
    if(!cdVerifyTime(time)) return alertId('cd_invalid_time');

    var yeardata = year.split(/-/);
    var timedata = time.split(/:/);
    
    /*  seed the date with day = 1, which is a valid day for any month.  
        this prevents automatic date correction by the date code for days that 
        fall outside of the current or target month */
    date.date(1);

    date.year(new Number(yeardata[0]));
    date.month(new Number(yeardata[1]) - 1);
    date.date(new Number(yeardata[2]));

    date.hour(new Number(timedata[0]));
    date.minute(new Number(timedata[1]));
    date.second(new Number(timedata[2]));

    return date;
}

function cdNew() {

    var start;
    var end;
    var full_day = 0;
    var multi_day = 0;

    if( ! $('cd_edit_allday_row').className.match(/hide_me/) ) {

        var date = $('cd_edit_allday_start_date').value;

        start = cdDateStrToDate(date + 'T00:00:00');
        end = cdDateStrToDate(date + 'T23:59:59');
        full_day = 1;

    } else if( ! $('cd_edit_allmultiday_row').className.match(/hide_me/) ) {

        var sdate = $('cd_edit_allmultiday_start_date').value;
        var edate = $('cd_edit_allmultiday_end_date').value;
        start = cdDateStrToDate(sdate + 'T00:00:00');
        end = cdDateStrToDate(edate + 'T23:59:59');
        full_day = 1;
        multi_day = 1;

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

        start = cdDateStrToDate(sdate + 'T' + stime);
        end = cdDateStrToDate(edate + 'T' + etime);
    }

    if (end.unix() < start.unix()) {
        alertId('cd_invalid_date_span');
        return;
    }

    cdCreate(start, end, $('cd_edit_note').value, full_day, multi_day);
}

function cdCreate(start, end, note, full_day, multi_day) {

    if( $('cd_apply_all').checked ) {
        var list = cdGetOrgList();
        for( var o = 0; o < list.length; o++ ) {
            var id = list[o].id();
            cdCreateOne( id, start, end, note, full_day, multi_day, (id == cdCurrentOrg()) );
        }

    } else {

        cdCreateOne( cdCurrentOrg(), start, end, note, full_day, multi_day, true );
    }
}

function cdGetOrgList(org) {
    if(!org) org = cdBaseOrg;

    var list = [];
    var type = findOrgType(org.ou_type()) ;
    if( type.can_have_users() ) list.push(org);

    if( org.children() ) {
        for( var i = 0; i < org.children().length; i++ ) {
            var child = org.children()[i];
            if( child ) {
                var l = cdGetOrgList(child);
                for( var j = 0; j < l.length; j++ )
                    list.push(l[j]);
            }
        }
    }

    return list;
}

function cdCreateOne( org, start, end, note, full_day, multi_day, refresh ) {
    var date = new aoucd();

    // force TZ normalization
    cdDateStrToDate(start.format('YYYY-MM-DD HH:mm:ss'), org, function (s) {
        start = s;
        cdDateStrToDate(end.format('YYYY-MM-DD HH:mm:ss'), org, function (e) {
            end = e;

            date.close_start(start.toISOString());
            date.close_end(end.toISOString());
            date.org_unit(org);
            date.reason(note);
            date.full_day(full_day);
            date.multi_day(multi_day);
        
            var req = new Request(CREATE_CLOSED_DATE, SESSION, date);
            req.callback(
                function(r) {
                    var res = r.getResultObject();
                    if( checkILSEvent(res) ) alertILSEvent(res);
                    if(refresh) cdDrawRange(selectedStart, selectedEnd, true);
                }
            );
            req.send();
        });
    });

}

