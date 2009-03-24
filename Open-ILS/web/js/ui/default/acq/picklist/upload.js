dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dijit.ProgressBar');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.ComboBox');
dojo.require('dijit.form.Button');
dojo.require("dojo.io.iframe");
dojo.require('openils.User');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.acq.Picklist');

var VANDELAY_URL = '/vandelay-upload';
var providerWidget;
var orderAgencyWidget;

function init() {
    dojo.byId('acq-pl-upload-ses').value = openils.User.authtoken;

    new openils.widget.AutoFieldWidget({
        fmClass : 'acqpo',
        fmField : 'provider',
        limitPerms : ['CREATE_PICKLIST'],
        parentNode : dojo.byId('acq-pl-upload-provider'),
    }).build(
        function(w) { providerWidget = w }
    );

    new openils.widget.AutoFieldWidget({
        fmClass : 'acqpo',
        fmField : 'ordering_agency',
        limitPerms : ['CREATE_PURCHASE_ORDER'],
        parentNode : dojo.byId('acq-pl-upload-agency'),
    }).build(
        function(w) { orderAgencyWidget = w }
    );

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.picklist.user.retrieve.atomic'],
        {   async: true,
            params: [openils.User.authtoken], 
            oncomplete : function(r) {
                var list = openils.Util.readResponse(r);
                acqPlUploadPlSelector.store = 
                    new dojo.data.ItemFileReadStore({data:acqpl.toStoreData(list)});
            }
        }
    );
}

function acqUploadRecords() {
    openils.Util.show('acq-pl-upload-progress');
    var picklist = acqPlUploadPlSelector.attr('value');
    if(picklist) {
        // ComboBox value is the display string.  find the actual picklist
        // and create a new one if necessary
        acqPlUploadPlSelector.store.fetch({
            query : {name:picklist}, 
            onComplete : function(items) {
                if(items.length == 0) {
                    // create a new picklist for these items
                    openils.acq.Picklist.create(
                        {name:picklist, org_unit: orderAgencyWidget.attr('value')},
                        function(plId) { acqSendUploadForm({picklist:plId}) }
                    );
                } else {
                    acqSendUploadForm({picklist:items[0].id});
                }
            }
        });
    } else {
        acqSendUploadForm({});
    }
}

function acqSendUploadForm(args) {
    dojo.io.iframe.send({
        url: VANDELAY_URL,
        method: "post",
        handleAs: "html",
        form: dojo.byId('acq-pl-upload-form'),
        content : {
            picklist : args.picklist,
            provider : providerWidget.attr('value'),
            ordering_agency : orderAgencyWidget.attr('value')
        },
        handle: function(data, ioArgs){
            acqHandlePostUpload(data.documentElement.textContent);
        }
    });
}


function acqHandlePostUpload(key) {
    openils.Util.hide('acq-pl-upload-progress');
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.process_upload_records'],
        {   async: true,
            params: [openils.User.authtoken, key],
            onresponse : function(r) {
                var resp = openils.Util.readResponse(r);
                if(resp.complete) {
                    if(resp.picklist) {
                        location.href = location.href + '/../view/' + resp.picklist.id();
                    } else {
                        location.href = location.href + '/../../po/view/' + resp.purchase_order.id;
                    }
                } else {
                    dojo.byId('acq-pl-upload-count').innerHTML = resp.count;
                }
            },
        }
    );
}


openils.Util.addOnLoad(init);

