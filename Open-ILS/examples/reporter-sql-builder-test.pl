#!/usr/bin/perl
#use diagnostics;
use warnings;
use strict;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Reporter::SQLBuilder;
use OpenSRF::Utils::JSON;

my $idl = 'fm_IDL.xml';
Fieldmapper->import(IDL => $idl);

# just to show a deep-ish join tree and several params
my $report = <<REPORT;
{
	select => [
		{	relation=> 'circ',
			column	=> { transform => month_trunc => colname => 'checkin_time' },
			alias	=> '::PARAM4',
		},
		{	relation=> 'circ-checkin_lib-aou',
			column	=> { colname => 'shortname', transform => 'Bare'},
			alias	=> 'Library Short Name',
		},
		{	relation=> 'circ-circ_staff-au-card-ac',
			column	=> 'barcode',
			alias	=> 'User Barcode',
		},
		{	relation=> 'circ-id-mb',
			column	=> { transform => sum => colname => 'amount' },
			alias	=> '::PARAM3',
		},
	],
	from => {
		table	=> 'action.circulation',
		alias	=> 'circ',
		join	=> {
			checkin_staff => {
				table	=> 'actor.usr',
				alias	=> 'circ-circ_staff-au',
				type	=> 'inner',
				key	=> 'id',
				join	=> {
					card => {
						table	=> 'actor.card',
						alias	=> 'circ-circ_staff-au-card-ac',
						type	=> 'inner',
						key	=> 'id',
					},
				},
			},
			checkin_lib => {
				table	=> 'actor.org_unit',
				alias	=> 'circ-checkin_lib-aou',
				type	=> 'inner',
				key	=> 'id',
			},
			'id-billings' => {
				table	=> 'money.billing',
				alias	=> 'circ-id-mb',
				type	=> 'left',
				key	=> 'xact',
			},
		},
	},
	where => [
		{	relation	=> 'circ-checkin_lib-aou',
			column		=> 'id',
			condition	=> { 'in' => '::PARAM1' },
		},
		{	relation	=> 'circ',
			column		=> { transform => month_trunc => colname => 'checkin_time' },
			condition	=> { 'in' => '::PARAM2' },
		},
		{	relation	=> 'circ-id-mb',
			column		=> 'voided',
			condition	=> { '=' => '::PARAM7' },
		},
	],
	having => [],
	order_by => [
		{	relation=> 'circ-checkin_lib-aou',
			column	=> { colname => 'shortname', transform => 'Bare' },
		},
		{	relation=> 'circ',
			column	=> { transform => month_trunc => colname => 'checkin_time' },
			direction => 'descending'
		},
		{	relation=> 'circ-circ_staff-au-card-ac',
			column	=> 'barcode',
		},
	],
	pivot_default => 0,
	pivot_data => 4,
	pivot_label => 2,
};
REPORT
my $params = <<PARAMS;
{
	PARAM1 => [ 18, 19, 20, 21, 22, 23 ],
	PARAM2 => [{transform => 'relative_month', params => [-2]},{transform => 'relative_month', params => [-3]}],
	PARAM3 => 'Billed Amount',
	PARAM4 => 'Checkin Date',
	PARAM5 => [{ transform => 'Bare', params => [10] },{ transform => 'Bare', params => [100] }],
	PARAM6 => [ 1, 4 ],
	PARAM7 => 'f',
}
PARAMS


# Survey response counts
$report = '{"select":[{"relation":"b312819df8fe889b50f70ea9fa054e72","path":"au-home_ou-aou-shortname","alias":"ILS User:Home Library:Short (Policy) Name","column":{"transform":"Bare","colname":"shortname"}},{"relation":"80bfa74cd4909b585f6187fe8f8591c5","path":"au-survey_responses-asvr-survey-asv-name","alias":"ILS User:Survey Responses:survey:name","column":{"transform":"Bare","colname":"name"}},{"relation":"8a6cb366f41b2b8186df7c7749ff41ba","path":"au-survey_responses-asvr-answer-asva-answer","alias":"ILS User:Survey Responses:answer:Answer Text","column":{"transform":"Bare","colname":"answer"}},{"relation":"8bcc25c96aa5a71f7a76309077753e67","path":"au-id","alias":"count","column":{"transform":"count","colname":"id"}}],"from":{"table":"actor.usr","path":"au","alias":"8bcc25c96aa5a71f7a76309077753e67","join":{"id-survey_responses":{"key":"usr","type":"left","table":"action.survey_response","path":"au-survey_responses-asvr","alias":"cab1b47d26fa649f9a795d191bac0642","join":{"survey":{"key":"id","table":"action.survey","path":"au-survey_responses-asvr-survey-asv","alias":"80bfa74cd4909b585f6187fe8f8591c5"},"answer":{"key":"id","table":"action.survey_answer","path":"au-survey_responses-asvr-answer-asva","alias":"8a6cb366f41b2b8186df7c7749ff41ba"}}},"home_ou":{"key":"id","table":"actor.org_unit","path":"au-home_ou-aou","alias":"b312819df8fe889b50f70ea9fa054e72"}}},"where":[{"relation":"80bfa74cd4909b585f6187fe8f8591c5","path":"au-survey_responses-asvr-survey-asv-id","column":{"transform":"Bare","colname":"id"},"condition":{"in":"::P0"}},{"relation":"b312819df8fe889b50f70ea9fa054e72","path":"au-home_ou-aou-id","column":{"transform":"Bare","colname":"id"},"condition":{"in":"::P1"}}],"having":[],"order_by":[]}';
$params = '{"P0":["1"],"P1":["1","17","18","20","19","22","24","25","27","21","29","26","28","23","30","226","227","229","230","228","221","222","130","131","132","231","232","233","234","235","223","224","225","135","137","136","138","139","140","141","277","280","279","283","281","282","284","278","133","134","262","263","265","266","264","268","267","43","44","45","46","47","48","285","286","287","296","288","289","299","290","291","292","293","294","295","298","297","300","301","302","31","32","33","34","41","42","121","122","123","125","129","126","124","127","128","168","169","170","171","172","173","194","195","151","154","155","152","153","164","165","167","166","236","237","238","240","239","269","270","271","272","273","274","275","276","118","119","120","243","251","256","244","245","246","247","248","249","250","252","253","255","257","254","258","259","260","261","10","12","11","13","15","14","16","108","109","110","111","112","113","241","242","156","157","158","160","162","163","159","161","303","304","307","306","305","308","310","309","311","207","211","208","209","210","88","89","91","90","212","213","218","215","214","217","216","219","220","70","72","71","74","73","75","76","77","114","115","116","117","196","197","201","199","200","204","202","203","206","198","205","100","101","102","103","104","105","106","107","68","69","98","99","35","38","37","36","39","40","142","143","144","145","146","147","148","149","150","92","93","94","95","96","97","188","189","190","191","192","193","61","62","67","63","64","65","66","78","79","80","81","82","85","84","86","83","87","58","59","60","49","56","50","51","52","54","53","55","57","174","182","175","177","179","180","183","181","184","185","186","187","176","178"]}';


# template format v2, left join, having count = 0
$report = '{"version":2,"core_class":"acp","select":[{"alias":"Short (Policy) Name","column":{"colname":"shortname","transform":"Bare","transform_label":"Raw Data"},"path":"acp-circ_lib-aou-shortname","relation":"ab9ff91ac334900edb50f0a5a8e3501f"},{"alias":"Barcode","column":{"colname":"barcode","transform":"Bare","transform_label":"Raw Data"},"path":"acp-barcode","relation":"7d74f3b92b19da5e606d737d339a9679"},{"alias":"Circ ID","column":{"colname":"id","transform":"count","transform_label":"Count"},"path":"acp-circulations-circ-id","relation":"ddeeaf1839fe1496b309babab563fea7"}],"from":{"path":"acp-circ_lib","table":"asset.copy","label":"Item","alias":"7d74f3b92b19da5e606d737d339a9679","idlclass":"acp","template_path":"acp","join":{"id-circ-target_copy-7d74f3b92b19da5e606d737d339a9679":{"path":"acp-circulations-circ","table":"action.circulation","key":"target_copy","type":"left","label":"Item :: Circulations","alias":"ddeeaf1839fe1496b309babab563fea7","idlclass":"circ","template_path":"acp-circulations"},"circ_lib-7d74f3b92b19da5e606d737d339a9679":{"path":"acp-circ_lib-aou","table":"actor.org_unit","key":"id","label":"Item :: Circulating Library","alias":"ab9ff91ac334900edb50f0a5a8e3501f","idlclass":"aou","template_path":"acp-circ_lib"}}},"where":[{"alias":"Circulating Library","column":{"colname":"circ_lib","transform":"Bare","transform_label":"Raw Data"},"path":"acp-circ_lib","relation":"7d74f3b92b19da5e606d737d339a9679","condition":{"in":"::P0"}},{"alias":"Check Out Date/Time","column":{"colname":"xact_start","transform":"Bare","transform_label":"Raw Data"},"path":"acp-circulations-circ-xact_start","relation":"ddeeaf1839fe1496b309babab563fea7","condition":{"between":"::P1"}}],"having":[{"alias":"Circ ID","column":{"colname":"id","transform":"count","transform_label":"Count"},"path":"acp-circulations-circ-id","relation":"ddeeaf1839fe1496b309babab563fea7","condition":{"=":"0"}}],"order_by":[],"rel_cache":{"7d74f3b92b19da5e606d737d339a9679":{"label":"Item","alias":"7d74f3b92b19da5e606d737d339a9679","path":"acp","reltype":"","idlclass":"acp","table":"asset.copy","fields":{"dis_tab":{"barcode":{"colname":"barcode","transform":"Bare","transform_label":"Raw Data","alias":"Barcode","datatype":"text","op":"=","op_label":"Equals","op_value":{}}},"filter_tab":{"circ_lib":{"colname":"circ_lib","transform":"Bare","transform_label":"Raw Data","alias":"Circulating Library","datatype":"org_unit","op":"in","op_label":"In list","op_value":{}}},"aggfilter_tab":{}}},"order_by":[{"relation":"ab9ff91ac334900edb50f0a5a8e3501f","field":"shortname"},{"relation":"7d74f3b92b19da5e606d737d339a9679","field":"barcode"},{"relation":"ddeeaf1839fe1496b309babab563fea7","field":"id"}],"ddeeaf1839fe1496b309babab563fea7":{"label":"Item :: Circulations","alias":"ddeeaf1839fe1496b309babab563fea7","path":"acp-circulations","reltype":"has_many","idlclass":"circ","table":"action.circulation","fields":{"dis_tab":{"id":{"colname":"id","transform":"count","aggregate":"true","params":"undefined","transform_label":"Count","alias":"Circ ID","datatype":"id","op":"=","op_label":"Equals","op_value":{}}},"filter_tab":{"xact_start":{"colname":"xact_start","transform":"Bare","aggregate":"undefined","params":"undefined","transform_label":"Raw Data","alias":"Check Out Date/Time","datatype":"timestamp","op":"between","op_label":"Between","op_value":{}}},"aggfilter_tab":{"id":{"colname":"id","transform":"count","aggregate":"true","params":"undefined","transform_label":"Count","alias":"Circ ID","datatype":"id","op":"=","op_label":"Equals","op_value":{"value":"0","label":"\"0\""}}}}},"ab9ff91ac334900edb50f0a5a8e3501f":{"label":"Item :: Circulating Library","alias":"ab9ff91ac334900edb50f0a5a8e3501f","path":"acp-circ_lib","reltype":"has_a","idlclass":"aou","table":"actor.org_unit","fields":{"dis_tab":{"shortname":{"colname":"shortname","transform":"Bare","transform_label":"Raw Data","alias":"Short (Policy) Name","datatype":"text","op":"=","op_label":"Equals","op_value":{}}},"filter_tab":{},"aggfilter_tab":{}}}}}'; 
$params = '{"P0":["2"],"P1":["2008-06-01","now"],"__pivot_label":"","__pivot_data":"3"}';

$report = '{"simple_report":{"name":"User List with expiry filter","fmClass":"au","displayFields":[{"name":"id","label":"User ID","selector":"usrname","datatype":"id","path":[{"expanded":true,"stateFlag":true,"stateFlagLabel":null,"depth":0,"selected":false,"id":"au","label":"ILS User","callerData":{"fmClass":"au"}}],"treeNodeId":"au.id","transform":{"name":"Bare","simple":true,"aggregate":false},"operator":{"name":"=","datatypes":["link","text","timestamp","interval","float","int","money","number","id"],"arity":1},"path_label":"ILS User [Required] -> User ID","alias":"User ID"},{"name":"family_name","label":"Last Name","datatype":"text","path":[{"expanded":true,"stateFlag":true,"stateFlagLabel":null,"depth":0,"selected":false,"id":"au","label":"ILS User","callerData":{"fmClass":"au"}}],"treeNodeId":"au.family_name","transform":{"name":"Bare","simple":true,"aggregate":false},"operator":{"name":"=","datatypes":["link","text","timestamp","interval","float","int","money","number","id"],"arity":1},"path_label":"ILS User [Required] -> Last Name","alias":"Last Name"},{"name":"first_given_name","label":"First Name","datatype":"text","path":[{"expanded":true,"stateFlag":true,"stateFlagLabel":null,"depth":0,"selected":false,"id":"au","label":"ILS User","callerData":{"fmClass":"au"}}],"treeNodeId":"au.first_given_name","transform":{"name":"Bare","simple":true,"aggregate":false},"operator":{"name":"=","datatypes":["link","text","timestamp","interval","float","int","money","number","id"],"arity":1},"path_label":"ILS User [Required] -> First Name","alias":"First Name"},{"name":"expire_date","label":"Privilege Expiration Date","datatype":"timestamp","path":[{"expanded":true,"stateFlag":true,"stateFlagLabel":null,"depth":0,"selected":false,"id":"au","label":"ILS User","callerData":{"fmClass":"au"}}],"treeNodeId":"au.expire_date","transform":{"name":"date_trunc","simple":true,"relative_time_input_transform":"relative_date","aggregate":false,"final_datatype":"text","datatypes":["timestamp"],"regex":{},"hint":"YYYY-MM-DD","cal_format":"%Y-%m-%d","input_size":10,"relativeTransform":false},"operator":{"name":"=","datatypes":["link","text","timestamp","interval","float","int","money","number","id"],"arity":1},"path_label":"ILS User [Required] -> Privilege Expiration Date","alias":"Privilege Expiration Date","filter_value":null}],"orderByNames":["au.expire_date","au.id","au.family_name","au.first_given_name"],"filterFields":[{"name":"deleted","label":"Is Deleted","datatype":"bool","path":[{"expanded":true,"stateFlag":true,"stateFlagLabel":null,"depth":0,"selected":false,"id":"au","label":"ILS User","callerData":{"fmClass":"au"}}],"treeNodeId":"au.deleted","transform":{"name":"Bare","simple":true,"aggregate":false},"operator":{"arity":1,"datatypes":["bool","org_unit"],"name":"= any"},"path_label":"ILS User [Required] -> Is Deleted","with_value_input":true,"filter_value":"{f}","filter_placeholder":null},{"name":"expire_date","label":"Privilege Expiration Date","datatype":"timestamp","path":[{"expanded":true,"stateFlag":true,"stateFlagLabel":null,"depth":0,"selected":false,"id":"au","label":"ILS User","callerData":{"fmClass":"au"}}],"treeNodeId":"au.expire_date","transform":{"name":"date_trunc","simple":true,"relative_time_input_transform":"relative_date","aggregate":false,"final_datatype":"text","datatypes":["timestamp"],"regex":{},"hint":"YYYY-MM-DD","cal_format":"%Y-%m-%d","input_size":10,"relativeTransform":false},"operator":{"name":"=","datatypes":["link","text","timestamp","interval","float","int","money","number","id"],"arity":1},"path_label":"ILS User [Required] -> Privilege Expiration Date","filter_value":null,"filter_placeholder":"P0"}]},"version":6,"doc_url":"","core_class":"au","from":{"alias":"8bcc25c96aa5a71f7a76309077753e67","path":"au-au","table":"actor.usr","idlclass":"au","label":"ILS User","join":{}},"select":[{"alias":"User ID","path":"au.id","relation":"8bcc25c96aa5a71f7a76309077753e67","column":{"colname":"id","transform":"Bare","aggregate":false}},{"alias":"Last Name","path":"au.family_name","relation":"8bcc25c96aa5a71f7a76309077753e67","column":{"colname":"family_name","transform":"Bare","aggregate":false}},{"alias":"First Name","path":"au.first_given_name","relation":"8bcc25c96aa5a71f7a76309077753e67","column":{"colname":"first_given_name","transform":"Bare","aggregate":false}},{"alias":"Privilege Expiration Date","path":"au.expire_date","relation":"8bcc25c96aa5a71f7a76309077753e67","column":{"colname":"expire_date","transform":"date_trunc","aggregate":false}}],"where":[{"path":"au-deleted","relation":"8bcc25c96aa5a71f7a76309077753e67","column":{"colname":"deleted","transform":"Bare","aggregate":false},"condition":{"= any":"{f}"}},{"path":"au-expire_date","relation":"8bcc25c96aa5a71f7a76309077753e67","column":{"colname":"expire_date","transform":"date_trunc","aggregate":false},"condition":{"=":"::P0"}}],"having":[],"order_by":[{"alias":"Privilege Expiration Date","path":"au-expire_date","relation":"8bcc25c96aa5a71f7a76309077753e67","direction":"ascending","column":{"colname":"expire_date","transform":"date_trunc","aggregate":false}},{"alias":"User ID","path":"au-id","relation":"8bcc25c96aa5a71f7a76309077753e67","direction":"ascending","column":{"colname":"id","transform":"Bare","aggregate":false}},{"alias":"Last Name","path":"au-family_name","relation":"8bcc25c96aa5a71f7a76309077753e67","direction":"ascending","column":{"colname":"family_name","transform":"Bare","aggregate":false}},{"alias":"First Name","path":"au-first_given_name","relation":"8bcc25c96aa5a71f7a76309077753e67","direction":"ascending","column":{"colname":"first_given_name","transform":"Bare","aggregate":false}}],"relations":{"8bcc25c96aa5a71f7a76309077753e67":{"alias":"8bcc25c96aa5a71f7a76309077753e67","path":"au-au","table":"actor.usr","idlclass":"au","label":"ILS User","join":{}}}}';
$params = '{"__pivot_label":"","__pivot_data":0,"__do_rollup":0,"P0":{"transform":"relative_date","params":[30]}}';

$report = '{"simple_report":{"name":"circ count per user per day, no filter","fmClass":"circ","displayFields":[{"name":"xact_start","label":"Checkout Date/Time","datatype":"timestamp","path":[{"expanded":true,"stateFlag":true,"stateFlagLabel":null,"depth":0,"selected":false,"id":"circ","label":"Circulation","callerData":{"fmClass":"circ"}}],"treeNodeId":"circ.xact_start","transform":{"name":"date_trunc","simple":true,"relative_time_input_transform":"relative_date","aggregate":false,"final_datatype":"timestamp","datatypes":["timestamp"],"regex":{},"hint":"YYYY-MM-DD","cal_format":"%Y-%m-%d","input_size":10},"operator":{"name":"=","datatypes":["link","text","timestamp","interval","float","int","money","number","id"],"arity":1},"path_label":"Circulation [Required] -> Checkout Date/Time","alias":"Checkout Date/Time"},{"name":"usrname","label":"OPAC/Staff Client Username","datatype":"text","path":[{"expanded":true,"stateFlag":true,"stateFlagLabel":null,"depth":0,"selected":false,"id":"circ","label":"Circulation","callerData":{"fmClass":"circ"}},{"expanded":false,"stateFlag":false,"stateFlagLabel":"Require INNER join between Circulation and Patron?","depth":1,"selected":true,"id":"circ.usr:id@au","label":"Patron","callerData":{"parent_id":"circ","fmClass":"au","fmField":{"key":"id","name":"usr","reltype":"has_a","class":"au"}}}],"treeNodeId":"circ.usr:id@au.usrname","transform":{"name":"Bare","simple":true,"aggregate":false},"operator":{"name":"=","datatypes":["link","text","timestamp","interval","float","int","money","number","id"],"arity":1},"path_label":"Circulation [Required] -> Patron -> OPAC/Staff Client Username","alias":"OPAC/Staff Client Username"},{"name":"name","label":"Group Name","i18n":true,"datatype":"text","path":[{"expanded":true,"stateFlag":true,"stateFlagLabel":null,"depth":0,"selected":false,"id":"circ","label":"Circulation","callerData":{"fmClass":"circ"}},{"expanded":true,"stateFlag":false,"stateFlagLabel":"Require INNER join between Circulation and Patron?","depth":1,"selected":false,"id":"circ.usr:id@au","label":"Patron","callerData":{"parent_id":"circ","fmClass":"au","fmField":{"key":"id","name":"usr","reltype":"has_a","class":"au"}}},{"expanded":false,"stateFlag":true,"stateFlagLabel":"Require INNER join between Patron and Main (Profile) Permission Group?","depth":2,"selected":true,"id":"circ.usr:id@au.profile:id@pgt","label":"Main (Profile) Permission Group","callerData":{"parent_id":"circ.usr:id@au","fmClass":"pgt","fmField":{"key":"id","name":"profile","reltype":"has_a","class":"pgt"}}}],"treeNodeId":"circ.usr:id@au.profile:id@pgt.name","transform":{"name":"Bare","simple":true,"aggregate":false},"operator":{"name":"=","datatypes":["link","text","timestamp","interval","float","int","money","number","id"],"arity":1},"path_label":"Circulation [Required] -> Patron -> Main (Profile) Permission Group [Required] -> Group Name","alias":"Group Name"},{"name":"id","label":"Circ ID","datatype":"id","path":[{"expanded":true,"stateFlag":true,"stateFlagLabel":null,"depth":0,"selected":false,"id":"circ","label":"Circulation","callerData":{"fmClass":"circ"}}],"treeNodeId":"circ.id","transform":{"name":"count_distinct","simple":true,"final_datatype":"number","aggregate":true},"operator":{"name":"=","datatypes":["link","text","timestamp","interval","float","int","money","number","id"],"arity":1},"path_label":"Circulation [Required] -> Circ ID","alias":"circs","filter_value":null,"direction":"descending"}],"orderByNames":["circ.id","circ.xact_start","circ.usr:id@au.usrname","circ.usr:id@au.profile:id@pgt.name"],"filterFields":[]},"version":7,"doc_url":"","core_class":"circ","from":{"alias":"fce458da5814089639960610c48d19d2","path":"circ-circ","table":"action.circulation","idlclass":"circ","label":"Circulation","join":{"usr-3247d2a4a42dd2607c6677083a8f7e4e":{"type":"left","key":"id","alias":"3247d2a4a42dd2607c6677083a8f7e4e","idlclass":"au","label":"Circulation [Required] -> Patron -> OPAC/Staff Client Username","table":"actor.usr","join":{"profile-ab5aeec88729d5ccd466b711d329b838":{"type":"inner","key":"id","alias":"ab5aeec88729d5ccd466b711d329b838","idlclass":"pgt","label":"Circulation [Required] -> Patron -> Main (Profile) Permission Group [Required] -> Group Name","table":"permission.grp_tree"}}}}},"select":[{"alias":"Checkout Date/Time","path":"circ.xact_start","relation":"fce458da5814089639960610c48d19d2","column":{"colname":"xact_start","transform":"date_trunc","aggregate":false}},{"alias":"OPAC/Staff Client Username","path":"circ.usr:id@au.usrname","relation":"3247d2a4a42dd2607c6677083a8f7e4e","column":{"colname":"usrname","transform":"Bare","aggregate":false}},{"alias":"Group Name","path":"circ.usr:id@au.profile:id@pgt.name","relation":"ab5aeec88729d5ccd466b711d329b838","column":{"colname":"name","transform":"Bare","aggregate":false}},{"alias":"circs","path":"circ.id","relation":"fce458da5814089639960610c48d19d2","column":{"colname":"id","transform":"count_distinct","aggregate":true}}],"where":[],"having":[],"order_by":[{"alias":"circs","path":"circ-id","relation":"fce458da5814089639960610c48d19d2","direction":"descending","column":{"colname":"id","transform":"count_distinct","aggregate":true}},{"alias":"Checkout Date/Time","path":"circ-xact_start","relation":"fce458da5814089639960610c48d19d2","direction":"ascending","column":{"colname":"xact_start","transform":"date_trunc","aggregate":false}},{"alias":"OPAC/Staff Client Username","path":"circ-usrname","relation":"3247d2a4a42dd2607c6677083a8f7e4e","direction":"ascending","column":{"colname":"usrname","transform":"Bare","aggregate":false}},{"alias":"Group Name","path":"circ-name","relation":"ab5aeec88729d5ccd466b711d329b838","direction":"ascending","column":{"colname":"name","transform":"Bare","aggregate":false}}],"relations":{"fce458da5814089639960610c48d19d2":{"alias":"fce458da5814089639960610c48d19d2","path":"circ-circ","table":"action.circulation","idlclass":"circ","label":"Circulation","join":{"usr-3247d2a4a42dd2607c6677083a8f7e4e":{"type":"left","key":"id","alias":"3247d2a4a42dd2607c6677083a8f7e4e","idlclass":"au","label":"Circulation [Required] -> Patron -> OPAC/Staff Client Username","table":"actor.usr","join":{"profile-ab5aeec88729d5ccd466b711d329b838":{"type":"inner","key":"id","alias":"ab5aeec88729d5ccd466b711d329b838","idlclass":"pgt","label":"Circulation [Required] -> Patron -> Main (Profile) Permission Group [Required] -> Group Name","table":"permission.grp_tree"}}}}},"3247d2a4a42dd2607c6677083a8f7e4e":{"type":"left","key":"id","alias":"3247d2a4a42dd2607c6677083a8f7e4e","idlclass":"au","label":"Circulation [Required] -> Patron -> OPAC/Staff Client Username","table":"actor.usr","join":{"profile-ab5aeec88729d5ccd466b711d329b838":{"type":"inner","key":"id","alias":"ab5aeec88729d5ccd466b711d329b838","idlclass":"pgt","label":"Circulation [Required] -> Patron -> Main (Profile) Permission Group [Required] -> Group Name","table":"permission.grp_tree"}}},"ab5aeec88729d5ccd466b711d329b838":{"type":"inner","key":"id","alias":"ab5aeec88729d5ccd466b711d329b838","idlclass":"pgt","label":"Circulation [Required] -> Patron -> Main (Profile) Permission Group [Required] -> Group Name","table":"permission.grp_tree"}}}';
$params = '{"__pivot_label":"","__pivot_data":0,"__do_rollup":0}';

my $r = OpenILS::Reporter::SQLBuilder->new;
$r->minimum_repsec_version(7);
$r->runner(42);
$r->register_params( OpenSRF::Utils::JSON->JSON2perl($params) );

my $rs = $r->parse_report( OpenSRF::Utils::JSON->JSON2perl($report) );
$rs->relative_time('2006-10-01T00:00:00-4');

print "Column Labels:\n---------------\n\t" . join("\n\t", $rs->column_label_list) . "\n\nSQL:\n--------\n";
print $rs->toSQL;

print "--------\n\n";

print "SQL group by list: ".join(',',$rs->group_by_list)."\n";
print "Perl group by list: ".join(',',$rs->group_by_list(0))."\n";

print "\n";

