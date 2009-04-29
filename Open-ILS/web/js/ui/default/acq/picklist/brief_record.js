dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dijit.form.Form');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.DateTextBox');
dojo.require('dijit.form.Button');
dojo.require('dijit.form.ComboBox');
dojo.require('openils.User');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.MarcXPathParser');
dojo.require('openils.acq.Picklist');
dojo.require('openils.CGI');

var attrDefs = {};
var paramPL = null;
var paramPO = null;

function drawBriefRecordForm(fields) {

    var tbody = dojo.byId('acq-brief-record-tbody');
    var rowTmpl = dojo.byId('acq-brief-record-row');
    var cgi = new openils.CGI();
    paramPL = cgi.param('pl');
    paramPO = cgi.param('po');


    if(paramPL) {
        openils.Util.hide('acq-brief-record-po-row');

        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.picklist.retrieve'],
            {   async: true,
                params: [openils.User.authtoken, paramPL], 
                oncomplete : function(r) {
                    var pl = openils.Util.readResponse(r);
                    plSelector.store = 
                        new dojo.data.ItemFileReadStore({data:acqpl.toStoreData([pl])});
                    plSelector.attr('value', pl.name());
                    plSelector.attr('disabled', true);
                }
            }
        );

    } else {

        if(paramPO) {
            openils.Util.hide('acq-brief-record-pl-row');
            poNumber.attr('value', paramPO);

        } else {
            openils.Util.hide('acq-brief-record-po-row');
            fieldmapper.standardRequest(
                ['open-ils.acq', 'open-ils.acq.picklist.user.retrieve.atomic'],
                {   async: true,
                    params: [openils.User.authtoken], 
                    oncomplete : function(r) {
                        var list = openils.Util.readResponse(r);
                        plSelector.store = 
                            new dojo.data.ItemFileReadStore({data:acqpl.toStoreData(list)});
                    }
                }
            );
        }
    }


    marcEditButton.onClick = function(fields) {
        saveBriefRecord(fields, true);
    }

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.lineitem_attr_definition.retrieve.all'],
        {   async : true,
            params : [openils.User.authtoken],

            oncomplete : function(r) {
                var attrs = openils.Util.readResponse(r);
                if(attrs && attrs.marc) {

                    attrs = attrs.marc.sort(
                        function(a, b) {
                            if(a.description < b.description)
                                return 1;
                            return -1;
                        }
                    );

                    var xpathParser = new openils.MarcXPathParser();
                    dojo.forEach(attrs,
                        function(def) {
                            attrDefs[def.code()] = xpathParser.parse(def.xpath());
                            var row = rowTmpl.cloneNode(true);
                            dojo.query('[name=name]', row)[0].innerHTML = def.description();
                            new dijit.form.TextBox({name : def.code()}, dojo.query('[name=widget]', row)[0]);
                            tbody.appendChild(row);
                        }
                    );
                }
            }
        }
    );
}

function saveBriefRecord(fields, editMarc) {

    if(paramPL) {
        fields.picklist = paramPL;
        delete fields.po;
        compileBriefRecord(fields, editMarc);
        return false;
    }

    if(paramPO) {
        fields.po = paramPO;
        delete fields.picklist;
        compileBriefRecord(fields, editMarc);
        return false;
    }

    // first, deal with the selection list
    var picklist = plSelector.attr('value');

    if(!picklist) {
        compileBriefRecord(fields, editMarc);
        return false;
    }

    // ComboBox value is the display string.  find the actual picklist
    // and create a new one if necessary
    plSelector.store.fetch({
        query : {name:picklist}, 

        onComplete : function(items) {
            if(items.length == 0) {
                
                // create a new picklist for these items
                openils.acq.Picklist.create(
                    {name:picklist, org_unit: openils.User.user.ws_ou()},
                    function(plId) { 
                        fields.picklist = plId;
                        compileBriefRecord(fields, editMarc);
                    }
                );

            } else {
                var id = plSelector.store.getValue(items[0], 'id');
                fields.picklist = id;
                compileBriefRecord(fields, editMarc);
            }
        }
    });

    return false;
}

function compileBriefRecord(fields, editMarc) {

    var baseString = '<record xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
        'xmlns="http://www.loc.gov/MARC21/slim" ' +
        'xmlns:marc="http://www.loc.gov/MARC21/slim" ' +
        'xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/ standards/marcxml/schema/MARC21slim.xsd">' +
        '<leader/></record>';

    var doc = new DOMParser().parseFromString(baseString, 'text/xml');

    for(var f in fields) {

        var def = attrDefs[f];
        if(!def) continue;
        var value = fields[f];
        if(!value) continue;

        var dfNode = doc.createElementNS('http://www.loc.gov/MARC21/slim', 'marc:datafield');
        var sfNode = doc.createElementNS('http://www.loc.gov/MARC21/slim', 'marc:subfield');
        
        // creates tags and fields in the document.  If there are more than one
        // option for the tag or code, use the first in the list
        dfNode.setAttribute('tag', ''+def.tags[0]);
        dfNode.setAttribute('ind1', ' ');
        dfNode.setAttribute('ind2', ' ');
        sfNode.setAttribute('code', ''+def.subfields[0]);
        tNode = doc.createTextNode(value);

        sfNode.appendChild(tNode);
        dfNode.appendChild(sfNode);
        doc.documentElement.appendChild(dfNode);
    }
    

    var xmlString = new XMLSerializer().serializeToString(doc);

    var li = new fieldmapper.jub();
    li.marc(xmlString);
    li.picklist(fields.picklist);
    if(fields.po) li.purchase_order(fields.po);
    li.selector(openils.User.user.id());
    li.creator(openils.User.user.id());
    li.editor(openils.User.user.id());

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.lineitem.create'],
        {   async : true,
            params : [openils.User.authtoken, li],
            oncomplete : function(r) {
                var id = openils.Util.readResponse(r);
                if(!id) return;
                if(editMarc) {
                    // XXX load marc editor
                } else {
                    if(fields.picklist) 
                        location.href = oilsBasePath + '/acq/picklist/view/' + fields.picklist;
                    else
                        location.href = oilsBasePath + '/acq/po/view/' + fields.po;
                }
            }
        }
    );

    return false;
}

openils.Util.addOnLoad(drawBriefRecordForm);
