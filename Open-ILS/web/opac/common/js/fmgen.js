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
Fieldmapper.prototype.isnew = function(n) { if(arguments.length == 1) this.a[0] =n; return this.a[0]; }
Fieldmapper.prototype.ischanged = function(n) { if(arguments.length == 1) this.a[1] =n; return this.a[1]; }
Fieldmapper.prototype.isdeleted = function(a) { if(arguments.length == 1) this.a[2] =n; return this.a[2]; }
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

	for( var pos in fmclasses[cl] ) {
		var p = parseInt(pos) + 3;
		var field = fmclasses[cl][pos];
		string += cl + ".prototype." + field + 
			"=function(n){if(arguments.length == 1)this.a[" + 
			p + "]=n;return this.a[" + p + "];};";
	}
}
eval(string);


