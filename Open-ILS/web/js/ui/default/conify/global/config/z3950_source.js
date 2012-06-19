dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dijit.form.NumberTextBox');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.Dialog');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.FlattenerGrid');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.User');
dojo.require('openils.PermaCrud');
var zsList;

function buildZSGrid() {

    if (sourceCode) {

        zaGrid.overrideWidgetArgs.source = {
            widgetValue : sourceCode, 
            readOnly : true
        };

    } else {

        zsGrid.loadAll({order_by:{czs : 'name'}});
    }
}

function formatSourceName(val) {
    return '<a href="' + location.href + '/' + escape(val) + '">' + val + '</a>';
}

var cloneSourceSelector;
function showAttrCloneDialog() {
    attrCloneDialog.show();
    if (!cloneSourceSelector) {
        cloneSourceSelector = new openils.widget.AutoFieldWidget({
            fmClass : 'czs',
            fmField : 'name',
            selfReference : true,
            parentNode : 'attr-clone-source'
        });
        cloneSourceSelector.build();
    }
}

function cloneFromSource() {
    var pcrud = new openils.PermaCrud({authtoken : openils.User.authtoken}); 
    var remoteAttrs = pcrud.search('cza', {source : cloneSourceSelector.widget.attr('value')});
    var myAttrs = pcrud.search('cza', {source : sourceCode});
    var newAttrs = [];

    dojo.forEach(remoteAttrs, 
        function(rattr) {

            // if this source already has an attribute with the same name, don't clobber it
            if (myAttrs.filter(function(a) { return (a.name() == rattr.name()) })[0]) 
                return;
            
            var newAttr = rattr.clone();
            newAttr.id(null);
            newAttr.isnew(true);
            newAttr.source(sourceCode);
            newAttrs.push(newAttr);
        }
    );

    if (newAttrs.length) {
        pcrud.create(newAttrs, 
            {oncomplete : function() { zaGrid.refresh() }});
    }

    attrCloneDialog.hide();
}

openils.Util.addOnLoad(buildZSGrid);


