<?php

header("Content-Type", "text/json");

$allItems = array(
	array('name'=>"Alabama", 'label'=>"<img src='images/Alabama.jpg'/>Alabama", 'abbreviation'=>"AL"),
	array('name'=>"Alaska", 'label'=>"Alaska", 'abbreviation'=>"AK"),
	array('name'=>"American Samoa", 'label'=>"American Samoa", 'abbreviation'=>"AS"),
	array('name'=>"Arizona", 'label'=>"Arizona", 'abbreviation'=>"AZ"),
	array('name'=>"Arkansas", 'label'=>"Arkansas", 'abbreviation'=>"AR"),
	array('name'=>"Armed Forces Europe", 'label'=>"Armed Forces Europe", 'abbreviation'=>"AE"),
	array('name'=>"Armed Forces Pacific", 'label'=>"Armed Forces Pacific", 'abbreviation'=>"AP"),
	array('name'=>"Armed Forces the Americas", 'label'=>"Armed Forces the Americas", 'abbreviation'=>"AA"),
	array('name'=>"California", 'label'=>"California", 'abbreviation'=>"CA"),
	array('name'=>"Colorado", 'label'=>"Colorado", 'abbreviation'=>"CO"),
	array('name'=>"Connecticut", 'label'=>"Connecticut", 'abbreviation'=>"CT"),
	array('name'=>"Delaware", 'label'=>"Delaware", 'abbreviation'=>"DE"),
	array('name'=>"District of Columbia", 'label'=>"District of Columbia", 'abbreviation'=>"DC"),
	array('name'=>"Federated States of Micronesia", 'label'=>"Federated States of Micronesia", 'abbreviation'=>"FM"),
	array('name'=>"Florida", 'label'=>"Florida", 'abbreviation'=>"FL"),
	array('name'=>"Georgia", 'label'=>"Georgia", 'abbreviation'=>"GA"),
	array('name'=>"Guam", 'label'=>"Guam", 'abbreviation'=>"GU"),
	array('name'=>"Hawaii", 'label'=>"Hawaii", 'abbreviation'=>"HI"),
	array('name'=>"Idaho", 'label'=>"Idaho", 'abbreviation'=>"ID"),
	array('name'=>"Illinois", 'label'=>"Illinois", 'abbreviation'=>"IL"),
	array('name'=>"Indiana", 'label'=>"Indiana", 'abbreviation'=>"IN"),
	array('name'=>"Iowa", 'label'=>"Iowa", 'abbreviation'=>"IA"),
	array('name'=>"Kansas", 'label'=>"Kansas", 'abbreviation'=>"KS"),
	array('name'=>"Kentucky", 'label'=>"Kentucky", 'abbreviation'=>"KY"),
	array('name'=>"Louisiana", 'label'=>"Louisiana", 'abbreviation'=>"LA"),
	array('name'=>"Maine", 'label'=>"Maine", 'abbreviation'=>"ME"),
	array('name'=>"Marshall Islands", 'label'=>"Marshall Islands", 'abbreviation'=>"MH"),
	array('name'=>"Maryland", 'label'=>"Maryland", 'abbreviation'=>"MD"),
	array('name'=>"Massachusetts", 'label'=>"Massachusetts", 'abbreviation'=>"MA"),
	array('name'=>"Michigan", 'label'=>"Michigan", 'abbreviation'=>"MI"),
	array('name'=>"Minnesota", 'label'=>"Minnesota", 'abbreviation'=>"MN"),
	array('name'=>"Mississippi", 'label'=>"Mississippi", 'abbreviation'=>"MS"),
	array('name'=>"Missouri", 'label'=>"Missouri", 'abbreviation'=>"MO"),
	array('name'=>"Montana", 'label'=>"Montana", 'abbreviation'=>"MT"),
	array('name'=>"Nebraska", 'label'=>"Nebraska", 'abbreviation'=>"NE"),
	array('name'=>"Nevada", 'label'=>"Nevada", 'abbreviation'=>"NV"),
	array('name'=>"New Hampshire", 'label'=>"New Hampshire", 'abbreviation'=>"NH"),
	array('name'=>"New Jersey", 'label'=>"New Jersey", 'abbreviation'=>"NJ"),
	array('name'=>"New Mexico", 'label'=>"New Mexico", 'abbreviation'=>"NM"),
	array('name'=>"New York", 'label'=>"New York", 'abbreviation'=>"NY"),
	array('name'=>"North Carolina", 'label'=>"North Carolina", 'abbreviation'=>"NC"),
	array('name'=>"North Dakota", 'label'=>"North Dakota", 'abbreviation'=>"ND"),
	array('name'=>"Northern Mariana Islands", 'label'=>"Northern Mariana Islands", 'abbreviation'=>"MP"),
	array('name'=>"Ohio", 'label'=>"Ohio", 'abbreviation'=>"OH"),
	array('name'=>"Oklahoma", 'label'=>"Oklahoma", 'abbreviation'=>"OK"),
	array('name'=>"Oregon", 'label'=>"Oregon", 'abbreviation'=>"OR"),
	array('name'=>"Pennsylvania", 'label'=>"Pennsylvania", 'abbreviation'=>"PA"),
	array('name'=>"Puerto Rico", 'label'=>"Puerto Rico", 'abbreviation'=>"PR"),
	array('name'=>"Rhode Island", 'label'=>"Rhode Island", 'abbreviation'=>"RI"),
	array('name'=>"South Carolina", 'label'=>"South Carolina", 'abbreviation'=>"SC"),
	array('name'=>"South Dakota", 'label'=>"South Dakota", 'abbreviation'=>"SD"),
	array('name'=>"Tennessee", 'label'=>"Tennessee", 'abbreviation'=>"TN"),
	array('name'=>"Texas", 'label'=>"Texas", 'abbreviation'=>"TX"),
	array('name'=>"Utah", 'label'=>"Utah", 'abbreviation'=>"UT"),
	array('name'=>"Vermont", 'label'=>"Vermont", 'abbreviation'=>"VT"),
	array('name'=> "Virgin Islands, U.S.", 'label'=>"Virgin Islands, U.S.", 'abbreviation'=>"VI"),
	array('name'=>"Virginia", 'label'=>"Virginia", 'abbreviation'=>"VA"),
	array('name'=>"Washington", 'label'=>"Washington", 'abbreviation'=>"WA"),
	array('name'=>"West Virginia", 'label'=>"West Virginia", 'abbreviation'=>"WV"),
	array('name'=>"Wisconsin", 'label'=>"Wisconsin", 'abbreviation'=>"WI"),
	array('name'=>"Wyoming", 'label'=>"Wyoming", 'abbreviation'=>"WY"),
//    array('id'=>, 'name'=>''),
);

$q = "";
if (array_key_exists("q", $_REQUEST)) {
	$q = $_REQUEST['q'];
}
if (strlen($q) && $q[strlen($q)-1]=="*") {
	$q = substr($q, 0, strlen($q)-1);
}
$ret = array();
foreach ($allItems as $item) {
	if (!$q || strpos(strtolower($item['name']), strtolower($q))===0) {
		$ret[] = $item;
	}
}

// Handle paging, if given.
if (array_key_exists("start", $_REQUEST)) {
	$ret = array_slice($ret, $_REQUEST['start']);
}
if (array_key_exists("count", $_REQUEST)) {
	$ret = array_slice($ret, 0, $_REQUEST['count']);
}

print '/*'.json_encode(array('items'=>$ret)).'*/';
