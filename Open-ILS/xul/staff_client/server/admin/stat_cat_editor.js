var SC_FETCH_ALL        = 'open-ils.circ:open-ils.circ.stat_cat.TYPE.retrieve.all';
var SC_FETCH_SF         = 'open-ils.pcrud:open-ils.pcrud.search.PCRUD.atomic';
var SC_CREATE            = 'open-ils.circ:open-ils.circ.stat_cat.TYPE.create';
var SC_UPDATE            = 'open-ils.circ:open-ils.circ.stat_cat.TYPE.update';
var SC_DELETE            = 'open-ils.circ:open-ils.circ.stat_cat.TYPE.delete';
var SC_ENTRY_CREATE    = 'open-ils.circ:open-ils.circ.stat_cat.TYPE.entry.create';
var SC_ENTRY_UPDATE    = 'open-ils.circ:open-ils.circ.stat_cat.TYPE.entry.update';
var SC_ENTRY_DELETE    = 'open-ils.circ:open-ils.circ.stat_cat.TYPE.entry.delete';
var SC_ENTRY_DEFAULT_CREATE    = 'open-ils.circ:open-ils.circ.stat_cat.actor.entry.default.create';
var SC_ENTRY_DEFAULT_DELETE    = 'open-ils.circ:open-ils.circ.stat_cat.actor.entry.default.delete';

var ACTOR                = 'actor';
var ASSET                = 'asset';
var session                = null;
var user                    = null;

var scCache                = {};
var PERMS                = {};
PERMS[ACTOR]            = {};
PERMS[ASSET]            = {};

var PCRUD_CLASS         = {};
PCRUD_CLASS[ACTOR]      = 'actscsf';
PCRUD_CLASS[ASSET]      = 'ascsf';

scSFCache               = {};

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
    'CREATE_PATRON_STAT_CAT_ENTRY_DEFAULT',
    'UPDATE_PATRON_STAT_CAT_ENTRY_DEFAULT',
    'DELETE_PATRON_STAT_CAT_ENTRY_DEFAULT',

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
    PERMS[ACTOR].create_stat_cat_default_entry = OILS_WORK_PERMS.CREATE_PATRON_STAT_CAT_ENTRY_DEFAULT;
    PERMS[ACTOR].update_stat_cat_default_entry = OILS_WORK_PERMS.UPDATE_PATRON_STAT_CAT_ENTRY_DEFAULT;
    PERMS[ACTOR].delete_stat_cat_default_entry = OILS_WORK_PERMS.DELETE_PATRON_STAT_CAT_ENTRY_DEFAULT;

    PERMS[ASSET].create_stat_cat = OILS_WORK_PERMS.CREATE_COPY_STAT_CAT;
    PERMS[ASSET].update_stat_cat = OILS_WORK_PERMS.UPDATE_COPY_STAT_CAT;
    PERMS[ASSET].delete_stat_cat = OILS_WORK_PERMS.DELETE_COPY_STAT_CAT;
    PERMS[ASSET].create_stat_cat_entry =  OILS_WORK_PERMS.CREATE_COPY_STAT_CAT_ENTRY;
    PERMS[ASSET].update_stat_cat_entry =  OILS_WORK_PERMS.UPDATE_COPY_STAT_CAT_ENTRY;
    PERMS[ASSET].delete_stat_cat_entry =  OILS_WORK_PERMS.DELETE_COPY_STAT_CAT_ENTRY;

    // set up the filter select
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
    if(!session && (location.protocol == 'chrome:' || location.protocol == 'oils:')) {
        try {
            var CacheClass = Components.classes["@open-ils.org/openils_data_cache;1"].getService();
            session = CacheClass.wrappedJSObject.data.session.key;
        } catch(e) {
            console.log("Error loading XUL stash: " + e);
        }
    }
    if(!session) throw "User session is not defined";
    user = fetchUser(session);
    $('sc_type_selector').onchange = scBuildNew;
    setTimeout( 
        function() { 
            fetchHighestWorkPermOrgs(
                session, user.id(), myPerms, function(){scGo();});
        }, 20 );
}

function scPopSipFields( selector, type ) {
    while(selector.lastChild.value != '') selector.removeChild(selector.lastChild);
    if(!scSFCache[type]) {
        var req = new Request( 
            SC_FETCH_SF.replace(/PCRUD/, PCRUD_CLASS[type]) , session, { 'field' : { '!=' : null } } );
        req.send(true);
        scSFCache[type] = req.result();
    }
    for(var f in scSFCache[type]) {
        var option = document.createElement('option');
        option.value = scSFCache[type][f].field();
        option.appendChild(text(scSFCache[type][f].name() + ' (' + scSFCache[type][f].field() + ')' + (isTrue(scSFCache[type][f].one_only()) ? '**' : '')));
        selector.appendChild(option);
    }
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

    if(type == ACTOR) {
        unHideMe($('sc_usr_summary_label'));
        unHideMe($('sc_usr_freetext_label'));
    } else {
        hideMe($('sc_usr_summary_label'));
        hideMe($('sc_usr_freetext_label'));
    }

    scCounter = 0;
    for( var c in cats ) scInsertCat( tbody, cats[c], type );
}


var scEntryCounter;
function scInsertCat( tbody, cat, type ) {

    var default_entry_id = -1;
    var row = scRow.cloneNode(true);
    row.id = 'sc_tr_' + cat.id();
    var required = cat.required();
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

    if(cat.sip_field().length != 2)
        unHideMe($n(row, 'sc_sip_field_none'));
    else {
        $n(row, 'sc_sip_field_value').appendChild( text( cat.sip_field() ) );
        unHideMe($n(row, 'sc_sip_field_value'));
    }

    $n(row, 'sc_sip_format_td').appendChild( text( cat.sip_format() ) );

    if(isTrue(cat.checkout_archive()))
        unHideMe($n(row, 'sc_checkout_archive_on'));
    else
        unHideMe($n(row, 'sc_checkout_archive'));

    if(isTrue(required))
        unHideMe($n(row, 'sc_required_on'));
    else 
        unHideMe($n(row, 'sc_required'));

    if(type == ACTOR) {
        if(isTrue(cat.usr_summary()))
            unHideMe($n(row, 'sc_usr_summary_on'));
        else 
            unHideMe($n(row, 'sc_usr_summary'));

        if(isTrue(cat.allow_freetext()))
            unHideMe($n(row, 'sc_usr_freetext_on'));
        else 
            unHideMe($n(row, 'sc_usr_freetext'));
    } else {
        hideMe($n(row, 'sc_usr_summary_td'));
        hideMe($n(row, 'sc_usr_freetext_td'));
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

    for( var e in cat.entries() ) { 
        if (scInsertEntry( cat, cat.entries()[e], $n(row, 'sc_entries_selector'), tbody, type ))
            default_entry_id =  cat.entries()[e].id();
    }
    
    if (default_entry_id > 0)
        setSelector($n(row, 'sc_entries_selector'), default_entry_id);
}


function scInsertEntry( cat, entry, selector, tbody, type ) {
    var val = entry.value();
    var entry_id = entry.id();
    var is_default_entry = false;

    if(type == ACTOR) {
        if( cat.default_entries()[0] && cat.default_entries()[0].stat_cat_entry() == entry_id ) {
            val = val + "*";
            is_default_entry = true;
        }
    }
    setSelectorVal( selector, scEntryCounter++, val, entry_id, 
            function(){ scUpdateEntry( cat, entry, tbody, type );} );

    return is_default_entry;
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

         
    var default_entry;
    if ( type == ACTOR && $n(row, 'sc_new_entry_default_set').checked ) {
        default_entry = new actsced();
        default_entry.isnew(1);
        default_entry.stat_cat(id);
        default_entry.owner(getSelectorVal($n(row, 'sc_new_entry_default_lib')));
        entry.default_entries([default_entry]);
    }
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

    if(type == ACTOR) {
        unHideMe($n(row, 'sc_new_entry_default'));
    } else {
        hideMe($n(row, 'sc_new_entry_default'));
    }

    $n(row, 'sc_new_entry_create').onclick = 
        function() {
            if( scCreateEntry( type, cat.id(), row ) )
                tbody.removeChild(row); };
    $n(row, 'sc_new_entry_cancel').onclick = function(){tbody.removeChild(row);}

    var org_list = PERMS[type].create_stat_cat_entry;
    if(org_list.length == 0) {
        $n(row, 'sc_new_entry_create').disabled = true;
        $n(row, 'sc_new_entry_lib').disabled = true;
        if (type==ACTOR)
            $n(row, 'sc_new_entry_default_lib').disabled = true;
        return;
    }

    var rootOrg = findReleventRootOrg(org_list, cat.owner());
    if(!rootOrg) {
        $n(row, 'sc_new_entry_create').disabled = true;
        $n(row, 'sc_new_entry_lib').disabled = true;
        if (type==ACTOR)
            $n(row, 'sc_new_entry_default_lib').disabled = true;
        return;
    }
    buildOrgSel($n(row, 'sc_new_entry_lib'), rootOrg, 0, 'shortname');
    buildOrgSel($n(row, 'sc_new_entry_default_lib'), rootOrg, 0, 'shortname');
    $n(row, 'sc_new_entry_name').focus();
}


function scBuildNew() {
    var libSel = $('sc_owning_lib_selector');
    var typeSel = $('sc_type_selector');
    var type = getSelectorVal(typeSel);
    switch(type) {
        case ACTOR:
            unHideMe($('usr_summary_td1'));
            unHideMe($('usr_summary_td2'));
            unHideMe($('sip_tr'));
            unHideMe($('usr_freetext_td1'));
            unHideMe($('usr_freetext_td2'));
        break;
        case ASSET:
            hideMe($('usr_summary_td1'));
            hideMe($('usr_summary_td2'));
            hideMe($('sip_tr'));
            hideMe($('usr_freetext_td1'));
            hideMe($('usr_freetext_td2'));
        break;
    }
    var org_list = PERMS[type].create_stat_cat;
    if(org_list.length == 0) { /* no create perms */
        $('sc_new').disabled = true;
        libSel.disabled = true;
        return;
    }
    else {
        $('sc_new').disabled = false;
        libSel.disabled = false;
    }
    buildMergedOrgSel(libSel, org_list, 0, 'shortname');
    scPopSipFields($('sc_sip_field'),type);
}


function scNew() {

    var name = $('sc_new_name').value;
    var type = getSelectorVal($('sc_type_selector'));

    var visible = 0;
    var required = 0;
    var usr_summary = 0;
    var checkout_archive = 0;
    var usr_freetext = 0;
    if( $('sc_make_opac_visible').checked) visible = 1;
    if( $('sc_make_required').checked) required = 1;
    if( $('sc_make_usr_summary').checked) usr_summary = 1;
    if( $('sc_make_checkout_archive').checked) checkout_archive = 1;
    if( $('sc_make_usr_freetext').checked) usr_freetext = 1;

    var cat;
    if( type == ACTOR ) {
        cat = new actsc();
        cat.usr_summary( usr_summary );
        cat.allow_freetext( usr_freetext );
    }
    if( type == ASSET ) {
        cat = new asc();
    }
    var field = getSelectorVal($('sc_sip_field'));
    if(field.length == 2) cat.sip_field(field);
    else cat.sip_field(null);
    cat.sip_format($('sc_sip_format').value);

    cat.opac_visible(visible);
    cat.required( required );
    cat.name(name);
    cat.checkout_archive(checkout_archive);
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

    var required = cat.required();
    var reqcb = $n(row, 'sc_edit_required');
    reqcb.checked = isTrue(required); 

    scPopSipFields($n(row, 'sc_edit_sip_field'), type);
    $n(row, 'sc_edit_name').value = cat.name();
    setSelector($n(row, 'sc_edit_sip_field'), cat.sip_field());
    $n(row, 'sc_edit_sip_format').value = cat.sip_format();

    if(type == ACTOR) {
        var cb1 = $n(row, 'sc_edit_usr_summary');
        var cb2 = $n(row, 'sc_edit_usr_freetext');
        cb1.checked = isTrue(cat.usr_summary()); 
        cb2.checked = isTrue(cat.allow_freetext()); 
        unHideMe($n(row, 'sc_edit_usr_summary_td'));
        unHideMe($n(row, 'sc_edit_usr_freetext_td'));
    } else {
        hideMe($n(row, 'sc_edit_usr_summary_td'));
        hideMe($n(row, 'sc_edit_usr_freetext_td'));
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
        $n( $n(row, 'sc_edit_opac_visibility'), 
            'sc_edit_opac_visibility').checked = true;
    } 

    $n( row, 'sc_edit_checkout_archive' ).checked = isTrue(cat.checkout_archive());

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
        $n( $n(row, 'sc_edit_opac_visibility'), 'sc_edit_opac_visibility').checked;

    var newlib = cat.owner();
    if(selector) newlib = getSelectorVal( selector );

    if(!name) return false;

    var required = $n(row, 'sc_edit_required').checked;
    var usr_summary = $n(row, 'sc_edit_usr_summary').checked;
    var sip_field = getSelectorVal( $n(row, 'sc_edit_sip_field') );
    var usr_freetext = $n(row, 'sc_edit_usr_freetext').checked;

    cat.name( name );
    cat.owner( newlib );
    cat.entries(null);
    cat.opac_visible(0);
    cat.checkout_archive($n(row, 'sc_edit_checkout_archive').checked ? 1 : 0);
    cat.required( (required) ? 1 : 0 );
    if(sip_field.length == 2) cat.sip_field( sip_field );
    else cat.sip_field(null);
    cat.sip_format($n(row, 'sc_edit_sip_format').value);
    if( visible ) cat.opac_visible(1);
    if(type == ACTOR) {
        cat.usr_summary( (usr_summary) ? 1 : 0 );
        cat.allow_freetext( (usr_freetext) ? 1 : 0 );
    }

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
    
    var defaultentry = $n(row, 'sc_edit_entry_default_set');
    if(type == ACTOR) {
        unHideMe($n(row, 'sc_edit_entry_default'));
        if( cat.default_entries()[0] && cat.default_entries()[0].stat_cat_entry() == entry.id() )
            defaultentry.checked =  true;
    } else {
        hideMe($n(row, 'sc_edit_entry_default'));
    }

    var name = $n(row, 'sc_edit_entry_name');
    name.value = entry.value();
    name.value.replace(/\*$/, "");
    name.focus();
    name.select();

    $n(row,'sc_edit_entry_submit').onclick = 
        function(){
            if( scEditEntry(cat, entry, row, type ) )
                tbody.removeChild(row);
            };

    $n(row,'sc_edit_entry_cancel').onclick = function(){tbody.removeChild(row);};
    $n(row,'sc_edit_entry_delete').onclick = 
        function(){ scEntryDelete( cat, entry, type ); }

    var rootEditOrg = findReleventRootOrg(PERMS[type].update_stat_cat_entry, entry.owner());
    var rootDelOrg = findReleventRootOrg(PERMS[type].delete_stat_cat_entry, entry.owner());
    var org_list = PERMS[type].update_stat_cat_entry;

    if(!rootEditOrg || rootEditOrg.id() != entry.owner())
        $n(row,'sc_edit_submit').disabled = true;

    if(!rootDelOrg || rootDelOrg.id() != entry.owner())
        $n(row,'sc_edit_delete').disabled = true;

    if(type == ACTOR) {
        if(!rootEditOrg || org_list.length == 0) {
            $n(row, 'sc_edit_entry_default_lib').disabled = true;
            return;
        }
        buildOrgSel($n(row, 'sc_edit_entry_default_lib'), rootEditOrg, 0, 'shortname');
        if( cat.default_entries()[0] )
           setSelector( $n(row, 'sc_edit_entry_default_lib'), cat.default_entries()[0].owner() );
    }
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

function scEditEntry( cat, entry, row, type ) {
    var newvalue = $n(row, 'sc_edit_entry_name').value;
    var curvalue = entry.value();
    var didupdate = false;

    if( curvalue != newvalue ) {
        entry.value( newvalue );
        var req = new Request( 
            SC_ENTRY_UPDATE.replace(/TYPE/, type), session, entry );
        req.send(true);
        var res = req.result();
        if(checkILSEvent(res)) throw res;
        didupdate = true;
    }

    if(type == ACTOR) {
        didupdate = scEditEntryDefault( cat, entry, row );
    }

    if (didupdate) scShow(type);
}

function scEditEntryDefault( cat, entry, row ) {
    var newsetdefault = $n(row, 'sc_edit_entry_default_set').checked;
    var newownerdefault = getSelectorVal($n(row, 'sc_edit_entry_default_lib'));
    var cursetdefault = false;
    var curownerdefault = null;
    var default_entry = null;

    if( cat.default_entries && cat.default_entries()[0] && cat.default_entries()[0].stat_cat_entry() == entry.id() ) {
        cursetdefault = true;
        default_entry = cat.default_entries()[0];
        curownerdefault = default_entry.owner();
    }

    if( cursetdefault == newsetdefault &&
         (curownerdefault == newownerdefault || curownerdefault == null) ) {
        return;
    }

    if( cursetdefault == true &&
         newsetdefault == false ) {
        var req = new Request( 
            SC_ENTRY_DEFAULT_DELETE, session, default_entry.id() );
        req.send(true);
        var res = req.result();
        if(checkILSEvent(res)) throw res;
    }

    if( newsetdefault == true ) {
        var cat_id = cat.id();
        var entry_id = entry.id();
        default_entry = new actsced();
        default_entry.isnew(1);
        default_entry.stat_cat(cat_id);
        default_entry.stat_cat_entry(entry_id);
        default_entry.owner(newownerdefault);
        var req = new Request( 
            SC_ENTRY_DEFAULT_CREATE, session, default_entry );
        req.send(true);
        var res = req.result();
        if(checkILSEvent(res)) throw res;
    }

    return true;
}
