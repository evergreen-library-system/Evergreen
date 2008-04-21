if(!dojo._hasResource["openils.widget.OrgUnitFilteringSelect"]){
dojo._hasResource["openils.widget.OrgUnitFilteringSelect"] = true;
dojo.require("dijit.form.FilteringSelect");
dojo.require("fieldmapper.OrgUtils");
dojo.provide("openils.widget.OrgUnitFilteringSelect");

/**
 * This widget provides a FilteringSelect for Org Units.  In particular,
 * it indents displayed name ('shortname', by default) based on the orgs depth 
 * to imitate a tree.  
 */

/* TODO add org sorting to ensure proper render order */

dojo.declare(
    "openils.widget.OrgUnitFilteringSelect", [dijit.form.FilteringSelect], 
    {
        _getMenuLabelFromItem : function(item) {
            var type = this.store.getValue(item, 'ou_type');
            var depth = fieldmapper.aout.findOrgType(type).depth();
            var lpad = depth*6; /* CSS instead? */

            return {
                html: true,
                label: '<div style="padding-left:'+lpad+'px;">' +
                    this.store.getValue(item, this.labelAttr || 'shortname') +
                    '</div>'
            }
        }
    }
);

}
