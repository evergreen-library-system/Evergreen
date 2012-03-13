dojo.require("dijit.form.Button");
dojo.require("dojo.dnd.Source");
dojo.require("openils.User");
dojo.require("openils.Util");
dojo.require("openils.PermaCrud");
dojo.require('openils.widget.OrgUnitFilteringSelect');

var user;
var pcrud;
var dndSource;

function pageInit() {
    user = new openils.User();
    pcrud = new openils.PermaCrud({authtoken : user.authtoken});
    fieldmapper.aou.slim_ok = false; // we need full orgs for updates

    user.buildPermOrgSelector(
        ['UPDATE_ORG_UNIT', 'ADMIN_ORG_UNIT'],
        contextOrgSelector, 
        null, 
        function() {
            dojo.connect(contextOrgSelector, 'onChange', drawChildren)
            // set the value to the root of the tree (instead of ws_ou).
            contextOrgSelector.store.fetch({
                query : {id : '*'},
                onComplete : function(list) {
                    contextOrgSelector.attr('value', list[0].id);
                }
            });
        }
    );
}

var tbody, rowTmpl;
function drawChildren() {

    if(!tbody) {
        tbody = dojo.byId('child-tbody');
        rowTmpl = tbody.removeChild(dojo.byId('row-template'));
        dndSource = new dojo.dnd.Source(tbody);
        dojo.connect(dndSource, 'onDndDrop', updateSiblingOrder);
    }

    dndSource.selectAll();
    dndSource.deleteSelectedNodes();
    dndSource.clearItems();

    var org = fieldmapper.aou.findOrgUnit(contextOrgSelector.attr('value'));
    if (!org.children()) return;
   
    // fetch the full child org units
    org.children( 
        org.children().map(
            function(c) { return fieldmapper.aou.findOrgUnit(c.id()) }
        )
    );

    // sort by sibling order, fall back to name
    var children = org.children().sort(
        function(a, b) {
            if (a.sibling_order() < b.sibling_order()) {
                return -1;
            } else if (a.sibling_order() > b.sibling_order()) {
                return 1;
            } else if (a.name() < b.name()) {
                return -1;
            }
            return 1;
        }
    );

    dojo.forEach(
        children,
        function(child) {
            var row = tbody.appendChild(rowTmpl.cloneNode(true));
            row.setAttribute('child', child.id());
            dojo.query('[name=name]', row)[0].innerHTML = child.name();
            dndSource.insertNodes(false, [row]);
        }
    );
}

function updateSiblingOrder() {
    var pos = 0;
    var toUpdate = [];
    dojo.forEach(
        dndSource.getAllNodes(),
        function(node) {
            childId = node.getAttribute('child');
            var child = fieldmapper.aou.findOrgUnit(childId);
            if (child.sibling_order() != pos) {
                child.sibling_order(pos);
                toUpdate.push(child);
            }
            pos++;
        }
    );

    if (toUpdate.length == 0) return;
    pcrud.update(toUpdate); // run sync to prevent UI changes mid-update 
}

openils.Util.addOnLoad(pageInit);
