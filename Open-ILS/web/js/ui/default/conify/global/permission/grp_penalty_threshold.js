dojo.require('dijit.form.FilteringSelect');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.widget.PermGrpFilteringSelect');


function buildGrid(org_id) {
    var org_id = openils.User.user.ws_ou();
    var list = fieldmapper.aou.findOrgUnit(org_id).orgNodeTrail().map( function (i) { 
            return i.id() } );       
    
     gptGrid.loadAll({order_by:{pgpt : 'grp'}},{org_unit:list});   

     new openils.User().buildPermOrgSelector('VIEW_GROUP_PENALTY_THRESHOLD', contextOrgSelector, null, function() {
             dojo.connect(contextOrgSelector, 'onChange', filterGrid);});   
}

function filterGrid() {
    gptGrid.resetStore();
    var unit = contextOrgSelector.getValue();   
    var list = fieldmapper.aou.findOrgUnit(unit).orgNodeTrail().map( function (i) { 
            return i.id() } );       

    if(unit) 
        gptGrid.loadAll({order_by:{pgpt: 'grp'}}, {org_unit:list});
    else
        gptGrid.loadAll({order_by:{pgpt : 'grp'}});
    
}

openils.Util.addOnLoad(buildGrid);
