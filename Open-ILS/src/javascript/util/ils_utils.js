/* */


/* these are the types of resource provided my MODS - used in virtual records */
var resourceFormats = [ 
	"text", 
	"moving image",
	"sound recording",
	"software, multimedia",
	"still images",
	"cartographic",
	"mixed material",
	"notated music",
	"three dimensional object" ];



function findOrgDepth(type_id) {

	if(type_id == null || globalOrgTypes == null)
		return null;

	var t = findOrgType(type_id);
	if(t != null)
		return t.depth();

	return null;
}

function findOrgType(type_id) {

	if(type_id == null || globalOrgTypes == null)
		return null;

	if(typeof type_id == 'object')
		return type_id;

	for(var type in globalOrgTypes) {
		var t =globalOrgTypes[type]; 
		if( t.id() == type_id || t.id() == parseInt(type_id) ) 
			return t;
	}
	return null;
}


/* locates a specific org unit */
var orgArraySearcher = null;

/* flatten the org tree for faster searching */
function _flattenOrgs(node) { 

	if(node == null) {
		node = globalOrgTree;
		orgArraySearcher = new Object();
	}

	orgArraySearcher[node.id()] = node;
	for(var idx in node.children()) {
		_flattenOrgs(node.children()[idx]);
	}
}

var singleOrgCache = new Object();
function findOrgUnit(org_id, branch) {

	if(org_id == null) return null;
	if(typeof org_id == 'object') return org_id;

	/* if we don't have the global org tree, grab the org unit from the server */
	var tree_exists = false;
	try{if(globalOrgTree != null) tree_exists = true;}catch(E){}

	if(!tree_exists) {
		var org = singleOrgCache[org_id];
		if(org) return org;
		var r = new RemoteRequest(
			"open-ils.actor",
			"open-ils.actor.org_unit.retrieve", null, org_id);
		r.send(true);
		return r.getResultObject();
	}

	if(orgArraySearcher == null)
		_flattenOrgs();

	return orgArraySearcher[org_id];
}


function getOrgById(id, node) {
	if(node == null) node = globalOrgTree;
	if( node.id() == id) return node;
	for( var ind in node.children() ) {
		var ret = getOrgById(id, node.children()[ind] );
		if( ret != null )
			return ret;
	}
	return null;
}



function orgNodeTrail(node) {
	var nodeArray = new Array();
	while( node ) {
		nodeArray.push(node);
		node = findOrgUnit(node.parent_ou());
	}
	nodeArray = nodeArray.reverse();
	return nodeArray;
}

function findSiblingOrgs(node) {
	return findOrgUnit(node.parent_ou()).children();
}


function grabCopyLocations() {

	if(globalCopyLocations != null) return;
	debug("Grabbing copy locations");

	var req = new RemoteRequest(
		"open-ils.search",
		"open-ils.search.config.copy_location.retrieve.all" );

	req.send(true);
	globalCopyLocations = req.getResultObject();
	return globalCopyLocations;

}

function findCopyLocation(id) {

	grabCopyLocations();
	if(typeof id == 'object') return id;

	if(globalCopyLocations == null) 
		throw new EXLogic("globalCopyLocations is NULL");

	for( var x = 0; x!= globalCopyLocations.length; x++) {
		if(globalCopyLocations[x].id() == id)
			return globalCopyLocations[x];
	}
	return null;
}


function modsFormatToMARC(format) {
	switch(format) {
		case "text":
			return "at";
		case "moving image":
			return "g";
		case "sound recording":
			return "ij";
		case "software, multimedia":
			return "m";
		case "still images":
			return "k";
		case "cartographic":
			return "ef";
		case "mixed material":
			return "op";
		case "notated music":
			return "cd";
		case "three dimensional object":
			return "r";
	}
	throw new EXLogic("Invalid format provided form modsFormatToMARC: " + format);
}

function MARCFormatToMods(format) {
	switch(format) {

		case "a":
		case "t":
			return "text";

		case "g":
			return "moving image";

		case "i":
		case "j":
			return "sound recording";

		case "m":
			return "software, multimedia";

		case "k":
			return "still images";

		case "e":
		case "f":
			return "cartographic";

		case "o":
		case "p":
			return "mixed material";

		case "c":
		case "d":
			return "notated music";

		case "r":
			return "three dimensional object";
	}
	throw new EXLogic("Invalid format provided for MARCFormatToMods: " + format);
}



/* if callback exists, call is asynchronous and 
	the returned item is passed to the callback... */
function fetchRecord(id, callback) {

	var req = new RemoteRequest(
		"open-ils.search",
		"open-ils.search.biblio.record.mods_slim.retrieve",
		id );

	if(callback) {
		req.setCompleteCallback(
			function(req) {callback(req.getResultObject())});
		req.send();
	} else {
		req.send(true);
		return req.getResultObject();
	}
}

/* if callback exists, call is asynchronous and 
	the returned item is passed to the callback... */
function fetchMetaRecord(id, callback) {
	var req = new RemoteRequest(
		"open-ils.search",
		"open-ils.search.biblio.metarecord.mods_slim.retrieve",
		id );

	if(callback) {
		req.setCompleteCallback(
			function(req) {callback(req.getResultObject())});
		req.send();
	} else {
		req.send(true);
		return req.getResultObject();
	}
}

/* if callback exists, call is asynchronous and 
	the returned item is passed to the callback... */
/* XXX no method yet... */
function fetchVolume(id, callback) {
	var req = new RemoteRequest(
		"open-ils.search",
		"open-ils.search.biblio.metarecord.mods_slim.retrieve",
		id );

	if(callback) {
		req.setCompleteCallback(
			function(req) {callback(req.getResultObject())});
		req.send();
	} else {
		req.send(true);
		return req.getResultObject();
	}
}

/* if callback exists, call is asynchronous and 
	the returned item is passed to the callback... */
function fetchCopy(id, callback) {
	var req = new RemoteRequest(
		"open-ils.search",
		"open-ils.search.asset.copy.fleshed.retrieve",
		id );

	if(callback) {
		req.setCompleteCallback(
			function(req) {callback(req.getResultObject())});
		req.send();
	} else {
		req.send(true);
		return req.getResultObject();
	}
}

function mkResourceImage(resource) {
	var pic = elem("img");
	pic.setAttribute("src", "/images/" + resource + ".jpg");
	pic.setAttribute("width", "20");
	pic.setAttribute("height", "20");
	pic.setAttribute("title", resource);
	return pic;
}



function doLogout() {

	/* remove cookie so browser know's we're logged out */
	deleteCookie("ils_ses");

	var user = UserSession.instance();
	if( user.session_id ) {
		var request = new RemoteRequest( "open-ils.auth",
			"open-ils.auth.session.delete", user.session_id );
		request.send(true);
		var response = request.getResultObject();
		if(! response ) {
			//alert("error logging out"); /* exception */
		}
	}

	/* completely destroy this user object */
	user.destroy();
}




