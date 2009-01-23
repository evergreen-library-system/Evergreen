if(!dojo._hasResource['openils.widget.AutoWidget']) {
    dojo.provide('openils.widget.AutoWidget');
    dojo.require('dojo.data.ItemFileWriteStore');
    dojo.require('fieldmapper.dojoData');
    dojo.require('fieldmapper.IDL');

    // common superclass to auto-generated UIs
    dojo.declare('openils.widget.AutoWidget', null, {

        fieldOrder : null, // ordered list of field names, optional.
        sortedFieldList : [], // holds the sorted IDL defs for our fields
        fmObject : null, // single fielmapper object
        fmObjectList : null, // list of fieldmapper objects
        fmClass : '', // our fieldmapper class

        // locates the relevent IDL info
        initAutoEnv : function() {
            if(this.fmObjectList && this.fmObjectList.length)
                this.fmClass = this.fmObjectList[0].classname;
            if(this.fmObject)
                this.fmClass = this.fmObject.classname;
            this.fmIDL = fieldmapper.IDL.fmclasses[this.fmClass];
            this.buildSortedFieldList();
        },

        buildAutoStore : function() {
            var list = [];
            if(this.fmObjectList) {
                list = this.fmObjectList;
            } else {
                if(this.fmObject)
                    list = [this.fmObject];
            }
            return new dojo.data.ItemFileWriteStore(
                {data:fieldmapper[this.fmClass].toStoreData(list)});
        },

        buildSortedFieldList : function() {
            this.sortedFieldList = [];

            if(this.fieldOrder) {

                for(var idx in this.fieldOrder) {
                    var name = this.fieldOrder[idx];
                    for(var idx2 in this.fmIDL.fields) {
                        if(this.fmIDL.fields[idx2].name == name) {
                            this.sortedFieldList.push(this.fmIDL.fields[idx2]);
                            break;
                        }
                    }
                }
                
                // if the user-defined order does not list all fields, 
                // shove the extras on the end.
                var anonFields = [];
                for(var idx in this.fmIDL.fields)  {
                    var name = this.fmIDL.fields[idx].name;
                    if(this.fieldOrder.indexOf(name) < 0) {
                        anonFields.push(this.fmIDL.fields[idx]);
                    }
                }

                anonFields = anonFields.sort(
                    function(a, b) {
                        if(a.label > b.label) return 1;
                        if(a.label < b.label) return -1;
                        return 0;
                    }
                );

                this.sortedFieldList = this.sortedFieldList.concat(anonFields);

            } else {
                // no sort order defined, sort all fields on display label

                for(var f in this.fmIDL.fields) 
                    this.sortedFieldList.push(this.fmIDL.fields[f]);
                this.sortedFieldList = this.sortedFieldList.sort(
                    // by default, sort on label
                    function(a, b) {
                        if(a.label > b.label) return 1;
                        if(a.label < b.label) return -1;
                        return 0;
                    }
                );
            } 
        },
    });
}

