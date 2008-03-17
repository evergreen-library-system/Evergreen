<?php

// Open the Curl session
if (!$_POST['url'])
	exit;

$session = curl_init(($_POST['url']));


$postvars = file_get_contents('php://input');

// Don't return HTTP headers. Do return the contents of the call
curl_setopt($session, CURLOPT_HEADER, false);
curl_setopt($session, CURLOPT_RETURNTRANSFER, true);

// Make the call
$response = curl_exec($session);

//header("Content-Type: text/html; charset=utf-8");
header("Content-Type: application/xml;");

// expects a json response and filters it
echo "/*" . $response . "*/";
curl_close($session);

?>

