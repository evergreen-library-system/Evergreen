/* ------------------------------------------------------------------------------------------------------ */
/* org tree utilities */
/* ------------------------------------------------------------------------------------------------------ */

function fetchOrgSettingDefault(orgId, name) {
    var req = new Request(FETCH_ORG_SETTING, orgId, name);
    req.send(true);
    var res = req.result();
    return (res) ? res.value : null;
}

function fetchBatchOrgSetting(orgId, nameList, onload) {
    var req = new Request(
        'open-ils.actor:open-ils.actor.ou_setting.ancestor_default.batch', orgId, nameList);
    if(onload) {
        req.callback(function(r) { onload(r.getResultObject()); });
        req.send();
    } else {
        req.send(true);
        return req.result();
    }
}


/* takes an org unit or id and return the numeric depth */
function findOrgDepth(org_id_or_node) {
	var org = findOrgUnit(org_id_or_node);
	if(!org) return -1;
	var type = findOrgType(org.ou_type());
	if(type) return type.depth();
	return -1;
}

function findOrgTypeFromDepth(depth) {
	if( depth == null ) return null;
	for( var type = 0; type < globalOrgTypes.length; type++ ) {
		var t = globalOrgTypes[type];
		if( t.depth() == depth ) return t;
	}
}

/* takes the org type id from orgunit.ou_type() field and returns
	the org type object */
function findOrgType(type_id) {
	if(typeof type_id == 'object') return type_id;
	for(var type = 0; type < globalOrgTypes.length; type++) {
		var t =globalOrgTypes[type]; 
		if( t.id() == type_id || t.id() == parseInt(type_id) ) 
			return t;
	}
	return null;
}


/* returns an org unit by id.  if an object is passed in as the id,
	then the object is assumed to be an org unit and is returned */
function findOrgUnit(org_id) {
	return (typeof org_id == 'object') ? org_id : orgArraySearcher[org_id];
}

function findOrgLasso(lasso_id) {
	if (typeof lasso_id == 'object') return lasso_id;
    for (var i = 0; i < _lasso.length; i++) {
        if (_lasso[i].id() == lasso_id) return _lasso[i];
    }
    return null;
}

var orgArraySearcherSN = {};
function findOrgUnitSN(shortname) {
	if (typeof shortname == 'object') return shortname;
	if( orgArraySearcherSN[shortname] ) return orgArraySearcherSN[shortname];
	_debug("fetching org by shortname "+shortname);
	var req = new Request(FETCH_ORG_BY_SHORTNAME, shortname);
	req.request.alertEvent = false;
	req.send(true);
	return req.result();
}


/* builds a trail from the top of the org tree to the node provide.
	basically fleshes out 'my orgs' 
	Returns an array of [org0, org1, ..., myorg] */
function orgNodeTrail(node) {
	var na = new Array();
	while( node ) {
		na.push(node);
		node = findOrgUnit(node.parent_ou());
	}
	return na.reverse();
}

function findSiblingOrgs(node) { return findOrgUnit(node.parent_ou()).children(); }

/* true if 'org' is 'me' or a child of mine, or optionally, a child of an ancestor org within the specified depth */
function orgIsMine(me, org, depth) {
	if(!me || !org) {
		return false;
	}
	if(me.id() == org.id()) {
		return true;
	}
	if (depth !== undefined) {
		while (depth < findOrgDepth(me)) {
			me = findOrgUnit( me.parent_ou() );
		}
		if(me.id() == org.id()) {
			return true;
		}
	}
	var kids = me.children();
	for( var i = 0; kids && i < kids.length; i++ ) {
		if(orgIsMine(kids[i], org /* intentional lack of 3rd arg */)) {
			return true;
		}

	}
	return false;
}

function orgIsMineFromSet(meList, org) {
    org = findOrgUnit(org);
    for(var i = 0; i < meList.length; i++) {
        if(orgIsMine(findOrgUnit(meList[i]), org))
            return true;
    }
    return false;
}

var orgArraySearcher = {};
var orgArraySearcherOrder = [];
var globalOrgTree;
for (var i = 0; i < _l.length; i++) {
	var x = new aou();
	x.id(_l[i][0]);
	x.ou_type(_l[i][1]);
	x.parent_ou(_l[i][2]);
	x.name(_l[i][3]);
	x.opac_visible(_l[i][4]);
	x.shortname(_l[i][5]);
	orgArraySearcher[x.id()] = x;
	orgArraySearcherOrder.push(x.id());
}
for (var i = 0; i < orgArraySearcherOrder.length; i++) {
	var x = orgArraySearcher[orgArraySearcherOrder[i]];
	if (x.parent_ou() == null || x.parent_ou() == '') {
		globalOrgTree = x;
		continue;
	} 

	var par = findOrgUnit(x.parent_ou());
	if (!par.children()) par.children(new Array());
	par.children().push(x);
}

function _tree_killer () {
	for (var i in orgArraySearcher) {
		x=orgArraySearcher[i];
		x.children(null);
		x.parent_ou(null);
		orgArraySearcher[i]=null;
	}
	globalOrgTree = null;
	orgArraySearcher = null;
	globalOrgTypes = null;
}



