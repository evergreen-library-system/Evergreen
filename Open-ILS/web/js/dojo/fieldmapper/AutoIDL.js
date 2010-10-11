if(!dojo._hasResource["fieldmapper.AutoIDL"]) {
    dojo.provide("fieldmapper.AutoIDL");
    dojo.require("fieldmapper.IDL");


    var classlist = [];
    try {
        classlist = dojo.config.AutoIDL || [];
    } catch(x) {
        /* meh */
    }

    fieldmapper.IDL.load(classlist);
}

