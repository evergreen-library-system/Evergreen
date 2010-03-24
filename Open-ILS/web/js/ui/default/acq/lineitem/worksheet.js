dojo.require("openils.Util");

function load() {
    fieldmapper.standardRequest(
        ["open-ils.acq", "open-ils.acq.lineitem.format"], {
            "params": [openils.User.authtoken, liId, "html"],
            "async": true,
            "oncomplete": function(r) {
                r = openils.Util.readResponse(r);
                var d = dojo.byId("acq-worksheet-contents");
                if (r.template_output())
                    d.innerHTML = r.template_output().data();
                else if (r.error_output())
                    d.innerHTML = r.error_output().data();
                else
                    d.innerHTML = localeStrings.LI_FORMAT_ERROR;
            }
        }
    );
}

openils.Util.addOnLoad(load);
