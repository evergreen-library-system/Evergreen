
function go() {

/* load the lib script */
load_lib('circ/circ_lib.js');
log_vars('circ_recurring_fines');

/** 
Set some sane defaults.  Valid values for result.recurringFinesLevel
are low, nornal, and high
*/
result.recurringFinesRule = "books";
result.recurringFinesLevel = 'normal';


return;

} go();
