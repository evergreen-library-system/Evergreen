var g = {};

var FETCH_HOLD_LIST            = 'open-ils.circ:open-ils.circ.hold_pull_list.retrieve';
var FETCH_COPY                    = 'open-ils.search:open-ils.search.asset.copy.fleshed.custom';
var FETCH_USER                    = 'open-ils.actor:open-ils.actor.user.fleshed.retrieve';
var FETCH_VOLUME                = 'open-ils.search:open-ils.search.callnumber.retrieve';

var myPerms                = [ 'VIEW_HOLD' ];
var HOLD_LIST_LIMIT    = 100;
var numHolds            = 0;

var listOffset            = 0;

function pullListInit() {
    if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
    JSAN.errorLevel = "die"; // none, warn, or die
    JSAN.addRepository('/xul/server/');
    JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.stash_retrieve();
    JSAN.use('util.date');

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
    var pl = typeof hold.pickup_lib() == 'object' ? hold.pickup_lib().shortname() : g.data.hash.aou[ hold.pickup_lib() ].shortname();
    $n(row, 'pickup').appendChild(text(pl));

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
    if( (parseInt(idx) +1) == numHolds ) update_ready('title');
}


function pullListDrawCopy( tbody, row, hold, idx, copy ) {

    $n(row, 'hold_type').appendChild(text(hold.hold_type()));
    $n(row, 'barcode').appendChild(text(copy.barcode()));
    $n(row, 'copy_location').appendChild(text(copy.location().name()));
    $n(row, 'copy_number').appendChild(text(copy.copy_number()));
    try {
        if (copy.age_protect()) {
            $n(row, 'age_protect').appendChild(text( (copy.age_protect() == null ? '<Unset>' : ( typeof copy.age_protect() == 'object' ? copy.age_protect().name() : g.data.hash.crahp[ copy.age_protect() ].name() )) + ' (' + util.date.formatted_date( copy.create_date(), '%{localized_date}' ) + ')' ));    
            unHideMe($n(row, 'age_protect_span'));
        }
    } catch(E) { alert(E); }

    var vreq = new Request(FETCH_VOLUME, copy.call_number());
    vreq.callback(
        function(r) { pullListDrawVolume( tbody, row, hold, idx, r.getResultObject() ); } );
    vreq.send();
}


function pullListDrawUser( tbody, row, hold, idx, user ) {
    $n(row, 'patron').appendChild(text(user.card().barcode()));
    if( (parseInt(idx) +1) == numHolds ) update_ready('patron');
}

var callNumbers = [];
function pullListDrawVolume( tbody, row, hold, idx, volume ) {
    $n(row, 'call_number').appendChild(text(volume.label()));
    callNumbers.push(volume.label());

    if( (parseInt(idx) +1) == numHolds ) update_ready('call_number');
}


function ts_getInnerText(el) {
    try {
        if (el == null) { alert('null'); return ''; }
        if (typeof el == "string") return el;
        if (typeof el == "undefined") { return el };
        if (el.innerText) return el.innerText;  //Not needed but it is faster
        var str = "";
    
        var cs = el.childNodes;
        var l = cs.length;
        for (var i = 0; i < l; i++) {
            switch (cs[i].nodeType) {
                case 1: //ELEMENT_NODE
                    str += ts_getInnerText(cs[i]);
                break;
                case 3: //TEXT_NODE
                    str += cs[i].nodeValue;
                break;
            }
        }
        return str;
    } catch(E) {
        try { 
            alert('el = ' + el + '\nel.nodeName = ' + el.nodeName + '  el.nodeType = ' + el.nodeType + '\nE = ' + E);
        } catch(F) {
            alert('el = ' + el + '\nF = ' + F + '\nE = ' + E);
        }
    }
}

function get_unhidden_span(node) {
    var nl = node.childNodes;
    var s = '';
    for (var i = 0; i < nl.length; i++) {
        if (nl[i].nodeName != 'span') continue;
        if (nl[i].getAttribute('class') != 'hide_me') s += ts_getInnerText(nl[i]);
    }
    return s;
}

function $f(parent,name) {
    var nl = parent.childNodes;
    for (var i = 0; i < nl.length; i++) {
        if (typeof nl[i].getAttribute != 'undefined' && nl[i].getAttribute('name') == name) {
            return nl[i];
        }
    }
}

function update_ready(which_update) {
    g[which_update] = true;
    if (typeof g.title != 'undefined' && typeof g.patron != 'undefined' && typeof g.call_number != 'undefined') {
        setTimeout( function() { update_ready_do_it(); }, 1000);
    }
}

function update_ready_do_it() {
    unHideMe($('pull_list_tbody')); hideMe($('inprogress'));
    var rows = [];
    var div = $('pull_list_tbody');
    var div_children = div.childNodes;
    for (var i = 0; i < div_children.length; i++) {
        var pre = div_children[i];
        if (pre.nodeName != 'pre') continue;
        value = ( 
            { 
                'call_number' : ts_getInnerText($f(pre,'call_number')), 
                'title' : ts_getInnerText($f(pre,'title')),
                'author' : ts_getInnerText($f(pre,'author')),
                'location' : ts_getInnerText($f(pre,'copy_location')),
                'copy_number' : ts_getInnerText($f(pre,'copy_number')),
                'item_type' : get_unhidden_span($f(pre,'item_type')),
                'node' : pre 
            } 
        );
        rows.push( value );
    }
    rows = rows.sort( function(a,b) { 
        function inner_sort(sort_type,a,b) {
            switch(sort_type) {
                case 'number' :
                    a = Number(a); b = Number(b);
                break;
                case 'title' : /* special case for "a" and "the".  doesn't use marc 245 indicator */
                    a = String( a ).toUpperCase().replace( /^\s*(THE|A|AN)\s+/, '' );
                    b = String( b ).toUpperCase().replace( /^\s*(THE|A|AN)\s+/, '' );
                break;
                default:
                    a = String( a ).toUpperCase();
                    b = String( b ).toUpperCase();
                break;
            }
                
            if (a < b) return -1; 
            if (a > b) return 1; 
            return 0; 
        }
        var value = inner_sort('string',a.call_number,b.call_number);
        if (value == 0) value = inner_sort('title',a.title,b.title);
        if (value == 0) value = inner_sort('string',a.author,b.author);
        if (value == 0) value = inner_sort('string',a.location,b.location);
        if (value == 0) value = inner_sort('number',a.copy_number,b.copy_number);
        if (value == 0) value = inner_sort('string',a.item_type,b.item_type);
        return value;
    } );
    while(div.lastChild) div.removeChild( div.lastChild );
    for (var i = 0; i < rows.length; i++) {
        div.appendChild( rows[i].node );
    }
}
