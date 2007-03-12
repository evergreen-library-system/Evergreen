/* ---------------------------------------------------------------------
	Set up the limits for the various profiles (aka permission groups).
	Values of -1 mean there is no limit 

	maxItemsOut			- the maximum number of items the user can have out
	fineThreshold		- the fine threshold. 
	overdueThreshold	- the overdue items threshold.
	maxHolds				- The maximum number of holds the user can have

	A user exceeds the fineThreshold and/or overdueThreshold if they are 
	equal to or exceed the threshold
	--------------------------------------------------------------------- */

var GROUP_CONFIG = {
	'Patron' : {
		maxItemsOut         : 50,
		fineThreshold       : 10,
		overdueThreshold    : 10,
		maxHolds            : -1
	},
}
