function CGI() {
	/* load up the url parameters */

	this._keys = new Array();
	this.data = new Object();

	var string = location.search.replace(/^\?/,"");

	var key = ""; 
	var value = "";
	var inkey = true;
	var invalue = false;

	for( var idx = 0; idx!= string.length; idx++ ) {

		var c = string.charAt(idx);

		if( c == "=" )	{
			invalue = true;
			inkey = false;
			continue;
		} 

		if(c == "&" || c == ";") {
			inkey = 1;
			invalue = 0;
			if( ! this.data[key] ) this.data[key] = [];
			this.data[key].push(decodeURIComponent(value));
			this._keys.push(key);
			key = ""; value = "";
			continue;
		}

		if(inkey) key += c;
		else if(invalue) value += c;
	}

	if( ! this.data[key] ) this.data[key] = [];
	this.data[key].push(decodeURIComponent(value));
	this._keys.push(key);
}

/* returns the value for the given param.  If there is only one value for the
   given param, it returns that value.  Otherwise it returns an array of values
 */
CGI.prototype.param = function(p) {
	if(this.data[p] == null) return null;
	if(this.data[p].length == 1)
		return this.data[p][0];
	return this.data[p];
}

/* returns an array of param names */
CGI.prototype.keys = function() {
	return this._keys;
}

/* debuggin method */
CGI.prototype.toString = function() {
	var string = "";
	var keys = this.keys();

	for( var k in keys ) {
		string += keys[k] + " : ";
		var params = this.param(keys[k]);

		for( var p in params ) {
			string +=  params[p] + " ";
		}
		string += "\n";
	}
	return string;
}


