// initialize an API session
// XXX Are there any cases where checkSession does not suffice for this?
function startSession(vendor, callback) {
    console.log('starting ebook API session for ' + vendor);
    new OpenSRF.ClientSession('open-ils.ebook_api').request({
        method: 'open-ils.ebook_api.start_session',
        params: [ vendor, ou ],
        async: false, // XXX
        oncomplete: function(r) {
            var resp = r.recv();
            if (resp) {
                var ses = resp.content();
                dojo.cookie(vendor, ses, {path: '/'});
                return callback(vendor,ses);
            }
        }
    }).send();
}

// validate or initialize API session
// (check_session method will fallback to start_session if no session ID is provided)
function checkSession(vendor, callback) {
    var ses = dojo.cookie(vendor) || null;
    if (ses == null)
        return startSession(vendor,callback);
    console.log('checking ebook API session for ' + vendor);
    new OpenSRF.ClientSession('open-ils.ebook_api').request({
        method: 'open-ils.ebook_api.check_session',
        params: [ ses, vendor, ou ],
        async: false, // XXX
        oncomplete: function(r) {
            var resp = r.recv();
            if (resp) {
                var new_ses = resp.content();
                dojo.cookie(vendor, new_ses, {path: '/'});
                return callback(vendor,new_ses);
            }
        }
    }).send();
}
