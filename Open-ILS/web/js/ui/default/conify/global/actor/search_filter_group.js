dojo.require('dijit.form.TextBox');
dojo.require('openils.Util');
dojo.require('openils.User');
dojo.require('fieldmapper.OrgUtils');
dojo.require("openils.widget.FlattenerGrid");
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.PermaCrud');

var fgeEditLabel, fgeEditQuery, fgeEditPos;
var curEntry, ocHandler;

// Builds an editor table for filter group entries
function showFgeEditor(fgeId, create) {

    dojo.addClass(fgeGrid.domNode, 'hidden');
    dojo.removeClass(dojo.byId('fge-edit-div'), 'hidden');

    function cancelHandler() {
        dojo.removeClass(fgeGrid.domNode, 'hidden');
        dojo.addClass(dojo.byId('fge-edit-div'), 'hidden');
    }

    if (!fgeEditLabel) { 

        // first time loading the editor.  build the widgets.

        fgeEditLabel = new openils.widget.AutoFieldWidget({
            fmField : 'label',
            fmClass : 'asq',
            parentNode : dojo.byId('fge-edit-label')
        });

        fgeEditLabel.build();

        fgeEditQuery = new openils.widget.AutoFieldWidget({
            fmField : 'query_text',
            fmClass : 'asq',
            parentNode : dojo.byId('fge-edit-query')
        });

        fgeEditQuery.build();

        fgeEditPos = new openils.widget.AutoFieldWidget({
            fmField : 'pos',
            fmClass : 'asfge',
            parentNode : dojo.byId('fge-edit-pos')
        });

        fgeEditPos.build();
        dojo.connect(fgeCancel, 'onClick', cancelHandler);
    }

    var pcrud = new openils.PermaCrud({authtoken : openils.User.authtoken});

    if (create) {

        curEntry = new fieldmapper.asfge();
        curEntry.isnew(true);
        curEntry.grp(filterGroupId);
        curEntry.query(new fieldmapper.asq());

        fgeEditLabel.widget.attr('value', '');
        fgeEditQuery.widget.attr('value', '');
        fgeEditPos.widget.attr('value', '');

    } else {

        // we're editing an existing entry, fetch it first

        curEntry = fieldmapper.standardRequest(
            ['open-ils.actor', 'open-ils.actor.filter_group_entry.crud'],
            {params : [openils.User.authtoken, fgeId], async : false}
        );

        fgeEditLabel.widget.attr('value', curEntry.query().label());
        fgeEditQuery.widget.attr('value', curEntry.query().query_text());
        fgeEditPos.widget.attr('value', curEntry.pos());
        curEntry.ischanged(true);
    }

    if (ocHandler) dojo.disconnect(ocHandler);
    ocHandler = dojo.connect(fgeSave, 'onClick',
        function() {

            // creates / updates entries

            curEntry.query().label(fgeEditLabel.widget.attr('value'));
            curEntry.query().query_text(fgeEditQuery.widget.attr('value'));
            curEntry.pos(fgeEditPos.widget.attr('value'));
            
            var stat = fieldmapper.standardRequest(
                ['open-ils.actor', 'open-ils.actor.filter_group_entry.crud'],
                {params : [openils.User.authtoken, curEntry], async : false}
            );

            cancelHandler();
            fgeGrid.refresh();
        }
    );
}

// deletes filter group entries (after fetching them first)
function fgeDelete() {

    dojo.forEach(
        fgeGrid.getSelectedItems(),
        function(item) {

            console.log(item);
            var id = fgeGrid.store.getValue(item, 'id');

            var entry = fieldmapper.standardRequest(
                ['open-ils.actor', 'open-ils.actor.filter_group_entry.crud'],
                {params : [openils.User.authtoken, id], async : false}
            );

            entry.isdeleted(true);

            var stat = fieldmapper.standardRequest(
                ['open-ils.actor', 'open-ils.actor.filter_group_entry.crud'],
                {params : [openils.User.authtoken, entry], async : false}
            );
        }
    );

    fgeGrid.refresh();
}

// builds a link to show the editor table
function getFgeLabel(rowIdx, item) {
    if (item) {
        return {
            id : this.grid.store.getValue(item, 'id'),
            label : this.grid.store.getValue(item, 'query_label')
        };
    }
}

function formatFgeLabel(args) {
    if (!args) return '';
    return '<a href="javascript:showFgeEditor(' + args.id + ')">' + args.label + '</a>';
}

// builds a link to this group's entries page
function getFgCode(rowIdx, item) {
    if (item) {
        return {
            id : this.grid.store.getValue(item, 'id'),
            code : this.grid.store.getValue(item, 'code')
        };
    }
}

function formatFgCode(args) {
    if (!args) return '';
    return '<a href="' + oilsBasePath + '/conify/global/actor/search_filter_group/' + args.id + '">' + args.code + '</a>';
}

function load() {

    if (filterGroupId) {

        // entries grid loads itself from template data.  
        // nothing for us to do.

    } else {

        // filter groups by where we have edit permission
        new openils.User().getPermOrgList(
            ['ADMIN_SEARCH_FILTER_GROUP'],
            function(list) { 
                fgGrid.query = {owner : list};
                fgGrid.refresh(); 
                fgGrid.suppressEditFields = ['id', 'create_date'];
            },
            false, true
        );
    }
}

openils.Util.addOnLoad(load);

