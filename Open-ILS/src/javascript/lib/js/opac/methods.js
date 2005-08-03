/* Methods are defined as service:method */

FETCH_MRCOUNT = "open-ils.search:open-ils.search.biblio.class.count"
if(isXUL()) FETCH_MRCOUNT += ".staff";

FETCH_MRIDS = "open-ils.search:open-ils.search.biblio.class"
if(isXUL()) FETCH_MRIDS += ".staff";

FETCH_MRMODS = "open-ils.search:open-ils.search.biblio.metarecord.mods_slim.retrieve";

FETCH_MR_COPY_COUNTS = "open-ils.search:open-ils.search.biblio.metarecord.copy_count"
if(isXUL()) FETCH_MR_COPY_COUNTS += ".staff";




