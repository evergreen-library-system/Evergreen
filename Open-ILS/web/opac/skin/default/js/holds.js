
var currentHoldRecord;
var currentHoldRecordObj;
var holdsOrgSelectorBuilt = false;

function holdsDrawWindow(recid, type) {

	if(recid == null) {
		recid = currentHoldRecord;
		if(recid == null) return;
	}
	currentHoldRecord = recid;

	if(!(G.user && G.user.session)) {

		detachAllEvt('common','locationChanged');
		attachEvt('common','loggedIn', holdsDrawWindow)
		initLogin();
		return;
	}
	swapCanvas($('holds_box'));

	var rec = findRecord( recid, type );
	currentHoldsRecordObj = rec;

	if(!holdsOrgSelectorBuilt) {
		holdsBuildOrgSelector(null,0);
		holdsOrgSelectorBuilt = true;
	}

	removeChildren($('holds_title'));
	removeChildren($('holds_author'));
	removeChildren($('holds_format'));
	removeChildren($('holds_email'));
	removeChildren($('holds_email'));

	$('holds_title').appendChild(text(rec.title()));
	$('holds_author').appendChild(text(rec.author()));

	for( var i in rec.types_of_resource() ) {
		var res = rec.types_of_resource()[i];
		var img = elem("img");
		setResourcePic(img, res);
		$('holds_format').appendChild(text(' '+res+' '));
		$('holds_format').appendChild(img);
		$('holds_format').appendChild(text(' '));
	}

	$('holds_phone').appendChild(text(G.user.day_phone()));
	$('holds_email').appendChild(text(G.user.email()));
	$('holds_cancel').onclick = showCanvas;
	$('holds_submit').onclick = holdsPlaceHold; 
}


function holdsBuildOrgSelector(node, depth) {

	if(!node) {
		node = globalOrgTree;
		depth = 0;
	}

	var selector = $('holds_org_selector');
	var index = selector.options.length;

	if(IE) {
		var pre = elem("pre");
		for(var x=2; x <= findOrgType(node.ou_type()).depth(); x++) {
			pre.appendChild(text("    "));
		}
		pre.appendChild(text(node.name()));
		var select = new Option("", node.id());
		selector.options[index] = select;
		select.appendChild(pre);
	
	} else {
		var pad = (findOrgType(node.ou_type()).depth() - 1) * 12;
		if(pad < 0) pad = 0;
		var select = new Option(node.name(), node.id());
		select.setAttribute("style", "padding-left: "+pad+'px;');
		selector.options[index] = select;
	}	

	if( node.id() == G.user.home_ou() ) {
		selector.selectedIndex = index;
		selector.options[index].selected = true;	
	}

	for( var i in node.children() ) {
		var child = node.children()[i];
		if(child) {
			holdsBuildOrgSelector(child, depth+1);
		}
	}
}

function holdsPlaceHold() {
	//alert("placing hold for " + currentHoldRecord );

	var org = $('holds_org_selector').options[$('holds_org_selector').selectedIndex].value;

	var hold = new ahr();
	hold.pickup_lib(org); 
	hold.request_lib(org); 
	hold.requestor(G.user.id());
	hold.usr(G.user.id());
	hold.hold_type('T');
	hold.email_notify(G.user.email());
	hold.phone_notify(G.user.day_phone());
	hold.target(currentHoldRecord);
	
	var req = new Request( CREATE_HOLD, G.user.session, hold );
	req.send(true);
	var res = req.result();

	/* XMLize me  XXX */
	if( res == '1' ) alert($('holds_success').innerHTML);
	else alert($('holds_failure').innerHTML);
	
	showCanvas();
}

function holdsCancel(holdid) {
	var req = new Request(CANCEL_HOLD, G.user.session, holdid);
	req.send(true);
	return req.result();
}


