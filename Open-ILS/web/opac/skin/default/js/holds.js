
var currentHoldRecord;
var currentHoldRecordObj;
var holdsOrgSelectorBuilt = false;
var holdRecipient;
var holdRequestor
var holdEmail;
var holdPhone;
var holdEditHold;
var holdEditCallback;


function holdsHandleStaff() {
	swapCanvas($('xulholds_box'));
	$('xul_recipient_barcode').focus();
	$('xul_recipient_barcode').onkeypress = function(evt) 
		{if(userPressedEnter(evt)) { _holdsHandleStaff(); } };
	$('xul_recipient_barcode_submit').onclick = _holdsHandleStaff;
	$('xul_recipient_me').onclick = _holdsHandleStaffMe;
}

function _holdsHandleStaffMe() {
	holdRecipient = G.user;
	holdsDrawWindow( currentHoldRecord, null );
}

function _holdsHandleStaff() {
	var barcode = $('xul_recipient_barcode').value;
	var user = grabUserByBarcode( G.user.session, barcode );
	var code = checkILSEvent(user);
	if(code || !user) {
		alertILSEvent(code, barcode);
		showCanvas();
		return;
	}
	holdRecipient = user;
	holdsDrawWindow( currentHoldRecord, null );
}

function holdsDrawWindow(recid, type, edithold, done_callback) {

	if(recid == null) {
		recid = currentHoldRecord;
		if(recid == null) return;
	}	
	currentHoldRecord = recid;
	holdEditHold = edithold;
	holdEditCallback = done_callback;
	
	if(isXUL() && holdRecipient == null ) { 
		holdsHandleStaff();
		return;
	}

	if( holdRecipient == null ) holdRecipient = G.user;
	if( holdRequestor == null ) holdRequestor = G.user;

	if(!(holdRequestor && holdRequestor.session)) {

		detachAllEvt('common','locationChanged');
		attachEvt('common','loggedIn', holdsDrawWindow)
		initLogin();
		return;
	}


	swapCanvas($('check_holds_box'));

	if(edithold) {
		hideMe($('holds_submit'));
		unHideMe($('holds_update'));
		_holdsDrawWindow(recid, type);
		_holdsUpdateEditHold(edithold);

	} else {
		setTimeout( function() { holdsCheckPossibility(recid, type); }, 10 );
	}
}

function _holdsUpdateEditHold(hold) {

	if( hold.capture_time() )
		$('holds_org_selector').disabled = true;
	else
		setSelector($('holds_org_selector'), hold.pickup_lib());

	$('holds_submit').onclick = holdsEditHold;
	$('holds_update').onclick = holdsEditHold;


	if(hold.phone_notify()) {
		$('holds_enable_phone').checked = true;
		$('holds_phone').value = hold.phone_notify();

	} else {
		$('holds_phone').disabled = true;
		$('holds_enable_phone').checked = false;
	}

	if(hold.email_notify()) {
		$('holds_enable_email').checked = true;

	} else {
		$('holds_enable_email').checked = false;
	}
}

function holdsEditHold() {
	var hold = holdsBuildHoldFromWindow();
	//hold.id( holdEditHold.id() );
	holdsUpdate(hold);
	showCanvas();
	if(holdEditCallback) holdEditCallback(hold);
}


function _holdsDrawWindow(recid, type) {

	swapCanvas($('holds_box'));

	var rec = findRecord( recid, type );
	currentHoldsRecordObj = rec;

	if(!holdsOrgSelectorBuilt) {
		holdsBuildOrgSelector(null,0);
		holdsOrgSelectorBuilt = true;
	}

	if(isXUL()) {
		var dsel = $('holds_depth_selector');
		unHideMe($('holds_depth_selector_row'));
		if(dsel.getElementsByTagName('option').length == 0) {
			var types = globalOrgTypes;
			var depth = findOrgDepth(G.user.ws_ou());
			iterate(types, 
				function(t) {
					if(t.depth() > depth) return;
					insertSelectorVal(dsel, -1, t.opac_label(), t.depth());
				}
			);
		}
	}

	appendClear($('holds_recipient'), text(
		holdRecipient.family_name() + ', ' +  
			holdRecipient.first_given_name()));
	appendClear($('holds_title'), text(rec.title()));
	appendClear($('holds_author'), text(rec.author()));

	removeChildren($('holds_format'));
	for( var i in rec.types_of_resource() ) {
		var res = rec.types_of_resource()[i];
		var img = elem("img");
		setResourcePic(img, res);
		$('holds_format').appendChild(text(' '+res+' '));
		$('holds_format').appendChild(img);
		$('holds_format').appendChild(text(' '));
	}


	$('holds_phone').value = holdRecipient.day_phone();
	appendClear( $('holds_email'), text(holdRecipient.email()));

	var pref = G.user.prefs[PREF_HOLD_NOTIFY];

	if(pref) {
		if( ! pref.match(/email/i) ) 
			$('holds_enable_email').checked = false;

		if( ! pref.match(/phone/i) ) {
			$('holds_phone').disabled = true;
			$('holds_enable_phone').checked = false;
		}
	}

	$('holds_cancel').onclick = function(){ runEvt('common', 'holdUpdateCanceled'), showCanvas() };
	$('holds_submit').onclick = function(){holdsPlaceHold(holdsBuildHoldFromWindow())};
	$('holds_update').onclick = function(){holdsPlaceHold(holdsBuildHoldFromWindow())};
	appendClear($('holds_physical_desc'), text(rec.physical_description()));
	if(type == 'M') hideMe($('hold_physical_desc_row'));
}


function holdsCheckPossibility(recid, type) {
	var req = new Request(CHECK_HOLD_POSSIBLE, G.user.session, 
			{ titleid : recid, patronid : G.user.id(), depth : 0 } );
	req.send(true);
	var res = req.result();

	if(res) _holdsDrawWindow(recid, type);
	else drawCanvas();
}


function holdsBuildOrgSelector(node) {

	if(!node) node = globalOrgTree;

	var selector = $('holds_org_selector');
	var index = selector.options.length;

	var type = findOrgType(node.ou_type());
	var indent = type.depth() - 1;
	var opt = setSelectorVal( selector, index, node.name(), node.id(), null, indent );
	if(!type.can_have_vols()) opt.disabled = true;
	
	if( node.id() == holdRecipient.home_ou() ) {
		selector.selectedIndex = index;
		selector.options[index].selected = true;	
	}

	for( var i in node.children() ) {
		var child = node.children()[i];
		if(child) holdsBuildOrgSelector(child);
	}
}

function holdsBuildHoldFromWindow() {

	var org = $('holds_org_selector').options[
		$('holds_org_selector').selectedIndex].value;

	var hold = new ahr();
	if(holdEditHold) {
		hold = holdEditHold;
		holdEditHold = null;
	}


	if( $('holds_enable_phone').checked ) {
		var phone = $('holds_phone').value;
		if( !phone.match(REGEX_PHONE) ) {
			alert($('holds_bad_phone').innerHTML);
			return;
		}
		hold.phone_notify(phone);

	} else {
		hold.phone_notify("");
	}

	if( $('holds_enable_email').checked ) 
		hold.email_notify(1);
	else
		hold.email_notify(0);


	hold.pickup_lib(org); 
	hold.request_lib(org); 
	hold.requestor(holdRequestor.id());
	hold.usr(holdRecipient.id());
	hold.hold_type('T');
	hold.target(currentHoldRecord);
	if(isXUL())		
		hold.selection_depth(getSelectorVal($('holds_depth_selector')));
	return hold;
}
	
function holdsPlaceHold(hold) {

	var req = new Request( CREATE_HOLD, holdRequestor.session, hold );
	req.send(true);
	var res = req.result();

	if( res == '1' ) alert($('holds_success').innerHTML);
	else alert($('holds_failure').innerHTML);
	
	showCanvas();
	holdRecipient = null;
	holdRequestor = null;
	runEvt('common', 'holdUpdated');
}

function holdsCancel(holdid, user) {
	if(!user) user = G.user;
	var req = new Request(CANCEL_HOLD, user.session, holdid);
	req.send(true);
	return req.result();
	runEvt('common', 'holdUpdated');
}

function holdsUpdate(hold, user) {
	if(!user) user = G.user;
	var req = new Request(UPDATE_HOLD, user.session, hold);
	req.send(true);
	var x = req.result(); /* cause an exception if there is one */
	runEvt('common', 'holdUpdated');
}




