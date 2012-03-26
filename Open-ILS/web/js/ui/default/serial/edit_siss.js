dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.Button');
dojo.require('dijit.form.FilteringSelect');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.EditPane');
dojo.require("openils.widget.HoldingCode");

dojo.requireLocalization('openils.serial', 'serial');
var localeStrings = dojo.i18n.getLocalization('openils.serial', 'serial');

// fresh_scap_selector needs these defined as globals XXX rework?
var pcrud;
var sub_id;

function drawSiss(siss_id, ssub_id) {
    var iss_grid = { overrideEditWidgets : {} };

    iss_grid.overrideEditWidgets.creator =
        new dijit.form.TextBox({"disabled": true});
    iss_grid.overrideEditWidgets.creator.shove = {
        "create": openils.User.user.id()
    };

    iss_grid.overrideEditWidgets.editor =
        new dijit.form.TextBox({
            "disabled": true, "value": openils.User.user.id()
        });

    iss_grid.overrideEditWidgets.holding_type =
        new dijit.form.TextBox({"disabled": true});

    var pane_args = {
        hideActionButtons : true,
        overrideWidgets : iss_grid.overrideEditWidgets
    }

    var button_label;
    pcrud = new openils.PermaCrud();
    if (siss_id == 'new') {
        sub_id = ssub_id;
        pane_args.fmClass = 'siss';
        pane_args.mode = 'create';
        pane_args.onPostSubmit = function(req, cudResults){
            //TODO: better success check
            alert(localeStrings.SAVE_SUCCESSFUL);
            //location.href = location.href.replace(/new\/.*/, cudResults[0].id());
            parent.document.getElementById(window.name).refresh_command();
        }
        button_label = localeStrings.CREATE_ISSUANCE;
    } else {
        pane_args.fmObject = pcrud.retrieve('siss', siss_id);
        pane_args.onPostSubmit = function(req, cudResults){
            //alert('req: '+req.toSource());
            //alert('cudResults: '+cudResults);
            //TODO: better success check
            alert(localeStrings.SAVE_SUCCESSFUL);
            parent.document.getElementById(window.name).refresh_command();
        }
        sub_id = pane_args.fmObject.subscription();
        button_label = localeStrings.MODIFY_ISSUANCE;
    }
    iss_grid.overrideEditWidgets.subscription =
        new dijit.form.TextBox({
            "disabled": true, "value": sub_id
        });
    fresh_scap_selector(iss_grid); // embed scap wizard into generated form

    var pane = new openils.widget.EditPane(
        pane_args, dojo.byId('edit-pane')
    );

    pane.fieldOrder = ['subscription','creator','editor','label','date_published','caption_and_pattern','holding_type'];
    pane.suppressFields = ['id', 'holding_link_id','create_date','edit_date'];
    pane.startup();

    var tbody = pane.table.getElementsByTagName('tbody')[0];
    var applySpan = document.createElement('span');
    tbody.appendChild(document.createElement('tr').appendChild(document.createElement('td').appendChild(applySpan)));
    new dijit.form.Button({
        label: button_label,
        onClick: function() {pane.performAutoEditAction();}
    }, applySpan);

}
