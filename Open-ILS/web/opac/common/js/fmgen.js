/* generate fieldmapper javascript classes.  This expects a global variable
	called 'fmclasses' to be fleshed with the classes we need to build */

function Fieldmapper() {}

var errorstr = "Attempt to build fieldmapper object with non-array";

Fieldmapper.prototype.clone = function() {
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
}

function FMEX(message) { this.message = message; }
FMEX.toString = function() { return "FieldmapperException: " + this.message + "\n"; }

var string = "";
for( var cl in fmclasses ) {
	string += cl + ".prototype = new Fieldmapper(); " + 
						cl + ".prototype.constructor = " + cl + ";" +
						cl + ".baseClass = Fieldmapper.constructor;" +
						"function " + cl + "(a) { " +
							"this.classname = \"" + cl + "\";" +
							"this._isfieldmapper = true;" +
							"if(a) { if(a.constructor == Array) this.a = a; else throw new FMEX(errorstr);} else this.a = []}"; 

	string += cl + "._isfieldmapper=true;";

	fmclasses[cl].push('isnew');
	fmclasses[cl].push('ischanged');
	fmclasses[cl].push('isdeleted');

	for( var pos in fmclasses[cl] ) {
		var p = parseInt(pos);
		var field = fmclasses[cl][pos];
		string += cl + ".prototype." + field + 
			"=function(n){if(arguments.length == 1)this.a[" + 
			p + "]=n;return this.a[" + p + "];};";
	}
}
eval(string);


