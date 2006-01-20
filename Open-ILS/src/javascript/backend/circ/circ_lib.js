
var __scratchKey = 0;
var __SCRATCH = {};
function scratchKey()		{ return '_' + __scratchKey++; };
function scratchPad(key)	{ return '__SCRATCH.'+ key; }
function getScratch(key)	{ return __SCRATCH[ key ]; }



/* -- Copy functions ----------------------------------------------------- */
try { 

	copy.fetchHold = function() {
		var key = scratchKey();
		copy.__OILS_FUNC_fetch_hold(scratchPad(key));
		var val = getScratch(key);
		return (val) ? val : null;
	}

} catch(E) { log_warn( "Copy function definitions failed: " + E ); }

