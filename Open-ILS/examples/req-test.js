load_lib('fmall.js');
load_lib('fmgen.js');
load_lib('jsonopensrfrequest.js');


var bc;
environment.result = [];

var req = new JSONOpenSRFRequest()

req.connect('open-ils.cstore');
req.call('open-ils.cstore.direct.actor.user.search.atomic');

req.send({ family_name : "arl-dan" },{flesh:1,flesh_fields:{au:['cards']}});
user = req.responseJSON[0].cards()[0].barcode();
log_debug(user);
environment.result.push(req.responseJSON);

req.send({ family_name : "arl-east" },{flesh:1,flesh_fields:{au:['cards']}});
user = req.responseJSON[0].cards()[0].barcode();
log_debug(user);
environment.result.push(req.responseJSON);

req.finish();

