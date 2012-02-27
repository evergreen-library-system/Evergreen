var RETRIEVE_CL = 'open-ils.circ:open-ils.circ.copy_location.retrieve.all';
var CREATE_CL = 'open-ils.circ:open-ils.circ.copy_location.create';
var UPDATE_CL = 'open-ils.circ:open-ils.circ.copy_location.update';
var DELETE_CL = 'open-ils.circ:open-ils.circ.copy_location.delete';


var YES;
var NO;
var _TRUE;
var _FALSE;
var locationSet;
var focusOrg;

var myPerms = [
    'CREATE_COPY_LOCATION',
    'UPDATE_COPY_LOCATION', 
    'DELETE_COPY_LOCATION',
    ];

function clEditorInit() {
    cgi = new CGI();
    session = cgi.param('ses');
    if(!session && (location.protocol == 'chrome:' || location.protocol == 'oils:')) {
        try {
            var CacheClass = Components.classes["@open-ils.org/openils_data_cache;1"].getService();
            session = CacheClass.wrappedJSObject.data.session.key;
        } catch(e) {
            console.log("Error loading XUL stash: " + e);
        }
    }
    if(!session) throw "User session is not defined!";
    fetchUser(session);
    $('user').appendChild(text(USER.usrname()));
    YES = $('yes').innerHTML;
    NO = $('no').innerHTML;
    _TRUE = $('true');
    _FALSE = $('false');
    locationSet = [];

    setTimeout( 
        function() { 
            fetchHighestWorkPermOrgs( SESSION, USER.id(), myPerms ); 
            $('cl_new_name').focus();
            clBuildNew();
            clGo(); 
        }, 20 );
}


function clHoldMsg() {
    alert($('cl_hold_msg').innerHTML);
}

function clGo() {    
    setTimeout(function(){clGo2();}, 500);
}

function clGo2() {    
    locationSet = {};
    var req = new Request(RETRIEVE_CL, focusOrg, true /* no i18n */);
    req.request._last = true;
    req.callback(clAppendLocation);
    req.send();

    /*  if we need to add view-all ability, can use this... 
    var org_list = OILS_WORK_PERMS['CREATE_COPY_LOCATION'];
    for(var i = 0; i < org_list.length; i++) {
        var req = new Request(RETRIEVE_CL, org_list[i]);
        req.callback(clAppendLocation);
        if(i == org_list.length - 1) 
            req.request._last = true;
        req.send();
    }
    */
}

function clAppendLocation(r) {
    var cls = r.getResultObject();
    if(checkILSEvent(cls)) throw cls;
    for(var i = 0; i < cls.length; i++) 
        locationSet[cls[i].id()] = cls[i];
    if(r._last) 
        clDraw();
}

function clBuildNew() {
    org_list = OILS_WORK_PERMS['CREATE_COPY_LOCATION'];
    var org;
    if(org_list.length == 0)
        return;
    var selector = $('cl_new_owner');
    var fselector = $('cl_org_filter');
    buildMergedOrgSel(selector, org_list, 0, 'shortname');
    buildMergedOrgSel(fselector, org_list, 0, 'shortname');
    var org = findOrgUnit(org_list[0]);
    if(org_list.length > 1 || (org.children() &&  org.children()[0])) {
        selector.disabled = false;
        fselector.disabled = false;
    }

    fselector.onchange = function() {
        focusOrg = getSelectorVal(fselector);
        clGo();
    }
    
    focusOrg = USER.ws_ou();
    if(!orgIsMineFromSet(org_list, USER.ws_ou())) 
        focusOrg = org_list[0];
    setSelector(fselector, focusOrg);


    var sub = $('sc_new_submit');
    sub.disabled = false;
    sub.onclick = clCreateNew;
}

function clCreateNew() {
    var cl = new acpl();
    cl.name( $('cl_new_name').value );
    cl.owning_lib( getSelectorVal( $('cl_new_owner')));
    cl.holdable( ($('cl_new_hold_yes').checked) ? 1 : 0 );
    cl.hold_verify( ($('cl_new_hold_verify_yes').checked) ? 1 : 0 );
    cl.opac_visible( ($('cl_new_vis_yes').checked) ? 1 : 0 );
    cl.circulate( ($('cl_new_circulate_yes').checked) ? 1 : 0 );
    cl.checkin_alert( $('cl_new_checkin_alert_yes').checked ? 1 : 0 );
    cl.label_prefix( $('cl_new_label_prefix').value );
    cl.label_suffix( $('cl_new_label_suffix').value );

    var req = new Request(CREATE_CL, SESSION, cl);
    req.send(true);
    var res = req.result();
    if(checkILSEvent(res)) throw res;
    alertId('cl_update_success');
    clGo();
}

var rowTemplate;
function clDraw() {

    var cls = [];
    for(var x in locationSet)
        cls.push(locationSet[x]);

    var tbody = $('cl_tbody');
    if(!rowTemplate)
        rowTemplate = tbody.removeChild($('cl_row'));
    removeChildren(tbody);

    for(var i = 0; i < cls.length; i++) /* force stringify */
        cls[i].name(new String(cls[i].name()));

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
    $n( row, 'cl_owner').appendChild(text(findOrgUnit(cl.owning_lib()).shortname()));

    appendClear($n( row, 'cl_holdable'), (isTrue(cl.holdable())) ? _TRUE.cloneNode(true) : _FALSE.cloneNode(true) );
    appendClear($n( row, 'cl_hold_verify'), (isTrue(cl.hold_verify())) ? _TRUE.cloneNode(true) : _FALSE.cloneNode(true) );
    appendClear($n( row, 'cl_visible'), (isTrue(cl.opac_visible())) ? _TRUE.cloneNode(true) : _FALSE.cloneNode(true) );
    appendClear($n( row, 'cl_circulate'), (isTrue(cl.circulate())) ? _TRUE.cloneNode(true) : _FALSE.cloneNode(true) );
    appendClear($n( row, 'cl_checkin_alert'), (isTrue(cl.checkin_alert())) ? _TRUE.cloneNode(true) : _FALSE.cloneNode(true) );
    $n( row, 'cl_label_prefix').appendChild(text(cl.label_prefix() || ''));
    $n( row, 'cl_label_suffix').appendChild(text(cl.label_suffix() || ''));

    var edit = $n( row, 'cl_edit');
    edit.onclick = function() { clEdit( cl, tbody, row ); };
    checkPermOrgDisabled(edit, cl.owning_lib(), 'UPDATE_COPY_LOCATION');

    if (!window._cl_per_row)
        window._cl_per_row = [];
    window._cl_per_row.push(cl);
    new openils.widget.TranslatorPopup({
        "targetObject":
            "window._cl_per_row[" + (window._cl_per_row.length - 1) + "]",
        "field": "name"
    }, $n(row, "cl_xlate_popup"));

    var del = $n( row, 'cl_delete' );
    del.onclick = function() { clDelete( cl, tbody, row ); };
    checkPermOrgDisabled(del, cl.owning_lib(), 'DELETE_COPY_LOCATION');
}

function clEdit( cl, tbody, row ) {

    cleanTbody(tbody, 'edit');
    var r = $('cl_edit').cloneNode(true);
    r.setAttribute('edit','1');
    
    var name = $n(r, 'cl_edit_name');
    name.setAttribute('size', cl.name().length + 3);
    name.value = cl.name();

    $n(r, 'cl_edit_owner').appendChild(text(findOrgUnit(cl.owning_lib()).shortname()));

    var arr = _clOptions(r);
    if(isTrue(cl.holdable())) arr[0].checked = true;
    else arr[1].checked = true;
    if(isTrue(cl.opac_visible())) arr[2].checked = true;
    else arr[3].checked = true;
    if(isTrue(cl.circulate())) arr[4].checked = true;
    else arr[5].checked = true;
    if(isTrue(cl.hold_verify())) arr[6].checked = true;
    else arr[7].checked = true;
    if(isTrue(cl.checkin_alert())) arr[8].checked = true;
    else arr[9].checked = true;

    var label_prefix = $n(r, 'cl_edit_label_prefix');
    if (cl.label_prefix()) {
        label_prefix.setAttribute('size', cl.label_prefix().length + 3);
    } else {
        label_prefix.setAttribute('size', 3);
    }
    label_prefix.value = cl.label_prefix();

    var label_suffix = $n(r, 'cl_edit_label_suffix');
    if (cl.label_suffix()) {
        label_suffix.setAttribute('size', cl.label_suffix().length + 3);
    } else {
        label_suffix.setAttribute('size', 3);
    }
    label_suffix.value = cl.label_suffix();

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
    arr[6] = $n( $n(r,'cl_edit_hold_verify_yes'), 'cl_edit_hold_verify');
    arr[7] = $n( $n(r,'cl_edit_hold_verify_no'), 'cl_edit_hold_verify');
    arr[8] = $n( $n(r,'cl_edit_checkin_alert_yes'), 'cl_edit_checkin_alert');
    arr[9] = $n( $n(r,'cl_edit_checkin_alert_no'), 'cl_edit_checkin_alert');
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
    if(arr[6].checked) cl.hold_verify(1);
    else cl.hold_verify(0);
    if(arr[8].checked) cl.checkin_alert(1);
    else cl.checkin_alert(0);
    cl.name($n(r, 'cl_edit_name').value);
    cl.label_prefix($n(r, 'cl_edit_label_prefix').value);
    cl.label_suffix($n(r, 'cl_edit_label_suffix').value);

    var req = new Request( UPDATE_CL, SESSION, cl );
    req.send(true);
    var res = req.result();
    if(checkILSEvent(res)) throw res;
    alertId('cl_update_success');

    clGo();
}


function clDelete( cl, tbody, row ) {
    if(!confirm($('cl_delete_confirm').innerHTML)) return;
    var req = new Request( DELETE_CL, SESSION, cl.id() );
    req.send(true);
    var res = req.result();
    if(checkILSEvent(res)) throw res;
    alertId('cl_update_success');
    clGo();
}


