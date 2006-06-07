
var __scratchKey = 0;
var __SCRATCH = {};
function scratchKey()		{ return '_' + __scratchKey++; };
function scratchPad(key)	{ return '__SCRATCH.'+ key; }
function getScratch(key)	{ return __SCRATCH[ key ]; }
function scratchClear()		{ for( var o in __SCRATCH ) __SCRATCH[o] = null; }



/* -- Copy functions ----------------------------------------------------- */
try {
	if( environment.copy ) {
		environment.copy.fetchHolds = function() {
			var key = scratchKey();
			environment.copy.__OILS_FUNC_fetch_hold(scratchPad(key));
			var val = getScratch(key);
			return (val) ? val : null;
		}
	} 
} catch(e) {}


/* note: returns false if the value is 'f' or 'F' ... */
function isTrue(d) {
	if(	d && 
			d != "0" && 
			d != "f" &&
			d != "F" )
			return true;
	return false;
}

