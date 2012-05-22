
var FETCH_HOLD_LIST            = 'open-ils.circ:open-ils.circ.hold_pull_list.retrieve';
var FETCH_COPY                    = 'open-ils.search:open-ils.search.asset.copy.fleshed.custom';
var FETCH_USER                    = 'open-ils.actor:open-ils.actor.user.fleshed.retrieve';
var FETCH_VOLUME                = 'open-ils.search:open-ils.search.callnumber.retrieve';

var myPerms                = [ 'VIEW_HOLD' ];
var HOLD_LIST_LIMIT    = 100;
var numHolds            = 0;

var listOffset            = 0;

function pullListInit() {
    fetchUser();
    $('pl_user').appendChild(text(USER.usrname()));
    $('pl_org').appendChild(text(findOrgUnit(USER.ws_ou()).name()));
    setTimeout( function() { 
        fetchHighestPermOrgs( SESSION, USER.id(), myPerms );
        pullListFetchHolds();
    }, 20 );
}

function pullListFetchHolds() {
    var req = new Request(FETCH_HOLD_LIST, SESSION, HOLD_LIST_LIMIT, listOffset );
    req.callback(pullListDrawHolds);
    req.send();
}

var holdRowTemplate;
function pullListDrawHolds(r) {
    var holds = r.getResultObject();

    var tbody = $('pull_list_tbody');
    if(!holdRowTemplate) 
        holdRowTemplate = tbody.removeChild($('pull_list_row'));
    numHolds = holds.length;

    for( var h in holds ) {
        var hold = holds[h];
        var row = holdRowTemplate.cloneNode(true);
        tbody.appendChild(row);
        pullListDrawHold( tbody, row, hold, h );
    }

}

function pullListDrawHold( tbody, row, hold, idx ) {

    $n(row, 'date').appendChild(text(hold.request_time().replace(/\ .*/, "")));

    switch( hold.hold_type() ) {
        case 'C' : unHideMe($n(row, 'copy_hold')); break;
        case 'V' : unHideMe($n(row, 'volume_hold')); break;
        case 'T' : unHideMe($n(row, 'title_hold')); break;
        case 'M' : unHideMe($n(row, 'mr_hold')); break;
    }
    
    var treq = new Request( FETCH_MODS_FROM_COPY, hold.current_copy() );
    treq.callback(
        function(r) {
            pullListDrawTitle( tbody, row, hold, idx, r.getResultObject() );    });
    treq.send();

    var creq = new Request( FETCH_COPY, hold.current_copy(), ['location'] );
    creq.callback(
        function(r) {
            pullListDrawCopy( tbody, row, hold, idx, r.getResultObject() ); });
    creq.send();

    var ureq = new Request( FETCH_USER, SESSION, hold.usr(), ['card'] );
    ureq.callback(
        function(r) {
            pullListDrawUser( tbody, row, hold, idx, r.getResultObject() ); });
    ureq.send();

}


function pullListDrawTitle( tbody, row, hold, idx, record ) {
    $n(row, 'title').appendChild(text(record.title()));
    $n(row, 'author').appendChild(text(record.author()));

    var type = modsFormatToMARC(record.types_of_resource()[0]);
    unHideMe($n(row, 'format_' + type));
}


function pullListDrawCopy( tbody, row, hold, idx, copy ) {

    $n(row, 'hold_type').appendChild(text(hold.hold_type()));
    $n(row, 'barcode').appendChild(text(copy.barcode()));
    $n(row, 'copy_location').appendChild(text(copy.location().name()));
    $n(row, 'copy_number').appendChild(text(copy.copy_number()));

    var vreq = new Request(FETCH_VOLUME, copy.call_number());
    vreq.callback(
        function(r) { pullListDrawVolume( tbody, row, hold, idx, r.getResultObject() ); } );
    vreq.send();
}


function pullListDrawUser( tbody, row, hold, idx, user ) {
    $n(row, 'patron').appendChild(text(user.card().barcode()));
}

var callNumbers = [];
function pullListDrawVolume( tbody, row, hold, idx, volume ) {
    $n(row, 'call_number').appendChild(text(volume.label()));
    callNumbers.push(volume.label());

    if( (parseInt(idx) +1) == numHolds )
        ts_resortTable($('pl_callnumber').getElementsByTagName('a')[0]);
}


