var SC_FETCH_ALL		= 'open-ils.circ:open-ils.circ.stat_cat.TYPE.retrieve.all';
var SC_CREATE			= 'open-ils.circ:open-ils.circ.stat_cat.TYPE.create';
var SC_UPDATE			= 'open-ils.circ:open-ils.circ.stat_cat.TYPE.update';
var SC_DELETE			= 'open-ils.circ:open-ils.circ.stat_cat.TYPE.delete';
var SC_ENTRY_CREATE	= 'open-ils.circ:open-ils.circ.stat_cat.TYPE.entry.create';
var SC_ENTRY_UPDATE	= 'open-ils.circ:open-ils.circ.stat_cat.TYPE.entry.update';
var SC_ENTRY_DELETE	= 'open-ils.circ:open-ils.circ.stat_cat.TYPE.entry.delete';
/*
var SC_MAP_CREATE		= 'open-ils.circ:open-ils.circ.stat_cat.TYPE.WHAT_map.create';
var SC_MAP_UPDATE		= 'open-ils.circ:open-ils.circ.stat_cat.TYPE.WHAT_map.update';
*/

var ACTOR				= 'actor';
var ASSET				= 'asset';
var session				= null;
var user					= null;

var scCache				= {};
var currentlyVisible;
var opacVisible		= false;


function scEditorInit() {
	var cgi = new CGI();
	session = cgi.param('ses');
	if(!session) throw "User session is not defined";
	var show = cgi.param('show');
	user = fetchUser(session);
	if(show == ACTOR) scShow(ACTOR);
	else scShow(ASSET);
	scBuildNew();
	$('sc_user').appendChild(text(user.usrname()));
}

function _cleanTbody(tbody) {
	for( var c  = 0; c < tbody.childNodes.length; c++ ) {
		var child = tbody.childNodes[c];
		if(child && child.getAttribute('edit')) tbody.removeChild(child); 
	}
}

function fetchUser(session) {
	var request = new Request(FETCH_SESSION, session, 1 );
	request.send(true);
	var user = request.result();
	if(checkILSEvent(user)) throw user;
	return user;
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
	/*$n(row, 'sc_delete').onclick = function(){ scDelete(type, cat.id()); };*/
	$n(row, 'sc_owning_lib').appendChild( text( findOrgUnit(cat.owner()).name() ));

	if( cat.opac_visible() ) unHideMe($n(row, 'sc_opac_visible'));
	else unHideMe($n(row, 'sc_opac_invisible'));

	tbody.appendChild(row);
	scEntryCounter = 0;

	cat.entries().sort(  /* sort the entries by value */
		function( a, b ) { 
			if( a.value() > b.value()) return 1;
			if( a.value() < b.value()) return -1;
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
	_cleanTbody(tbody);
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

	var org = findOrgUnit(cat.owner());
	var myorg = findOrgUnit(user.home_ou());
	var depth = findOrgDepth(org);
	var mydepth = findOrgDepth(myorg);

	if( depth < mydepth ) {
		depth = mydepth;
		org = myorg;
	}


	_scBuildOrgSelector( $n(row, 'sc_new_entry_lib'), org, findOrgDepth(org));
	$n(row, 'sc_new_entry_name').focus();
}


function scBuildNew() {
	var selector = $('sc_owning_lib_selector');
	var org = findOrgUnit( user.home_ou() );
	var offset = findOrgDepth(org);
	_scBuildOrgSelector( selector, org, offset);
}

function _scBuildOrgSelector(selector, org, offset) {
	insertSelectorVal( selector, -1, 
		org.name(), org.id(), null, findOrgDepth(org) - offset );
	for( var c in org.children() )
		_scBuildOrgSelector( selector, org.children()[c], offset);
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

	_cleanTbody(tbody);
	var row = $('sc_edit_row').cloneNode(true);
	row.setAttribute('edit', '1');

	var r = $('sc_tr_' + cat.id());
	if(r.nextSibling) tbody.insertBefore( row, r.nextSibling );
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
		_scBuildOrgSelector( selector, myorg, findOrgDepth(myorg) );
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
		function() { 
			if( scEditGo( type, cat, row, selector ) ) 
				tbody.removeChild(row); };

	$n(row, 'sc_edit_delete').onclick = function(){ scDelete(type, cat.id()); };

	var o_depth = findOrgDepth(findOrgUnit(cat.owner()));
	var m_depth = findOrgDepth(findOrgUnit(user.home_ou()));

	if(  o_depth < m_depth ) {
		$n(row,'sc_edit_submit').disabled = true;
		$n(row,'sc_edit_delete').disabled = true;
	}

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
	_cleanTbody(tbody);
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
	var m_depth = findOrgDepth(findOrgUnit(user.home_ou()));

	if(  o_depth < m_depth ) {
		$n(row,'sc_edit_entry_name_submit').disabled = true;
		$n(row,'sc_edit_entry_delete').disabled = true;
	}
		
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

