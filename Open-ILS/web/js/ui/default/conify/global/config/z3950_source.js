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

        // draw the credentials context org unit selector
        new openils.User().buildPermOrgSelector(
            'ADMIN_Z3950_SOURCE', z39ContextSelector);

    } else {

        zsGrid.loadAll({order_by:{czs : 'name'}});
    }
}

function applyCreds(clear) {
    dojo.byId('z39-creds-button').disabled = true;
    dojo.byId('z39-creds-clear').disabled = true;
    fieldmapper.standardRequest(
        ['open-ils.search', 'open-ils.search.z3950.apply_credentials'],
        {   async : true,
            params : [
                openils.User.authtoken,
                sourceCode,
                z39ContextSelector.attr('value'),
                clear ? '' : dojo.byId('z39-creds-username').value,
                clear ? '' : dojo.byId('z39-creds-password').value
            ],
            oncomplete : function(r) {
                dojo.byId('z39-creds-password').value = '';
                dojo.byId('z39-creds-button').disabled = false;
                dojo.byId('z39-creds-clear').disabled = false;
                openils.Util.readResponse(r);
            }
        }
    );
}

function formatSourceName(val) {
    return '<a href="' + location.href + '/' + encodeURIComponent(val) + '">' + val + '</a>';
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


