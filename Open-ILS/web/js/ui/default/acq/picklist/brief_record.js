dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dijit.form.Form');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.DateTextBox');
dojo.require('dijit.form.Button');
dojo.require('openils.User');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.MarcXPathParser');

function drawBriefRecordForm(fields) {

    var tbody = dojo.byId('acq-brief-record-tbody');
    var rowTmpl = dojo.byId('acq-brief-record-row');

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

                    dojo.forEach(attrs,
                        function(def) {
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

function compileBriefRecord(fields) {
    console.log(js2JSON(fields));
    return false;
}

openils.Util.addOnLoad(drawBriefRecordForm);
