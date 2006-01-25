var SC_FETCH_ALL		= 'open-ils.circ:open-ils.circ.stat_cat.TYPE.retrieve.all';
var SC_CREATE			= 'open-ils.circ:open-ils.circ.stat_cat.TYPE.create';
var SC_UPDATE			= 'open-ils.circ:open-ils.circ.stat_cat.TYPE.update';
var SC_DELETE			= 'open-ils.circ:open-ils.circ.stat_cat.TYPE.delete';
var SC_ENTRY_CREATE	= 'open-ils.circ:open-ils.circ.stat_cat.TYPE.entry.create';
var SC_ENTRY_UPDATE	= 'open-ils.circ:open-ils.circ.stat_cat.TYPE.entry.update';
var SC_ENTRY_DELETE	= 'open-ils.circ:open-ils.circ.stat_cat.TYPE.entry.delete';

var ACTOR				= 'actor';
var ASSET				= 'asset';
var session				= null;
var user					= null;

var scCache				= {};
var PERMS				= {};
PERMS[ACTOR]			= {};
PERMS[ASSET]			= {};

var currentlyVisible;
var opacVisible		= false;
var cgi;


function scEditorInit() {
	cgi = new CGI();
	session = cgi.param('ses');
	if(!session) throw "User session is not defined";
	user = fetchUser(session);
	setTimeout( function() { scFetchPerms(); scGo(); }, 20 );
}

function scGo() {

	var show = cgi.param('show');
	if(!show) show = ASSET;
	scShow(show);
	scBuildNew();
	$('sc_user').appendChild(text(user.usrname()));
}

function scFetchPerms() {

	var orgs = fetchHighestPermOrgs( session, user.id(), 
		[	'CREATE_PATRON_STAT_CAT',
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
			'DELETE_COPY_STAT_CAT_ENTRY' ] );

	PERMS[ACTOR].create_stat_cat = orgs[0];
	PERMS[ACTOR].update_stat_cat = orgs[1];
	PERMS[ACTOR].delete_stat_cat = orgs[2];
	PERMS[ACTOR].create_stat_cat_entry = orgs[3];
	PERMS[ACTOR].update_stat_cat_entry = orgs[4];
	PERMS[ACTOR].delete_stat_cat_entry = orgs[5];

	PERMS[ASSET].create_stat_cat = orgs[6];
	PERMS[ASSET].update_stat_cat = orgs[7];
	PERMS[ASSET].delete_stat_cat = orgs[8];
	PERMS[ASSET].create_stat_cat_entry =  orgs[9];
	PERMS[ASSET].update_stat_cat_entry =  orgs[10];
	PERMS[ASSET].delete_stat_cat_entry =  orgs[11];
}

function scFetchPerm(perm) {
	var req = new RemoteRequest(
		'open-ils.actor',
		'open-ils.actor.user.perm.highest_org', session, user.id(), perm );
	req.send(true);
	return req.getResultObject();
	PERMS.create_stat = req.getResultObjecdt();
}


function scFetchAll( session, type, orgid, callback, args ) {
	var req = new Request( 
		SC_FETCH_ALL.replace(/TYPE/, type) , session, orgid );
	req.send(true);
	return req.result();
}

function scShow(type) { 

	currentlyVisible = type;

	if( type == ASSET ) {
		addCSSClass($('sc_show_copy'), 'has_color');
		removeCSSClass($('sc_show_actor'), 'has_color');

	} else if( type == ACTOR ) {
		addCSSClass($('sc_show_actor'), 'has_color');
		removeCSSClass($('sc_show_copy'), 'has_color');
	}

	scCache[type] = scFetchAll( session, type, user.home_ou() );  
	scDraw( type, scCache[type] );
}

var scRow; var scCounter;
function scDraw( type, cats ) {

	hideMe($('loading'));
	if(!cats || cats.length == 0) return unHideMe($('sc_none'));
	var tbody = $('sc_tbody');

	if(!scRow) scRow = tbody.removeChild($('sc_tr'));
	removeChildren(tbody);
	unHideMe($('sc_table'));

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

	if( cat.opac_visible() ) unHideMe($n(row, 'sc_opac_visible'));
	else unHideMe($n(row, 'sc_opac_invisible'));

	tbody.appendChild(row);
	scEntryCounter = 0;

	cat.entries().sort(  /* sort the entries by value */
		function( a, b ) { 
			if( a.value().toLowerCase() > b.value().toLowerCase()) return 1;
			if( a.value().toLowerCase() < b.value().toLowerCase()) return -1;
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
	entry.owner(user.home_ou());
	entry.value(value);

	var req = new Request( SC_ENTRY_CREATE.replace(/TYPE/, type), session, entry );
	req.send(true);
	var res = req.result();
	if(checkILSEvent(res)) throw res;
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

	var c_org = PERMS[type].create_stat_cat_entry;
	var max_c_depth = (c_org != null) ? findOrgDepth(c_org) : -1;
	
	if( max_c_depth == -1 ) {
		$n(row, 'sc_new_entry_create').disabled = true;
		$n(row, 'sc_new_entry_lib').disabled = true;
		return;
	}

	var org = findOrgUnit(cat.owner());
	var depth = findOrgDepth(org);

	if( depth < max_c_depth ) {
		depth = max_c_depth;
		org = findOrgUnit(c_org);
	}
	
	buildOrgSel( $n(row, 'sc_new_entry_lib'), org, depth );
	$n(row, 'sc_new_entry_name').focus();
}


function scBuildNew() {

	var c_org = PERMS[ASSET].create_stat_cat;
	var max_c_depth = (c_org != null) ? findOrgDepth(c_org) : -1;

	var ac_org = PERMS[ACTOR].create_stat_cat;
	var max_ac_depth = (ac_org != null) ? findOrgDepth(ac_org) : -1;

	var depth = max_c_depth;
	var org = c_org;

	var selector = $('sc_owning_lib_selector');

	if( depth == -1 ) {
		depth = max_ac_depth;
		org = ac_org;
		if( depth == -1 ) {
			$('sc_new').disabled = true;
			$('sc_type_selector').disabled = true;
			selector.disabled = true;
			return;
		}
	}

	org = findOrgUnit( org );
	buildOrgSel( selector, org, depth );
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

	scShow(type);
}

function scEdit( tbody, type, cat ) {

	_cleanTbody(tbody, 'edit');
	var row = $('sc_edit_row').cloneNode(true);
	row.setAttribute('edit', '1');

	var r = $('sc_tr_' + cat.id());
	if(r.nextSibling) { tbody.insertBefore( row, r.nextSibling ); }
	else{ tbody.appendChild(row); }

	$n(row, 'sc_edit_name').value = cat.name();

	var name = $n(row, 'sc_edit_cancel');
	name.onclick = function() { tbody.removeChild(row); };

	var show = $n(row, 'sc_edit_show_owning_lib');
	
	var myorg = findOrgUnit(user.home_ou());
	var ownerorg = findOrgUnit(cat.owner());
	show.appendChild(text(ownerorg.name()));

	var selector = null;
	if( myorg.children() && myorg.children().length > 0 ) {
		selector = $n(row, 'sc_edit_owning_lib');
		buildOrgSel( selector, myorg, findOrgDepth(myorg) );
		setSelector( selector, cat.owner() );
		unHideMe(selector);

	} else { unHideMe(show); }

	name.focus();
	name.select();

	if( cat.opac_visible() ) {
		$n( $n(row, 'sc_edit_opac_vis'), 
			'sc_edit_opac_visibility').checked = true;
	}
	else 
		$n( $n(row, 'sc_edit_opac_invis'), 
			'sc_edit_opac_visibility').checked = true;

	$n(row, 'sc_edit_submit').onclick = 
		function() { scEditGo( type, cat, row, selector ); };

	$n(row, 'sc_edit_delete').onclick = 
		function(){ scDelete(type, cat.id()); };

	var o_depth = findOrgDepth(findOrgUnit(cat.owner()));
	/*var m_depth = findOrgDepth(findOrgUnit(user.home_ou()));*/
	var e_org = PERMS[type].update_stat_cat;
	var d_org = PERMS[type].delete_stat_cat;
	var max_e_depth = (e_org != null) ? findOrgDepth(e_org) : -1;
	var max_d_depth = (d_org != null) ? findOrgDepth(d_org) : -1;

	if( max_e_depth == -1 || o_depth < max_e_depth )
		$n(row,'sc_edit_submit').disabled = true;

	if( max_d_depth == -1 || o_depth < max_d_depth )
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
	if( cat.opac_visible() ) isvisible = true;

	if( (name == cat.name()) && (visible == isvisible) 
		&& (newlib == cat.owner()) ) { return true; }

	cat.name( name );
	cat.owner( newlib );
	cat.entries(null);
	cat.opac_visible(0);
	if( visible ) cat.opac_visible(1);

	var req = new Request( SC_UPDATE.replace(/TYPE/,type), session, cat );
	req.send(true);
	var res = req.result();
	if(checkILSEvent(res)) throw res;
	scShow(type);

	return true;
}

function scUpdateEntry( cat, entry, tbody, type ) {
	_cleanTbody(tbody, 'edit');
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

	var o_depth = findOrgDepth( findOrgUnit(entry.owner()) );
	/*var m_depth = findOrgDepth(findOrgUnit(user.home_ou()));*/

	var e_org = PERMS[type].update_stat_cat_entry;
	var d_org = PERMS[type].delete_stat_cat_entry;
	var max_e_depth = (e_org != null) ? findOrgDepth(e_org) : -1;
	var max_d_depth = (d_org != null) ? findOrgDepth(d_org) : -1;

	if( max_e_depth == -1 || o_depth < max_e_depth )
		$n(row,'sc_edit_entry_name_submit').disabled = true;

	if( max_d_depth == -1 || o_depth < max_d_depth )
		$n(row,'sc_edit_entry_delete').disabled = true;
}

function scEntryDelete( cat, entry, type ) {
	if(!confirm($('sc_entry_delete_confirm').innerHTML)) return;
	var req = new Request( SC_ENTRY_DELETE.replace(/TYPE/,type), session, entry.id() );
	req.send(true);
	var res = req.result();
	if(checkILSEvent(res)) throw res;
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

