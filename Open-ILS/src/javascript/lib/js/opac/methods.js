/* Methods are defined as service:method */

var FETCH_MRCOUNT = "open-ils.search:open-ils.search.biblio.class.count";
if(isXUL()) FETCH_MRCOUNT += ".staff";

var FETCH_MRIDS = "open-ils.search:open-ils.search.biblio.class";
if(isXUL()) FETCH_MRIDS += ".staff";

var FETCH_MRMODS = "open-ils.search:open-ils.search.biblio.metarecord.mods_slim.retrieve";

var FETCH_MR_COPY_COUNTS = "open-ils.search:open-ils.search.biblio.metarecord.copy_count";
if(isXUL()) FETCH_MR_COPY_COUNTS += ".staff";

var FETCH_FLESHED_USER = "open-ils.actor:open-ils.actor.user.fleshed.retrieve";

var LOGIN_INIT 		= "open-ils.auth:open-ils.auth.authenticate.init";
var LOGIN_COMPLETE 	= "open-ils.auth:open-ils.auth.authenticate.complete";


