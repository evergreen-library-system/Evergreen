dojo.require("openils.widget.AutoGrid");
dojo.require("openils.widget.OrgUnitFilteringSelect");

var owner;

function prepareOwnerSelector(perm) {
    new openils.User().buildPermOrgSelector(
        perm,
        ownerSelect,
        null,
        function() {
            dojo.connect(
                ownerSelect,
                "onChange",
                function() {
                    owner = fieldmapper.aou.findOrgUnit(this.attr("value"));
                    grid.resetStore();
                    populateGrid();
                }
            );
        }
    );
}

function populateGrid(id) {
    var search = typeof(ownerSelect) == "undefined" ? {"id": {"!=": null}} : {
        "org_unit": fieldmapper.aou.orgNodeTrail(
            owner || fieldmapper.aou.findOrgUnit(openils.User.user.ws_ou()),
            true /* asId */
        )
    };
    if (id) search.id = id;

    grid.loadAll(null, search);
}
