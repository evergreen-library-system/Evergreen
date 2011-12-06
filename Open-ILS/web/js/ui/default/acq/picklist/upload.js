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
var vlAgent;

function init() {
    dojo.byId('acq-pl-upload-ses').value = openils.User.authtoken;

    new openils.widget.AutoFieldWidget({
        fmClass : 'acqpo',
        fmField : 'provider',
        orgLimitPerms : ['CREATE_PICKLIST', 'CREATE_PURCHASE_ORDER'],
        parentNode : dojo.byId('acq-pl-upload-provider'),
    }).build(
        function(w) { providerWidget = w }
    );

    new openils.widget.AutoFieldWidget({
        fmClass : 'acqpo',
        fmField : 'ordering_agency',
        orgLimitPerms : ['CREATE_PICKLIST', 'CREATE_PURCHASE_ORDER'],
        parentNode : dojo.byId('acq-pl-upload-agency'),
    }).build(
        function(w) { orderAgencyWidget = w }
    );

    vlAgent = new VLAgent();
    vlAgent.init();

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
                    acqSendUploadForm({picklist:items[0].id[0]});
                }
            }
        });
    } else {
        acqSendUploadForm({picklist:null});
    }
}

function acqSendUploadForm(args) {
    dojo.io.iframe.send({
        url: VANDELAY_URL,
        method: "post",
        handleAs: "html",
        form: dojo.byId('acq-pl-upload-form'),
        handle: function(data, ioArgs){
            acqHandlePostUpload(data.documentElement.textContent, args.picklist);
        }
    });
}


function acqHandlePostUpload(key, plId) {

    var args = {
        picklist : plId,
        provider : providerWidget.attr('value'),
        ordering_agency : orderAgencyWidget.attr('value'),
        create_po : acqPlUploadCreatePo.attr('value'),
        activate_po : acqPlUploadActivatePo.attr('value'),
        vandelay : vlAgent.values()
    };

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.process_upload_records'],
        {   async: true,
            params: [openils.User.authtoken, key, args],
            onresponse : function(r) {

                vlAgent.handleResponse(
                    openils.Util.readResponse(r),
                    function(resp, res) {

                        openils.Util.hide('acq-pl-upload-complete-pl');
                        openils.Util.hide('acq-pl-upload-complete-po');
                        openils.Util.hide('acq-pl-upload-complete-q');
                        openils.Util.hide('acq-pl-upload-progress-bar');
                        openils.Util.show('acq-pl-upload-complete');

                        if(res.picklist_url) {
                            openils.Util.show('acq-pl-upload-complete-pl');
                            dojo.byId('acq-pl-upload-complete-pl').setAttribute('href', res.picklist_url);
                        } 

                        if(res.po_url) {
                            openils.Util.show('acq-pl-upload-complete-po');
                            dojo.byId('acq-pl-upload-complete-po').setAttribute('href', res.po_url);
                        }

                        if (res.queue_url) {
                            link = dojo.byId('acq-pl-upload-complete-q');
                            openils.Util.show(link);
                            link.setAttribute('href', res.queue_url);
                            link.innerHTML = resp.queue.name();
                        }
                    }
                );
            },
        }
    );
}


openils.Util.addOnLoad(init);

