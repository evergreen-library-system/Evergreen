dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.layout.BorderContainer');
dojo.require("dojo.dnd.Container");
dojo.require("dojo.dnd.Source");
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require('openils.Event');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.ProgressDialog');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.widget.EditDialog');

var user;
var groups;
var locations;
var source;
var locTbody;
var locRowTemplate;
var locMapTbody;
var locMapRowTemplate;
var currentGroupId;
var currentGroupMaps;
var currentOrg;

function init() {

    user = new openils.User();
   
    // init the DnD environment
    source = new dojo.dnd.Source('acplg-list');
    dojo.connect(source, 'onDndDrop', updateGroupOrder);

    // context org selector
    user.buildPermOrgSelector(
        'ADMIN_COPY_LOCATION_GROUP', 
        contextOrgSelector, 
        null, 
        function() {
            dojo.connect(contextOrgSelector, 'onChange', drawPage);
        }
    );

    fetchCopyLocations();
}

function fetchCopyLocations() {
    // the full set of copy locations can be very large.  
    // Only retrieve the set of locations owned by orgs this user 
    // can use for building location groups.
    user.getPermOrgList(
        ['ADMIN_COPY_LOCATION_GROUP'], 
        function(list) {

            var ownerOrgList = [];
            dojo.forEach(list,
                function(org) {
                    // include parent orgs
                    ownerOrgList = ownerOrgList.concat(org).concat(
                        fieldmapper.aou.orgNodeTrail(fieldmapper.aou.findOrgUnit(org), true));
                }
            );

            var pcrud = new openils.PermaCrud({authtoken : user.authtoken});
            pcrud.search('acpl', // this can take some time...
                {owning_lib : ownerOrgList, deleted: 'f'},
                {   
                    async : true,
                    join : 'aou',
                    oncomplete : function(r) {
                        locations = openils.Util.readResponse(r);
                        sortCopyLocations();
                        drawPage(user.user.ws_ou());
                    }
                }
            );
        },
        true,
        true
    );
}

// sort the list of copy locations according the shape of 
// the org unit tree.  apply a secondary sort on name.
function sortCopyLocations() {
    var newlist = [];

    function addNode(node) {
        // find locs for this org
        var locs = locations.filter(function(loc) { return loc.owning_lib() == node.id() });
        // sort on name and append to the new list
        newlist = newlist.concat(locs.sort(function(a, b) { return a.name() < b.name() ? -1 : 1 }));
        // repeat for org child nodes
        dojo.forEach(node.children(), addNode);
    }

    addNode(fieldmapper.aou.globalOrgTree);
    locations = newlist;
}


function drawPage(org) {
    currentOrg = org;
    currentGroupId = null;
    currentGroupMaps = [];
    //drawLocations();
    drawGroupList();
}

function drawGroupList(selectedGrp) {
    var pcrud = new openils.PermaCrud({authtoken : user.authtoken});
    groups = pcrud.search('acplg', {owner : currentOrg}, {order_by : {acplg : 'pos'}});


    source.selectAll();
    source.deleteSelectedNodes();
    source.clearItems();

    dojo.forEach(groups,
        function(group) {
            if(!group) return;

            var drag = dojo.byId('dnd-drag-actions').cloneNode(true);
            drag.id = '';
            var vis = openils.Util.isTrue(group.opac_visible());
            openils.Util.hide(dojo.query('[name=' + (vis ? 'invisible' : 'visible') + ']', drag)[0]);


            var node = source.insertNodes(false, [{ 
                data : drag.innerHTML.replace(/GRPID/g, group.id()).replace(/GRPNAME/g, group.name()),
                type : [group.id()+''] // use the type field to store the ID
            }]);
        }
    );

    if (groups.length == 0) {
        selectedGrp = null
    } else if (selectedGrp == null) {
        selectedGrp = groups[0].id();
    }

    drawGroupEntries(selectedGrp);
}

function drawLocations() {

    if (!locTbody) {
        locTbody = dojo.byId('acplg-loc-tbody');
        locRowTemplate = locTbody.removeChild(dojo.byId('acplg-loc-row'));
    } else {
        // clear out the previous table
        while (node = locTbody.childNodes[0])
            locTbody.removeChild(node);
    }

    var allMyOrgs = fieldmapper.aou.fullPath(currentOrg, true);

    dojo.forEach(locations,
        function(loc) {
            if (allMyOrgs.indexOf(loc.owning_lib()) == -1) return;

            // don't show locations contained in the current group
            if (currentGroupMaps.length) {
                var existing = currentGroupMaps.filter(
                    function(map) { return (map.location() == loc.id()) });
                if (existing.length > 0) return;
            }

            var row = locRowTemplate.cloneNode(true);
            row.setAttribute('location', loc.id());
            dojo.query('[name=name]', row)[0].innerHTML = loc.name();
            dojo.query('[name=owning_lib]', row)[0].innerHTML = fieldmapper.aou.findOrgUnit(loc.owning_lib()).shortname();
            locTbody.appendChild(row);
        }
    );
}

function updateGroupOrder() {
    var pos = 0;
    var toUpdate = [];

    // find any groups that have changed position and send them off for update
    dojo.forEach(
        source.getAllNodes(),
        function(node) {
            var item = source.getItem(node.id);
            var grpId = item.type[0];
            var grp = groups.filter(function(g) { return g.id() == grpId })[0];
            if (grp.pos() != pos) {
                grp.pos(pos);
                toUpdate.push(grp);
            }
            pos++;
        }
    );

    if (toUpdate.length == 0) return;

    var pcrud = new openils.PermaCrud({authtoken : user.authtoken});
    pcrud.update(toUpdate); // run sync to prevent UI changes mid-update 
}

function newGroup() {

    var dialog = new openils.widget.EditDialog({
        fmClass : 'acplg',
        mode : 'create',
        parentNode : dojo.byId('acplg-edit-dialog'),
        suppressFields : ['id'],
        // note: when 'pos' is suppressed, the value is not propagated.
        overrideWidgetArgs : {
            pos : {widgetValue : groups.length, dijitArgs : {disabled : true}},
            owner : {widgetValue : currentOrg, dijitArgs : {disabled : true}}
        },
        onPostSubmit : function(req, cudResults) {
            if (cudResults && cudResults.length) {
                // refresh the group display
                drawGroupList(cudResults[0].id());
            }
        }
    });

    dialog.startup();
    dialog.show();
}

function editGroup(grpId) {
    var grp = groups.filter(function(g) { return g.id() == grpId })[0];

    var dialog = new openils.widget.EditDialog({
        fmObject : grp,
        mode : 'update',
        parentNode : dojo.byId('acplg-edit-dialog'),
        suppressFields : ['id', 'pos', 'owner'],
        onPostSubmit : function(req, cudResults) {
            if (cudResults && cudResults.length) {
                // refresh the group display
                // pcrud.update returns ID only
                drawGroupList(cudResults[0]);
            }
        }
    });

    dialog.startup();
    dialog.show();
}

function deleteGroup(grpId) {
    // confirm and delete
    var pcrud = new openils.PermaCrud({authtoken : user.authtoken});
    var grp = groups.filter(function(g) { return g.id() == grpId })[0];
    pcrud.eliminate(grp, {oncomplete : function() { drawGroupList() }});
}

function drawGroupEntries(grpId) {
    currentGroupId = grpId;

    // init/reset the table of mapped copy locations
    if (!locMapTbody) {
        locMapTbody = dojo.byId('acplg-loc-map-tbody');
        locMapRowTemplate = locMapTbody.removeChild(dojo.byId('acplg-loc-map-row'));
    } else {
        // clear out the previous table
        while (node = locMapTbody.childNodes[0])
            locMapTbody.removeChild(node);
    }
    
    // update the 'selected' status
    dojo.query('[group]').forEach(
        function(node) {
            if (node.getAttribute('group') == grpId) {
                openils.Util.addCSSClass(node, 'acplg-group-selected');
            } else {
                openils.Util.removeCSSClass(node, 'acplg-group-selected');
            }
        }
    );

    currentGroupMaps = [];

    // fetch the group
    if (grpId) {
        var pcrud = new openils.PermaCrud({authtoken : user.authtoken});
        currentGroupMaps = pcrud.search('acplgm', {lgroup : grpId});
    } 

    // update the location selector to remove the already-selected orgs
    drawLocations();

    // draw the mapped copy locations
    // remove any mapped locations from the location selector
    dojo.forEach(currentGroupMaps,
        function(map) {
            var row = locMapRowTemplate.cloneNode(true);
            row.setAttribute('map', map.id());
            var loc = locations.filter(
                function(loc) { return (loc.id() == map.location()) })[0];
            dojo.query('[name=name]', row)[0].innerHTML = loc.name();
            dojo.query('[name=owning_lib]', row)[0].innerHTML = 
                fieldmapper.aou.findOrgUnit(loc.owning_lib()).shortname();
            locMapTbody.appendChild(row);

            // if the location is in the group, remove it from the location selection list
            //removeLocationRow(loc.id());
        }
    );
}

function editLocations(action) {
    var maps = [];
    var tbody = (action == 'create') ? locTbody : locMapTbody;
    dojo.forEach(tbody.getElementsByTagName('tr'),
        function(row) {
            var selector = dojo.query('[name=selector]', row)[0];
            if (selector.checked) {
                var map = new fieldmapper.acplgm();
                map.lgroup(currentGroupId);
                if (action == 'create') {
                    map.location(row.getAttribute('location'));
                } else {
                    map.id(row.getAttribute('map'));
                }
                maps.push(map);
            }
        }
    );

    if (maps.length == 0) return;

    // check for dupes
    var pcrud = new openils.PermaCrud({authtoken : user.authtoken});
    pcrud[action](maps, {
        oncomplete : function() { 
            drawGroupEntries(currentGroupId) 
            /*
            if (action != 'create') {
                drawLocations();
            }
            */
        }
    });
}

function deSelectAll(node) {
    dojo.query('[name=selector]', node).forEach(
        function(selector) {
            selector.checked = false;
        }
    );
}

/*
function removeLocationRow(locId) {
    var row = dojo.query('[location=' + locId + ']', locTbody)[0];
    if (row) locTbody.removeChild(row);
}
*/

openils.Util.addOnLoad(init);
