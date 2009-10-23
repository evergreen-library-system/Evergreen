var SC_FETCH_ALL        = 'open-ils.circ:open-ils.circ.stat_cat.TYPE.retrieve.all';
var SC_CREATE            = 'open-ils.circ:open-ils.circ.stat_cat.TYPE.create';
var SC_UPDATE            = 'open-ils.circ:open-ils.circ.stat_cat.TYPE.update';
var SC_DELETE            = 'open-ils.circ:open-ils.circ.stat_cat.TYPE.delete';
var SC_ENTRY_CREATE    = 'open-ils.circ:open-ils.circ.stat_cat.TYPE.entry.create';
var SC_ENTRY_UPDATE    = 'open-ils.circ:open-ils.circ.stat_cat.TYPE.entry.update';
var SC_ENTRY_DELETE    = 'open-ils.circ:open-ils.circ.stat_cat.TYPE.entry.delete';

var ACTOR                = 'actor';
var ASSET                = 'asset';
var session                = null;
var user                    = null;

var scCache                = {};
var PERMS                = {};
PERMS[ACTOR]            = {};
PERMS[ASSET]            = {};

var currentlyVisible;
var opacVisible        = false;
var cgi;
var focusOrg;

var myPerms = [    
    'CREATE_PATRON_STAT_CAT',
    'UPDATE_PATRON_STAT_CAT',
    'DELETE_PATRON_STAT_CAT',
    'CREATE_PATRON_STAT_CAT_ENTRY',
    'UPDATE_PATRON_STAT_CAT_ENTRY',
    'DELETE_PATRON_STAT_CAT_ENTRY',

    'CREATE_COPY_STAT_CAT',
    'UPDATE_COPY_STAT_CAT',
    'DELETE_COPY_STAT_CAT',
    'CREATE_COPY_STAT_CAT_ENTRY',
    'UPDATE_COPY_STAT_CAT_ENTRY',
    'DELETE_COPY_STAT_CAT_ENTRY' 
];

function scSetPerms() {
    PERMS[ACTOR].create_stat_cat = OILS_WORK_PERMS.CREATE_PATRON_STAT_CAT;
    PERMS[ACTOR].update_stat_cat = OILS_WORK_PERMS.UPDATE_PATRON_STAT_CAT;
    PERMS[ACTOR].delete_stat_cat = OILS_WORK_PERMS.DELETE_PATRON_STAT_CAT;
    PERMS[ACTOR].create_stat_cat_entry = OILS_WORK_PERMS.CREATE_PATRON_STAT_CAT_ENTRY;
    PERMS[ACTOR].update_stat_cat_entry = OILS_WORK_PERMS.UPDATE_PATRON_STAT_CAT_ENTRY;
    PERMS[ACTOR].delete_stat_cat_entry = OILS_WORK_PERMS.DELETE_PATRON_STAT_CAT_ENTRY;

    PERMS[ASSET].create_stat_cat = OILS_WORK_PERMS.CREATE_COPY_STAT_CAT;
    PERMS[ASSET].update_stat_cat = OILS_WORK_PERMS.UPDATE_COPY_STAT_CAT;
    PERMS[ASSET].delete_stat_cat = OILS_WORK_PERMS.DELETE_COPY_STAT_CAT;
    PERMS[ASSET].create_stat_cat_entry =  OILS_WORK_PERMS.CREATE_COPY_STAT_CAT_ENTRY;
    PERMS[ASSET].update_stat_cat_entry =  OILS_WORK_PERMS.UPDATE_COPY_STAT_CAT_ENTRY;
    PERMS[ASSET].delete_stat_cat_entry =  OILS_WORK_PERMS.DELETE_COPY_STAT_CAT_ENTRY;

    // set up the fitler select
    var fselector = $('sc_org_filter');
    var org_list = PERMS[currentlyVisible].update_stat_cat;
    buildMergedOrgSel(fselector, org_list, 0, 'shortname');
    var org = findOrgUnit(org_list[0]);
    if(org_list.length > 1 || (org.children() &&  org.children()[0])) 
        fselector.disabled = false;

    fselector.onchange = function() {
        focusOrg = getSelectorVal(fselector);
        scShow(currentlyVisible);
    }
    
    focusOrg = USER.ws_ou();
    if(!orgIsMineFromSet(org_list, focusOrg)) 
        focusOrg = org_list[0];
    setSelector(fselector, focusOrg);
}

function scEditorInit() {
    cgi = new CGI();
    session = cgi.param('ses');
    if(!session) throw "User session is not defined";
    user = fetchUser(session);
    $('sc_type_selector').onchange = scBuildNew;
    setTimeout( 
        function() { 
            fetchHighestWorkPermOrgs(
                session, user.id(), myPerms, function(){scGo();});
        }, 20 );
}


function scGo() {
    var show = cgi.param('show');
    if(!show) currentlyVisible = ASSET;
    scSetPerms();
    scShow(currentlyVisible);
    scBuildNew();
    $('sc_user').appendChild(text(user.usrname()));
}

function scFetchAll( session, type, orgid, callback, args ) {
    var req = new Request( 
        SC_FETCH_ALL.replace(/TYPE/, type) , session, orgid );
    req.send(true);
    return req.result();
}

function scShow(type) { 
    setTimeout(function(){_scShow(type)}, 500);
}

function _scShow(type) { 

    currentlyVisible = type;

    if( type == ASSET ) {
        addCSSClass($('sc_show_copy'), 'has_color');
        removeCSSClass($('sc_show_actor'), 'has_color');

    } else if( type == ACTOR ) {
        addCSSClass($('sc_show_actor'), 'has_color');
        removeCSSClass($('sc_show_copy'), 'has_color');
    }

    scCache[type] = scFetchAll(session, type, focusOrg);   /* XXX */
    scDraw( type, scCache[type] );
}

var scRow; var scCounter;
function scDraw( type, cats ) {

    hideMe($('loading'));

    var tbody = $('sc_tbody');
    if(!scRow) scRow = tbody.removeChild($('sc_tr'));
    removeChildren(tbody);

    if(!cats || cats.length == 0) {
        hideMe($('sc_table'));
        unHideMe($('sc_none'));
        return;
    }

    hideMe($('sc_none'));
    unHideMe($('sc_table'));

    if(type == 'actor') 
        unHideMe($('sc_usr_summary_label'));
    else
        hideMe($('sc_usr_summary_label'));

    scCounter = 0;
    for( var c in cats ) scInsertCat( tbody, cats[c], type );
}


var scEntryCounter;
function scInsertCat( tbody, cat, type ) {

    var row = scRow.cloneNode(true);
    row.id = 'sc_tr_' + cat.id();
    var name_td = $n(row, 'sc_name');
    name_td.appendChild( text(cat.name()) );
    if(scCounter++ % 2) addCSSClass(row, 'has_color');

    $n(row, 'sc_new_entry').onclick = function() { scNewEntry(type, cat, tbody); }
    $n(row, 'sc_edit').onclick = function(){ scEdit(tbody, type, cat); };
    $n(row, 'sc_owning_lib').appendChild( text( findOrgUnit(cat.owner()).name() ));

    if(isTrue(cat.opac_visible()))
        unHideMe($n(row, 'sc_opac_visible'));
    else 
        unHideMe($n(row, 'sc_opac_invisible'));

    if(type == 'actor') {
        if(isTrue(cat.usr_summary()))
            unHideMe($n(row, 'sc_usr_summary_on'));
        else 
            unHideMe($n(row, 'sc_usr_summary'));

    } else {
        hideMe($n(row, 'sc_usr_summary_td'));
    }

    tbody.appendChild(row);
    scEntryCounter = 0;

    cat.entries().sort(  /* sort the entries by value */
        function( a, b ) { 
         a = new String(a.value()).toLowerCase();
         b = new String(b.value()).toLowerCase();
            if( a > b ) return 1;
            if( a < b ) return -1;
            return 0;
        }
    );

    for( var e in cat.entries() ) 
        scInsertEntry( cat, cat.entries()[e], $n(row, 'sc_entries_selector'), tbody, type );
}


function scInsertEntry( cat, entry, selector, tbody, type ) {
    setSelectorVal( selector, scEntryCounter++, entry.value(), entry.id(), 
            function(){ scUpdateEntry( cat, entry, tbody, type );} );
}



function scDelete(type, id) {
    if(!confirm($('sc_delete_confirm').innerHTML)) return;
    var req = new Request( SC_DELETE.replace(/TYPE/,type), session, id );
    req.send(true);
    var res = req.result();
    if(checkILSEvent(res)) throw res;
    alertId('sc_update_success');
    scShow(type);
}

function scCreateEntry( type, id, row ) {
    var value = $n(row, 'sc_new_entry_name').value;
    if(!value) return;
    var entry;
    if( type == ACTOR ) entry = new actsce();
    if( type == ASSET ) entry = new asce();

    entry.isnew(1);
    entry.stat_cat(id);
    entry.owner(getSelectorVal($n(row, 'sc_new_entry_lib')));
    entry.value(value);

    var req = new Request( SC_ENTRY_CREATE.replace(/TYPE/, type), session, entry );
    req.send(true);
    var res = req.result();
    if(checkILSEvent(res)) throw res;
    alertId('sc_update_success');
    scShow(type);
}

function scNewEntry( type, cat, tbody ) {
    cleanTbody(tbody, 'edit');
    var row = $('sc_new_entry_row').cloneNode(true);
    row.setAttribute('edit', '1');

    var r = $('sc_tr_' + cat.id());
    if(r.nextSibling) tbody.insertBefore( row, r.nextSibling );
    else{ tbody.appendChild(row); }

    $n(row, 'sc_new_entry_create').onclick = 
        function() {
            if( scCreateEntry( type, cat.id(), row ) )
                tbody.removeChild(row); };
    $n(row, 'sc_new_entry_cancel').onclick = function(){tbody.removeChild(row);}

    var org_list = PERMS[type].create_stat_cat_entry;
    if(org_list.length == 0) {
        $n(row, 'sc_new_entry_create').disabled = true;
        $n(row, 'sc_new_entry_lib').disabled = true;
        return;
    }

    var rootOrg = findReleventRootOrg(org_list, cat.owner());
    if(!rootOrg) {
        $n(row, 'sc_new_entry_create').disabled = true;
        $n(row, 'sc_new_entry_lib').disabled = true;
        return;
    }
    buildOrgSel($n(row, 'sc_new_entry_lib'), rootOrg, 0, 'shortname');
    $n(row, 'sc_new_entry_name').focus();
}


function scBuildNew() {
    var libSel = $('sc_owning_lib_selector');
    var typeSel = $('sc_type_selector');
    var type = getSelectorVal(typeSel);
    var org_list = PERMS[type].create_stat_cat;
    if(org_list.length == 0) { /* no create perms */
        $('sc_new').disabled = true;
        typeSel.disabled = true;
        libSel.disabled = true;
        return;
    }
    buildMergedOrgSel(libSel, org_list, 0, 'shortname');
}


function scNew() {

    var name = $('sc_new_name').value;
    var type = getSelectorVal($('sc_type_selector'));

    var visible = 0;
    if( $('sc_make_opac_visible').checked) visible = 1;

    var cat;
    if( type == ACTOR ) cat = new actsc();
    if( type == ASSET ) cat = new asc();

    cat.opac_visible(visible);
    cat.name(name);
    cat.owner(getSelectorVal($('sc_owning_lib_selector')));
    cat.isnew(1);

    var req = new Request( SC_CREATE.replace(/TYPE/, type), session, cat );

    req.send(true);
    var res = req.result();
    if(checkILSEvent(res)) throw res;
    alertId('sc_update_success');

    scShow(type);
}

function scEdit( tbody, type, cat ) {

    cleanTbody(tbody, 'edit');
    var row = $('sc_edit_row').cloneNode(true);
    row.setAttribute('edit', '1');

    var r = $('sc_tr_' + cat.id());
    if(r.nextSibling) { tbody.insertBefore( row, r.nextSibling ); }
    else{ tbody.appendChild(row); }

    $n(row, 'sc_edit_name').value = cat.name();

    if(type == 'actor') {
        var cb = $n(row, 'sc_edit_usr_summary');
        cb.checked = isTrue(cat.usr_summary()); 
    } else {
        hideMe($n(row, 'sc_edit_usr_summary_td'));
    }

    var name = $n(row, 'sc_edit_cancel');
    name.onclick = function() { tbody.removeChild(row); };

    var show = $n(row, 'sc_edit_show_owning_lib');
    
    var myorg = findOrgUnit(user.home_ou());
    var ownerorg = findOrgUnit(cat.owner());
    show.appendChild(text(ownerorg.name()));

    var selector = null;
    if( myorg.children() && myorg.children().length > 0 ) {
        selector = $n(row, 'sc_edit_owning_lib');
        buildOrgSel( selector, myorg, findOrgDepth(myorg), 'shortname');
        setSelector( selector, cat.owner() );
        unHideMe(selector);

    } else { unHideMe(show); }

    name.focus();
    name.select();

    if( cat.opac_visible() != 0 && cat.opac_visible() != '0' ) {
        $n( $n(row, 'sc_edit_opac_vis'), 
            'sc_edit_opac_visibility').checked = true;
    } else {
        $n( $n(row, 'sc_edit_opac_invis'), 
            'sc_edit_opac_visibility').checked = true;
    }

    $n(row, 'sc_edit_submit').onclick = 
        function() { scEditGo( type, cat, row, selector ); };

    $n(row, 'sc_edit_delete').onclick = 
        function(){ scDelete(type, cat.id()); };

    var rootEditOrg = findReleventRootOrg(PERMS[type].update_stat_cat, cat.owner());
    var rootDelOrg = findReleventRootOrg(PERMS[type].delete_stat_cat, cat.owner());

    if(!rootEditOrg || rootEditOrg.id() != cat.owner())
        $n(row,'sc_edit_submit').disabled = true;

    if(!rootDelOrg || rootDelOrg.id() != cat.owner())
        $n(row,'sc_edit_delete').disabled = true;
}

function scEditGo( type, cat, row, selector ) {
    var name = $n(row, 'sc_edit_name').value;
    var visible = 
        $n( $n(row, 'sc_edit_opac_vis'), 'sc_edit_opac_visibility').checked;

    var newlib = cat.owner();
    if(selector) newlib = getSelectorVal( selector );

    if(!name) return false;

    var isvisible = false;
    if( cat.opac_visible() != 0 && cat.opac_visible() != '0' ) isvisible = true;

    var usr_summary = $n(row, 'sc_edit_usr_summary').checked;

    if( (name == cat.name()) && 
        (visible == isvisible) && 
        (newlib == cat.owner()) && 
        (usr_summary == isTrue(cat.usr_summary())) )
            return true; 

    cat.name( name );
    cat.owner( newlib );
    cat.entries(null);
    cat.opac_visible(0);
    if( visible ) cat.opac_visible(1);
    cat.usr_summary( (usr_summary) ? 1 : 0 );

    var req = new Request( SC_UPDATE.replace(/TYPE/,type), session, cat );
    req.send(true);
    var res = req.result();
    if(checkILSEvent(res)) throw res;
    alertId('sc_update_success');
    scShow(type);

    return true;
}

function scUpdateEntry( cat, entry, tbody, type ) {
    cleanTbody(tbody, 'edit');
    var row = $('sc_edit_entry_row').cloneNode(true);
    row.setAttribute('edit', '1');

    var r = $('sc_tr_' + cat.id());
    if(r.nextSibling) tbody.insertBefore( row, r.nextSibling );
    else{ tbody.appendChild(row); }

    $n(row, 'sc_edit_entry_owner').appendChild(text(findOrgUnit(entry.owner()).name()));

    var name = $n(row, 'sc_edit_entry_name');
    name.value = entry.value();
    name.focus();
    name.select();

    $n(row,'sc_edit_entry_name_submit').onclick = 
        function(){
            if( scEditEntry(cat, entry, name.value, type ) )
                tbody.removeChild(row);
            };

    $n(row,'sc_edit_entry_cancel').onclick = function(){tbody.removeChild(row);};
    $n(row,'sc_edit_entry_delete').onclick = 
        function(){ scEntryDelete( cat, entry, type ); }

    var rootEditOrg = findReleventRootOrg(PERMS[type].update_stat_cat_entry, entry.owner());
    var rootDelOrg = findReleventRootOrg(PERMS[type].delete_stat_cat_entry, entry.owner());

    if(!rootEditOrg || rootEditOrg.id() != entry.owner())
        $n(row,'sc_edit_submit').disabled = true;

    if(!rootDelOrg || rootDelOrg.id() != entry.owner())
        $n(row,'sc_edit_delete').disabled = true;
}

function scEntryDelete( cat, entry, type ) {
    if(!confirm($('sc_entry_delete_confirm').innerHTML)) return;
    var req = new Request( SC_ENTRY_DELETE.replace(/TYPE/,type), session, entry.id() );
    req.send(true);
    var res = req.result();
    if(checkILSEvent(res)) throw res;
    alertId('sc_update_success');
    scShow(type);
}

function scEditEntry( cat, entry, newvalue, type ) {
    if(entry.value() == newvalue) return;
    entry.value( newvalue );
    var req = new Request( 
        SC_ENTRY_UPDATE.replace(/TYPE/, type), session, entry );
    req.send(true);
    var res = req.result();
    if(checkILSEvent(res)) throw res;
    scShow(type);
}

