var ORG_SETTING_UPDATE		= 'open-ils.actor:open-ils.actor.org_unit.settings.update';
var ORG_SETTING_RETRIEVE	= 'open-ils.actor:open-ils.actor.org_unit.settings.retrieve';
var ORG_SETTING_DELETE		= 'open-ils.actor:open-ils.actor.org_setting.delete';

var myPerms = [ 'UPDATE_ORG_SETTING' ];


var ORG_SETTINGS = {
	'circ.lost_materials_processing_fee' : null,
	'cat.default_item_price' : null,
	'circ.collections_fee' : null
};

function osEditorInit() {
	fetchUser();
	$('user').appendChild(text(USER.usrname()));

	for( var i in ORG_SETTINGS ) ORG_SETTINGS[i] = $(i);

	setTimeout( 
		function() { 
			fetchHighestPermOrgs( SESSION, USER.id(), myPerms );
			osBuildOrgs();
			osDrawRange();
		}, 
		20 
	);
}

function osCurrentOrg() {
	var selector = $('os_orgs');
	return getSelectorVal(selector);
}

function osBuildOrgs() {
	var org = findOrgUnit(PERMS['UPDATE_ORG_SETTING']);

	if( !org || org == -1 ) {
		org = findOrgUnit(USER.ws_ou());
		for( var i in ORG_SETTINGS ) 
			$(i+'.apply').disabled = true;
	}

	var type = findOrgType(org.ou_type()) ;

	var selector = $('os_orgs');
	buildOrgSel(selector, org, type.depth());
	if(!type.can_have_users()) 
		selector.options[0].disabled = true;

	selector.onchange = osDrawRange;

	osBaseOrg = org;

	if( ! osBaseOrg.children() ) 
		for( var i in ORG_SETTINGS ) 
			$(i+'.apply_all').disabled = true;

	var gotoOrg = USER.ws_ou();
	if( ! setSelector( selector, gotoOrg ) ) {
		gotoOrg = USER.home_ou();
		setSelector( selector, gotoOrg );
	}

	return gotoOrg;
}



function osDrawRange() {
	var org = osCurrentOrg();
	appendClear($('osCurrentOrg'), text(findOrgUnit(org).name()));
	var req = new Request(ORG_SETTING_RETRIEVE, org);
	req.callback(osDraw);
	req.send();
}


function osDraw( r ) {
	var org = osCurrentOrg();
	var settings = r.getResultObject();

	for( var i in ORG_SETTINGS ) {
		var node = ORG_SETTINGS[i];
		var val = settings[i];
		node.value = 
			(node.getAttribute('ismoney')) ?  
				_formatMoney(val) : (val != null) ? val : "";
	}
}

function _formatMoney(m) {
	if(!m || m == 0) return '0.00';
	m = m + '';
	if( m.match(/\d+\.\d+/) ) return m;
	if( !m.match(/\./) ) return m + '.00';
	if( m.match(/^\.\d+/) ) return '0' + m;
	return m;
}


