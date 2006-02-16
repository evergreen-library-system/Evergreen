
attachEvt("common", "run", myOPACInit );
attachEvt("common", "loggedIn", myOPACInit );

attachEvt('common','locationUpdated', myopacReload );

var fleshedUser = null;
var fleshedContainers = {};


function clearNodes( node, keepArray ) {
	if(!node) return;
	for( var n in keepArray ) node.removeChild(keepArray[n]);
	removeChildren(node);
	for( var n in keepArray ) node.appendChild(keepArray[n]);
}

function myOPACInit() {
	if(!(G.user && G.user.session)) initLogin();
	else myOPACChangePage( "summary" );
}

function myopacReload() {
	swapCanvas($('myopac_reloading'));
	//alert($('myopac_reloading').className);
	var a = {};
	a[PARAM_LOCATION] = getNewSearchLocation();
	a[PARAM_DEPTH] = getNewSearchDepth();
	goTo(buildOPACLink(a, true));
}


function myOPACChangePage( page ) {
	
	var s = $("myopac_summary_td");
	var c = $("myopac_checked_td");
	var f = $("myopac_fines_td");
	var h = $("myopac_holds_td");
	var p = $("myopac_prefs_td");
	var b = $('myopac_bookbag_td');

	var ss = $("myopac_summary_div");
	var cc = $("myopac_checked_div");
	var ff = $("myopac_fines_div");
	var hh = $("myopac_holds_div");
	var pp = $("myopac_prefs_div");
	var bb = $('myopac_bookbag_div');

	var cls = "myopac_link";
	var acls = "myopac_link_active";

	hideMe(ss);
	hideMe(cc); hideMe(ff);
	hideMe(hh); hideMe(pp);
	hideMe(bb);

	removeCSSClass(s, acls );
	removeCSSClass(c, acls );
	removeCSSClass(f, acls );
	removeCSSClass(h, acls );
	removeCSSClass(p, acls );
	removeCSSClass(b, acls );

	switch( page ) {

		case "summary": 
			unHideMe(ss);
			addCSSClass(s, acls );
			myOPACShowSummary();
			break;

		case "checked": 
			unHideMe(cc);
			addCSSClass(c, acls );
			myOPACShowChecked();
			break;

		case "holds": 
			unHideMe(hh);
			addCSSClass(h, acls );
			myOPACShowHolds();
			break;

		case "fines": 
			unHideMe(ff);
			addCSSClass(f, acls );
			myOPACShowFines();
			break;

		case "prefs": 
			unHideMe(pp);
			addCSSClass(p, acls );
			myOPACShowPrefs();
			break;

		case 'bookbag':
			unHideMe(bb);
			addCSSClass(b, acls);
			myOPACShowBookbags();
			break;
	}

	/*
	alert('Classes:\n' + s.className + '\n' + c.className + 
		'\n' + h.className + '\n' + f.className + '\n' + p.className);
		*/
}

function myOPACShowChecked() {
	if(checkedDrawn) return;
	var req = new Request(FETCH_CHECKED_OUT_SLIM, G.user.session);	
	req.callback(myOPACDrawCheckedOutSlim);
	req.send();
}


var checkedRowTemplate;
var circsCache = new Array();
var checkedDrawn = false;

function myOPACDrawCheckedOutSlim(r) {

	var checked			= r.getResultObject();
	var tbody			= $("myopac_checked_tbody");
	var loading			= $("myopac_checked_loading");
	var none				= $("myopac_checked_none");

	if(checkedDrawn) return;
	checkedDrawn = true;
	if(!checkedRowTemplate) 
		checkedRowTemplate = tbody.removeChild($("myopac_checked_row"));

	clearNodes( tbody, [ loading, none ] );

	hideMe(loading); /* remove all children and start over */
	if(!(checked && checked[0])) unHideMe(none);

	for( var idx in checked ) {

		var circ    = checked[idx]
		var row = checkedRowTemplate.cloneNode(true);
		row.id = 'myopac_checked_row_ ' + circ.id();

 		var due = circ.due_date();
      due = due.replace(/[0-9][0-9]:.*$/,"");

		var dlink = $n( row, "myopac_checked_due" );
		var rlink = $n( row, "myopac_checked_renewals" );
		var rnlink = $n( row, "myopac_checked_renew_link" );

		dlink.appendChild(text(due));
		rlink.appendChild(text(circ.renewal_remaining()));
		unHideMe(row);
		rnlink.setAttribute('href', 'javascript:myOPACRenewCirc("'+circ.id()+'");');
		circsCache.push(circ);

		tbody.appendChild(row);

		var req = new Request(FETCH_MODS_FROM_COPY, circ.target_copy() );
		req.request.circ = circ.id();
		req.request.copy = circ.target_copy();
		req.callback(myOPACDrawCheckedTitle);
		req.send();
	}
}

function myOPACDrawCheckedTitle(r) {
	var record = r.getResultObject();
	var circid = r.circ;

	if(!record || checkILSEvent(record)) {
		var req = new Request( FETCH_COPY, r.copy );
		req.request.circ = circid
		req.callback(myOPACDrawNonCatalogedItem);
		req.send();
		return;
	}

	var row = $('myopac_checked_row_ ' + circid);
	var tlink = $n( row, "myopac_checked_title_link" );
	var alink = $n( row, "myopac_checked_author_link" );
	buildTitleDetailLink(record, tlink);
	buildSearchLink(STYPE_AUTHOR, record.author(), alink);
}

function myOPACDrawNonCatalogedItem(r) {
	var copy = r.getResultObject();
	var circid = r.circ;

	var row = $('myopac_checked_row_ ' + circid);
	var tlink = $n( row, "myopac_checked_title_link" );
	var alink = $n( row, "myopac_checked_author_link" );

	tlink.parentNode.appendChild(text(copy.dummy_title()));
	alink.parentNode.appendChild(text(copy.dummy_author()));
}


function myOPACRenewCirc(circid) {

	var circ;
	for( var i = 0; i != circsCache.length; i++ ) 
		if(circsCache[i].id() == circid)
			circ = circsCache[i];

	var req = new Request(RENEW_CIRC, G.user.session, 
		{ patron : G.user.id(), copyid : circ.target_copy() } );
	req.send(true);
	var res = req.result();

	if(evt = checkILSEvent(res)) {
		if( evt != 0 ) {
			alert(evt);
			alertILSEvent(evt);
			return;
		}
	}

	alert($('myopac_renew_success').innerHTML);	
	checkedDrawn = false;
	myOPACShowChecked();
}



function myOPACShowHolds() {
	var req = new Request(FETCH_HOLDS, G.user.session, G.user.id());	
	req.callback(myOPACDrawHolds);
	req.send();
}

var holdsTemplateRowOrig;
var holdsTemplateRow;
function myOPACDrawHolds(r) {

	var tbody = $("myopac_holds_tbody");
	if(holdsTemplateRow) return;
	if(holdsTemplateRowOrig) {
		holdsTemplateRow = holdsTemplateRowOrig;
		removeChildren(tbody);
	} else {
		holdsTemplateRow = tbody.removeChild($("myopac_holds_row"));
		holdsTemplateRowOrig = holdsTemplateRow;
	}

	hideMe($('myopac_holds_loading'));

	var holds = r.getResultObject();

	if(!holds || holds.length < 1) unHideMe($('myopac_holds_none'));
	for( var i = 0; i != holds.length; i++ ) {

		var h = holds[i];
		var row = holdsTemplateRow.cloneNode(true);
		row.id = "myopac_holds_row_" + h.id() + '_' + h.target();

		var formats = (h.holdable_formats()) ? h.holdable_formats() : null;
		var form = $n(row, "myopac_holds_formats");
		form.id = "myopac_holds_form_" + h.id() + '_' + h.target();
		if(formats) form.appendChild(text(formats));

		$n(row, "myopac_holds_location").
			appendChild(text(findOrgUnit(h.pickup_lib()).name()));
		$n(row, "myopac_holds_email_link").
			appendChild(text(h.email_notify()));
		$n(row, "myopac_holds_phone_link").
			appendChild(text(h.phone_notify()));
		tbody.appendChild(row);

		$n(row,'myopac_holds_cancel_link').setAttribute(
			'href','javascript:myOPACCancelHold("'+ h.id()+'");'); 
		unHideMe(row);

		myOPACDrawHoldTitle(h);
	}
}

function myOPACCancelHold(holdid) {
	if( confirm($('myopac_holds_cancel_verify').innerHTML) ) {
		holdsCancel(holdid);
		holdsTemplateRow = null
		myOPACShowHolds();
	}
}



function myOPACDrawHoldTitle(hold) {
	var method;
	if(hold.hold_type() == "M") method = FETCH_MRMODS;
	if(hold.hold_type() == "T") method = FETCH_RMODS;
	var req = new Request(method, hold.target());
	req.callback(myOPACFleshHoldTitle);
	req.request.hold = hold.id();
	req.send();
}

function myOPACFleshHoldTitle(r) {

	var record = r.getResultObject();
	var row = $("myopac_holds_row_" + r.hold + '_' + record.doc_id());
	var title_link = $n(row, "myopac_holds_title_link");
	var author_link = $n(row, "myopac_holds_author_link");

	buildTitleDetailLink(record, title_link);
	buildSearchLink(STYPE_AUTHOR, record.author(), author_link);

	var form = $("myopac_holds_form_" + r.hold + '_' + record.doc_id());

	if(form) {
		var img = elem("img");
		img.setAttribute("src", 
			buildImageLink('tor/' + record.types_of_resource()[0] + ".jpg"));
		addCSSClass(img, "myopac_form_pic");
		form.appendChild(img);
	}
}

var finesShown = false;
function myOPACShowFines() {
	if(finesShown) return; finesShown = true;
	var req = new Request(FETCH_FINES_SUMMARY, G.user.session, G.user.id() );
	req.callback(_myOPACShowFines);
	req.send();
}

function _myOPACShowFines(r) {
	hideMe($('myopac_fines_summary_loading'));
	unHideMe($('myopac_fines_summary_row'));

	var summary = r.getResultObject();
	var total	= "0.00"; /* localization? */
	var paid		= "0.00";
	var balance = "0.00";
	if( instanceOf(summary,mous) ) {

		total		= _finesFormatNumber(summary.total_owed());
		paid		= _finesFormatNumber(summary.total_paid());
		balance	= _finesFormatNumber(summary.balance_owed());

		var req = new Request(FETCH_TRANSACTIONS, G.user.session, G.user.id() );
		req.callback(myOPACShowTransactions);
		req.send();
	}

	$('myopac_fines_summary_total').appendChild(text(total));
	$('myopac_fines_summary_paid').appendChild(text(paid));
	$('myopac_fines_summary_balance').appendChild(text(balance));
}

function _finesFormatNumber(num) {
	if(isNull(num)) num = 0;
	num = num + "";
	if(num.length < 2 || !num.match(/\./)) num += ".00";
	if(num.match(/\./) && num.charAt(num.length-2) == '.') num += "0";
	return num;
}          

function _trimTime(time) { if(!time) return ""; return time.replace(/\ .*/,""); }

function _trimSeconds(time) { if(!time) return ""; return time.replace(/\..*/,""); }


function myOPACShowTransactions(r) {

	if(myopacGenericTransTemplate || myopacCircTransTemplate) return;

	var transactions = r.getResultObject();

	for( var idx in transactions ) {

		var trans	= transactions[idx].transaction;
		var record	= transactions[idx].record;
		var circ		= transactions[idx].circ;

		if(trans.xact_type() == 'circulation') 
			myOPACShowCircTransaction(trans, record, circ);

		else if(trans.xact_type() == 'grocery' ) 
			myopacShowGenericTransaction( trans );
	}
}

var myopacGenericTransTemplate;
function myopacShowGenericTransaction( trans ) {
	var tbody = $('myopac_trans_tbody');

	if(!myopacGenericTransTemplate) {
		myopacGenericTransTemplate = 
			tbody.removeChild($('myopac_trans_row'));
		removeChildren(tbody);
	}

	var row = myopacGenericTransTemplate.cloneNode(true);

	$n(row,'myopac_trans_start').appendChild(
			text(_trimSeconds(trans.xact_start())));

	$n(row,'myopac_trans_last_payment').appendChild(
			text(_trimSeconds(trans.last_payment_ts())));

	$n(row,'myopac_trans_init_amount').appendChild(
			text(_finesFormatNumber(trans.total_owed())));

	$n(row,'myopac_trans_total_paid').appendChild(
			text(_finesFormatNumber(trans.total_paid())));

	$n(row,'myopac_trans_balance').appendChild(
			text(_finesFormatNumber(trans.balance_owed())));

	var req = new Request(FETCH_MONEY_BILLING, G.user.session, trans.id());
	req.send(true);
	var bills = req.result();
	if(bills && bills[0])
		$n(row,'myopac_trans_bill_type').appendChild(
				text(bills[0].billing_type()));

	tbody.appendChild(row);
	unHideMe($('myopac_trans_table'));
}



/* draws a circulation transaction summary */
var myopacCircTransTemplate;
function myOPACShowCircTransaction(trans, record, circ) {
	var tbody = $('myopac_circ_trans_tbody');

	if(!myopacCircTransTemplate) {
		myopacCircTransTemplate = tbody.removeChild($('myopac_circ_trans_row'));
		removeChildren(tbody);
	}

	var row = myopacCircTransTemplate.cloneNode(true);

	buildTitleDetailLink(record, $n(row,'myopac_circ_trans_title'));

	$n(row,'myopac_circ_trans_author').appendChild(text(
		normalize(truncate(record.author(), 65))));

	$n(row,'myopac_circ_trans_start').
		appendChild(text(_trimTime(trans.xact_start())));

   var due = _trimTime(circ.due_date());
	var checkin = _trimTime(circ.stop_fines_time());

	$n(row,'myopac_circ_trans_due').appendChild(text(due))
	$n(row,'myopac_circ_trans_finished').appendChild(text(checkin))

	$n(row,'myopac_circ_trans_balance').
		appendChild(text(_finesFormatNumber(trans.balance_owed())));

	tbody.appendChild(row);
	unHideMe($('myopac_circ_trans_table'));
}


function myOPACSavePrefs() {
	G.user.prefs[PREF_HITS_PER] = getSelectorVal($('prefs_hits_per'));
	if(commitUserPrefs())
		alert($('prefs_update_success').innerHTML);
	else alert($('prefs_update_failure').innerHTML);
}


function myOPACShowPrefs() {
	grabUserPrefs();
	myOPACShowHitsPer();
	hideMe($('myopac_prefs_loading'));
	unHideMe($('myopac_prefs_row'));
}

function myOPACShowHitsPer() {
	var hits = 10;
	if(G.user.prefs[PREF_HITS_PER])
		hits = G.user.prefs[PREF_HITS_PER];
	var hitsSel = $('prefs_hits_per');
	setSelector(hitsSel, hits);
}

var userShown = false;
function myOPACShowSummary() {
	if(userShown) return; userShown = true;
	var req = new Request(FETCH_FLESHED_USER,G.user.session, G.user.id());
	req.callback(_myOPACSummaryShowUer);
	req.send();
}

var addrRowTemplate;
function _myOPACSummaryShowUer(r) {

	var user = r.getResultObject();
	fleshedUser = user;

	appendClear($('myopac_summary_first'),text(user.first_given_name()));
	appendClear($('myopac_summary_middle'),text(user.second_given_name()));
	appendClear($('myopac_summary_dayphone'),text(user.day_phone()));
	appendClear($('myopac_summary_eveningphone'),text(user.evening_phone()));
	appendClear($('myopac_summary_otherphone'),text(user.other_phone()));
	appendClear($('myopac_summary_last'),text(user.family_name()));
	appendClear($('myopac_summary_username'),text(user.usrname()));
	appendClear($('myopac_summary_email'),text(user.email()));
	appendClear($('myopac_summary_barcode'),text(user.card().barcode()));
	appendClear($('myopac_summary_ident1'),text(user.ident_value()));
	appendClear($('myopac_summary_ident2'),text(user.ident_value2()));
	appendClear($('myopac_summary_homelib'),text(findOrgUnit(user.home_ou()).name()));
	appendClear($('myopac_summary_create_date'),text(user.create_date()));

	var tbody = $('myopac_addr_tbody');
	var template;

	if(addrRowTemplate) { 
		template = addrRowTemplate;
	} else {
		template = tbody.removeChild($('myopac_addr_row'));
		addrRowTemplate = template;
	}
	removeChildren(tbody);

	for( var a in user.addresses() ) {
		var row = template.cloneNode(true);
		myOPACDrawAddr(row, user.addresses()[a]);
		tbody.appendChild(row);
	}
}

function myOPACDrawAddr(row, addr) {

	appendClear($n(row, 'myopac_addr_type'),text(addr.address_type()));
	var street = (addr.street2()) ? addr.street1() + ", " + addr.street2() : addr.street1();
	appendClear($n(row, 'myopac_addr_street'),text(street));
	appendClear($n(row, 'myopac_addr_city'),text(addr.city()));
	appendClear($n(row, 'myopac_addr_county'),text(addr.county()));
	appendClear($n(row, 'myopac_addr_state'),text(addr.state()));
	appendClear($n(row, 'myopac_addr_zip'),text(addr.post_code()));
}


function myOPACUpdateUsername() {
	var username = $('myopac_new_username').value;
	if(username == null || username == "") {
		alert($('myopac_username_error').innerHTML);
		return;
	}
	var req = new Request(UPDATE_USERNAME, G.user.session, username );
	req.send(true);
	if(req.result()) {

		var evt;
		if(evt = checkILSEvent(req.result())) {
			alertILSEvent(evt);
			return;
		}

		G.user.usrname(username);
		hideMe($('myopac_update_username_row'));
		userShown = false;
		myOPACShowSummary();
		return;
	}

	alert($('myopac_username_failure').innerHTML);
}

function myOPACUpdateEmail() {
	var email = $('myopac_new_email').value;
	if(email == null || email == "") {
		alert($('myopac_email_error').innerHTML);
		return;
	}

	var req = new Request(UPDATE_EMAIL, G.user.session, email );
	req.send(true);
	if(req.result()) {
		G.user.usrname(email);
		hideMe($('myopac_update_email_row'));
		userShown = false;
		myOPACShowSummary();
		return;
	}

	alert($('myopac_email_failure').innerHTML);
}


function myOPACUpdatePassword() {
	var curpassword = $('myopac_current_password').value;
	var password = $('myopac_new_password').value;
	var password2 = $('myopac_new_password2').value;

	if(	curpassword == null || curpassword == "" || 
			password == null || password == "" || 
			password2 == null || password2 == "" || password != password2 ) {
		alert($('myopac_password_error').innerHTML);
		return;
	}

	var req = new Request(UPDATE_PASSWORD, G.user.session, password, curpassword );
	req.send(true);
	if(req.result()) {
		G.user.usrname(password);
		hideMe($('myopac_update_password_row'));
		userShown = false;
		myOPACShowSummary();
		return;
	}

	alert($('myopac_password_failure').innerHTML);
}




var containerTemplate;
function myOPACShowBookbags(force) {

	var tbody =$('myopac_bookbag_tbody') ;

	if(!containerTemplate) 
		containerTemplate = tbody.removeChild($('myopac_bookbag_tr'));
	else if(!force) return;

	removeChildren(tbody);

	var containers = containerFetchAll();

	var found = false;
	for( var i in containers ) {
		found = true;
		var cont = containers[i];
		var row = containerTemplate.cloneNode(true);
		row.id = 'myopac_bookbag_row_' + cont.id();
		var link = $n(row, 'myopac_expand_bookbag');
		var dlink = $n(row, 'myopac_container_delete');
		link.appendChild( text(cont.name()) );
		link.setAttribute('href', 
			'javascript:myOPACExpandBookbag("' + cont.id() + '","' + cont.name() + '");');
		myOPACFetchBBItems( cont.id(), row );
		dlink.setAttribute('href', 'javascript:myOPACDeleteBookbag("'+cont.id()+'");');

		if( cont.pub() ) {
			unHideMe($n(row, 'myopac_bb_published_yes'));
			var link = $n(row, 'myopac_bb_published_view');
			link.setAttribute('href', buildExtrasLink( 'bbags.xml?bb='+cont.id(), false));  
			link.setAttribute('target', '_blank' );
			unHideMe(link);

		} else { 
			unHideMe($n(row, 'myopac_bb_published_no')); 
		}

		tbody.appendChild(row);	
	}

	if(!found) unHideMe($('myopac_bookbags_none'));
	else unHideMe($('myopac_bookbag_table'));	
}

function myOPACDeleteBookbag(id) {
	if( confirm( $('myopac_delete_bookbag_warn').innerHTML ) ) {
		var result = containerDelete(id);
		var code = checkILSEvent(result);
		if(code) { alertILSEvent(code); return; }
		hideMe($('myopac_bookbag_items_table'));
		hideMe($('myopac_bookbag_items_name'));
		hideMe($('myopac_bookbag_no_items'));
		myOPACShowBookbags(true);
	}
}

function myOPACFetchBBItems( id, row, block ) {
	if(!block) {
		containerFlesh( id, _myOPACSetBBItems, { row: row }  );
	} else {
		var cont = containerFlesh(id);
		myOPACSetBBItems( cont, row );
	}
}

function _myOPACSetBBItems(r) { myOPACSetBBItems( r.getResultObject(), r.args.row ); }

function myOPACSetBBItems( container, row ) {
	fleshedContainers[container.id()] = container;
	var node = $n(row, 'myopac_bookbag_item_count');
	removeChildren(node);
	node.appendChild( text(container.items().length) );
}

var BBItemsRow;
function myOPACExpandBookbag( id, name ) {
	
	var tbody = $('myopac_bookbag_items_tbody');
	if(!BBItemsRow) BBItemsRow = tbody.removeChild($('myopac_bookbag_items_row'));
	removeChildren(tbody);
	removeChildren($('myopac_bookbag_items_name'));

	$('myopac_bookbag_items_name').appendChild(text(name));

	if( fleshedContainers[id] ) {
		var len = fleshedContainers[id].items().length;

		if( len == 0 ) {
			unHideMe($('myopac_bookbag_no_items'));
			hideMe($('myopac_bookbag_items_table'));
			return;
		}

		hideMe($('myopac_bookbag_no_items'));
		unHideMe($('myopac_bookbag_items_table'));

		for( var i = 0; i != len; i++ ) {
			var row = BBItemsRow.cloneNode(true);
			found = true;

			var item = fleshedContainers[id].items()[i];
			var tlink = $n(row,'myopac_bookbag_items_title');
			var alink = $n(row,'myopac_bookbag_items_author');

			var req = new Request( FETCH_RMODS, item.target_biblio_record_entry() );
			req.request.tlink = tlink;
			req.request.alink = alink;
			req.callback(myOPACShowBBItem);
			req.send();

			var clink = $n(row, 'myopac_bookbag_items_remove');
			clink.setAttribute('href', 'javascript:myOPACRemoveBBItem("'+item.id()+'","'+id+'","'+name+'");');

			tbody.appendChild(row);
		}
	}
}

function myOPACRemoveBBItem( id, containerid, container_name ) {
	containerRemoveItem( id );
	myOPACFetchBBItems( containerid, $('myopac_bookbag_row_' + containerid), true);
	myOPACExpandBookbag( containerid, container_name );
}

function myOPACShowBBItem(r) {
	var record = r.getResultObject();
	buildTitleDetailLink(record, r.tlink);
	buildSearchLink(STYPE_AUTHOR, record.author(), r.alink);
}

function myOPACCreateBookbag() {
	var name = $('myopac_bookbag_new_name').value;	
	if(!name) return;
	var result = containerCreate( name, $('bb_public_yes').checked );
	var code = checkILSEvent(result);
	if(code) { alertILSEvent(code); return; }
	myOPACShowBookbags(true);
}


