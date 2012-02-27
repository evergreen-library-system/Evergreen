var USER;
var SESSION;
var PERMS = {};
var ORG_CACHE = {};
var OILS_WORK_PERMS = {};

var XML_ELEMENT_NODE = 1;
var XML_TEXT_NODE = 3;

var FETCH_ORG_UNIT = "open-ils.actor:open-ils.actor.org_unit.retrieve";

function debug(str) { try { dump(str + '\n'); } catch(e){} }

function fetchUser(session) {
    if(session == null ) {
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
    }
    if(!session) throw "User session is not defined";
    SESSION = session;
    var request = new Request(FETCH_SESSION, session);
    request.send(true);
    var user = request.result();
    if(checkILSEvent(user)) throw user;
    USER = user;
    return user;
}

/* if defined, callback will get the user object asynchronously */
function fetchFleshedUser(id, callback) {
    if(id == null) return null;
    var req = new Request(
        'open-ils.actor:open-ils.actor.user.fleshed.retrieve', SESSION, id );

    if( callback ) {
        req.callback( function(r){callback(r.getResultObject());} );
        req.send();

    } else {
        req.send(true);
        return req.result();
    }
}

/**
  * Fetches the highest org at for each perm  and stores the value in
  * PERMS[ permName ].  It also returns the org list to the caller
  */
function fetchHighestPermOrgs( session, userId, perms ) {
    var req = new RemoteRequest(
        'open-ils.actor',
        'open-ils.actor.user.perm.highest_org.batch', 
        session, userId, perms  );
    req.send(true);
    var orgs = req.getResultObject();
    for( var i = 0; i != orgs.length; i++ ) 
        PERMS[perms[i]] = orgs[i];
        //PERMS[ perms[i] ] = ( orgs[i] != null ) ? orgs[i] : -1 ;
    return orgs;
}

function fetchHighestWorkPermOrgs(session, userId, perms, onload) {
    var req = new RemoteRequest(
        'open-ils.actor',
        'open-ils.actor.user.has_work_perm_at.batch',
        session, perms);
    if(onload) {
        req.setCompleteCallback(function(r){
            onload(OILS_WORK_PERMS = r.getResultObject());
        });
        req.send()
    } else {
        req.send(true);
        return OILS_WORK_PERMS = req.getResultObject();
    }
}

/*
 takes org IDs 
 Finds the lowest relevent org unit between a context org unit and a set of
 permission orgs.  This defines the sphere of influence for a given action
 on a specific set of data.  if the context org shares no common nodes with
 the set of permission orgs, null is returned.
 returns the orgUnit object
 */
function findReleventRootOrg(permOrgList, contextOrgId) {
    var contextOrgNode = findOrgUnit(contextOrgId);
    for(var i = 0; i < permOrgList.length; i++) {
        var permOrg = findOrgUnit(permOrgList[i]);
        if(orgIsMine(permOrg, contextOrgNode)) {
            // perm org is equal to or a parent of the context org, so the context org is the highest
            return contextOrgNode;
        } else if(orgIsMine(contextOrgNode, permOrg)) {
            // perm org is a child if the context org, so permOrg is the highest org
            return permOrg;
        }
    }
    return null;
}


/* offset is the depth of the highest org 
    in the tree we're building 
  */

/* XXX Moved to opac_utils.js */

/*
function buildOrgSel(selector, org, offset) { 
    insertSelectorVal( selector, -1, 
        org.name(), org.id(), null, findOrgDepth(org) - offset );
    for( var c in org.children() )
        buildOrgSel( selector, org.children()[c], offset);
}
*/

/** removes all child nodes in 'tbody' that have the attribute 'key' defined */
function cleanTbody(tbody, key) {
    for( var c  = 0; c < tbody.childNodes.length; c++ ) {
        var child = tbody.childNodes[c];
        if(child && child.getAttribute(key)) tbody.removeChild(child); 
    }
}


/** Inserts a row into a specified place in a table
  * tbody is the table body
  * row is the context row after which the new row is to be inserted
  * newRow is the new row to insert
  */
function insRow( tbody, row, newRow ) {
    if(row.nextSibling) tbody.insertBefore( newRow, row.nextSibling );
    else{ tbody.appendChild(newRow); }
}


/** Checks to see if a given node should be enabled
  * A node should be enabled if the itemOrg is lower in the
  * org tree than my permissions allow editing
  * I.e. I can edit the context item because it's "below" me
  */
function checkDisabled( node, itemOrg, perm ) {
    var itemDepth = findOrgDepth(itemOrg);
    var mydepth = findOrgDepth(PERMS[perm]);
    if( mydepth != -1 && mydepth <= itemDepth ) node.disabled = false;
}

/**
  * If the item-related org unit (owner, etc.) is one of or
  * or a child of any of the perm-orgs related to the
  * provided permission, enable the requested node
  */
function checkPermOrgDisabled(node, itemOrg, perm) {
    var org_list = OILS_WORK_PERMS[perm];
    if(org_list.length > 0) {
        for(var i = 0; i < org_list.length; i++) {
            var highPermOrg = findOrgUnit(org_list[i]);
            if(orgIsMine(highPermOrg, findOrgUnit(itemOrg))) 
                node.disabled = false;
        }
    }
}


function fetchOrgUnit(id, callback) {

    if(ORG_CACHE[id]) return ORG_CACHE[id];
    var req = new Request(FETCH_ORG_UNIT, SESSION, id);    

    if(callback) {
        req.callback(
            function(r) { 
                var org = r.getResultObject();
                ORG_CACHE[id] = org;
                callback(org); 
            }
        );
        req.send();

    } else {
        req.send(true);
        var org = req.result();
        ORG_CACHE[id] = org;
        return org;
    }
}
