if(!dojo._hasResource["fieldmapper.Fieldmapper"]){
/* generate fieldmapper javascript classes.  This expects a global variable
	called 'fmclasses' to be fleshed with the classes we need to build */

	function FMEX(message) { this.message = message; }
	FMEX.toString = function() { return "FieldmapperException: " + this.message + "\n"; }


	dojo._hasResource["fieldmapper.Fieldmapper"] = true;
	dojo.provide("fieldmapper.Fieldmapper");

	dojo.declare( "fieldmapper.Fieldmapper", null, {

		constructor : function (initArray) {
			if (initArray) {
				if (dojo.isArray(initArray)) {
					this.a = initArray;
				} else {
					this.a = [];
				}
			}
		},

		_isfieldmapper : true,
		fm_classes : fmclasses,

		clone : function() {
			var obj = new this.constructor();

			for( var i in this.a ) {
				var thing = this.a[i];
				if(thing == null) continue;

				if( thing._isfieldmapper ) {
					obj.a[i] = thing.clone();
				} else {

					if(instanceOf(thing, Array)) {
						obj.a[i] = new Array();

						for( var j in thing ) {

							if( thing[j]._isfieldmapper )
								obj.a[i][j] = thing[j].clone();
							else
								obj.a[i][j] = thing[j];
						}
					} else {
						obj.a[i] = thing;
					}
				}
			}
			return obj;
		},

		isnew : function(n) { if(arguments.length == 1) this.a[0] =n; return this.a[0]; },
		ischanged : function(n) { if(arguments.length == 1) this.a[1] =n; return this.a[1]; },
		isdeleted : function(n) { if(arguments.length == 1) this.a[2] =n; return this.a[2]; }

	});

	for( var cl in fmclasses ) {
		dojo.provide( cl );
		dojo.declare( cl , fieldmapper.Fieldmapper, {
			constructor : function () {
				if (!this.a) this.a = [];
				this.classname = this.declaredClass;
				this._fields = fmclasses[this.classname];
				for( var pos = 0; pos <  this._fields.length; pos++ ) {
					var p = parseInt(pos) + 3;
					var f = this._fields[pos];
					this[f]=new Function('n', 'if(arguments.length==1)this.a['+p+']=n;return this.a['+p+'];');
				}
			}
		});

	}
}


