dump('entering print_list_template_editor.js\n');
// vim:noet:sw=4:ts=4:

if (typeof circ == 'undefined') circ = {};
circ.print_list_template_editor = function (params) {
    try {
        JSAN.use('util.error'); this.error = new util.error();
    } catch(E) {
        dump('print_list: ' + E + '\n');
    }
}

circ.print_list_template_editor.prototype = {

    'init' : function( params ) {

        try {
            var obj = this;

            JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
            this.test_patron = new au();
            this.test_patron.family_name('Doe');
            this.test_patron.first_given_name('John');
            this.test_patron.alias('Curly');
            this.test_card = new ac();
            this.test_card.barcode('123456789');
            this.test_patron.card( this.test_card );

            this.test_data = {
                'payment' : {
                    'original_balance' : '16.36',
                    'payment_type' : 'Cash',
                    'payment_received' : '0.00',
                    'payment_applied' : '0.00',
                    'voided_balance' : '0.50',
                    'change_given' : '0.00',
                    'credit_given' : '0.00',
                    'note' : "We refunded this because...",
                    'new_balance' : '16.36'
                }
            }

            this.test_list = {
            
                'items' : [
                {"uses":"undefined","alert_message":"","author":"Annixter, Jane.","barcode":"3635300990263","call_number":"F","checkin_time":"   ","checkin_time_full":"","xact_start":"2006-08-23","xact_start_full":"2006-08-23T14:37:15-0400","circ_as_type":"","circ_id":"19907","circ_lib":"URRLS-SC","circ_modifier":"","circulate":"Yes","acp_id":"34","copy_number":"1","create_date":"2006-04-28","edit_date":"2006-08-23","deleted":"No","deposit_amount":"0.00","deposit":"No","mvr_doc_id":"13","due_date":"2006-08-23","edition":"","fine_level":"Low","stop_fines":"","stop_fines_time":"","holdable":"Yes","isbn":"","loan_duration":"Short","location":"Adult","message":"   ","opac_visible":"Yes","owning_lib":"URRLS-SC","price":"10.00","pubdate":"1961","publisher":"Longmans","ref":"No","renewal_remaining":"0","route_to":"   ","status":"Checked out","tcn":"PIN01000015 ","title":"Peace comes to Castle Oak ","xact_finish":""},
                {"uses":"undefined","alert_message":"","author":"Josephson, Matthew","barcode":"33207002163014","call_number":"NONFIC 330.922 JOSEPHSO","checkin_time":"   ","checkin_time_full":"","xact_start":"2006-08-23","xact_start_full":"2006-08-23T14:37:23-0400","circ_as_type":"","circ_id":"19908","circ_lib":"ARL-ATH","circ_modifier":"","circulate":"Yes","acp_id":"1658","copy_number":"1","create_date":"2006-04-28","edit_date":"2006-08-23","deleted":"No","deposit_amount":"0.00","deposit":"No","mvr_doc_id":"250","due_date":"2006-09-06","edition":"","fine_level":"Low","stop_fines":"","stop_fines_time":"","holdable":"Yes","isbn":"","loan_duration":"Short","location":"Adult","message":"   ","opac_visible":"Yes","owning_lib":"ARL-ATH","price":"10.95","pubdate":"[c1934]","publisher":"Harcourt, Brace and company","ref":"No","renewal_remaining":"0","route_to":"   ","status":"Checked out","tcn":"PIN01000311 ","title":"The  robber barons :  the great American capitalists, 1861-1901","xact_finish":""},
                {"uses":"undefined","alert_message":"","author":"Payne, Emmy","barcode":"33034001434539","call_number":"EJ PAYNE","checkin_time":"   ","checkin_time_full":"","xact_start":"2006-08-23","xact_start_full":"2006-08-23T14:36:54-0400","circ_as_type":"","circ_id":"19904","circ_lib":"SHRL-RM","circ_modifier":"","circulate":"Yes","acp_id":"6165596","copy_number":"1","create_date":"2006-04-28","edit_date":"2006-08-23","deleted":"No","deposit_amount":"0.00","deposit":"No","mvr_doc_id":"1220497","due_date":"2006-09-06","edition":"Reinforced ed.","fine_level":"Low","stop_fines":"","stop_fines_time":"","holdable":"Yes","isbn":"075872926X (BWI bdg.)","loan_duration":"Short","location":"Adult","message":"   ","opac_visible":"Yes","owning_lib":"SHRL-RM","price":"0.00","pubdate":"1944","publisher":"Houghton Mifflin","ref":"No","renewal_remaining":"0","route_to":"   ","status":"Checked out","tcn":"PIN01000377 ","title":"Katy no-pocket ","xact_finish":""},
                {"uses":"undefined","alert_message":"","author":"Ames, Leslie","barcode":"31039000791757","call_number":"AF AME","checkin_time":"   ","checkin_time_full":"","xact_start":"2006-08-23","xact_start_full":"2006-08-23T14:37:07-0400","circ_as_type":"","circ_id":"19906","circ_lib":"ORLS-TEL","circ_modifier":"","circulate":"Yes","acp_id":"28","copy_number":"1","create_date":"2006-04-28","edit_date":"2006-08-23","deleted":"No","deposit_amount":"0.00","deposit":"No","mvr_doc_id":"8","due_date":"2006-09-06","edition":"","fine_level":"Low","stop_fines":"","stop_fines_time":"","holdable":"Yes","isbn":"","loan_duration":"Short","location":"Adult","message":"   ","opac_visible":"Yes","owning_lib":"ORLS-TEL","price":"5.95","pubdate":"","publisher":"Lenox Hill","ref":"No","renewal_remaining":"0","route_to":"   ","status":"Checked out","tcn":"PIN01000009 ","title":"King's Castle ","xact_finish":""},
                {"uses":"undefined","alert_message":"","author":"Payne, Emmy","barcode":"33034001434539","call_number":"EJ PAYNE","checkin_time":"   ","checkin_time_full":"","xact_start":"2006-08-23","xact_start_full":"2006-08-23T14:36:54-0400","circ_as_type":"","circ_id":"19903","circ_lib":"SHRL-RM","circ_modifier":"","circulate":"Yes","acp_id":"6165596","copy_number":"1","create_date":"2006-04-28","edit_date":"2006-08-23","deleted":"No","deposit_amount":"0.00","deposit":"No","mvr_doc_id":"1220497","due_date":"2006-09-06","edition":"Reinforced ed.","fine_level":"Low","stop_fines":"","stop_fines_time":"","holdable":"Yes","isbn":"075872926X (BWI bdg.)","loan_duration":"Short","location":"Adult","message":"   ","opac_visible":"Yes","owning_lib":"SHRL-RM","price":"0.00","pubdate":"1944","publisher":"Houghton Mifflin","ref":"No","renewal_remaining":"0","route_to":"   ","status":"Checked out","tcn":"PIN01000377 ","title":"Katy no-pocket ","xact_finish":""}],
                'holds' : [{"author":"Wells, H. G. ","available_time":"2006-08-03","available_timestamp":"2006-08-03T15:14:53-0400","capture_time":"2006-08-03","capture_timestamp":"2006-08-03T15:14:53-0400","current_copy":"33207003884402","edition":"","email_notify":"No","expire_time":"","fulfillment_time":"","id":"57","holdable_formats":"","isbn":"0192828266 :","notify_time":"","notify_count":"0","patron_name":"23500000023053 Stompro, Josh","phone_notify":"218-233-3757","pickup_lib_shortname":"ARL-ATH","pickup_lib":"Athens-Clarke County Library","prev_check_time":"2006-08-02T16:15:11-0400","pubdate":"1995","publisher":"Oxford University Press","request_time":"2006-05-20","request_timestamp":"2006-05-20","requestor":"1000000","selection_depth":"0","status":"Ready for pickup","tcn":"PIN03002240 ","target":"131469","title":"The  war of the worlds","transit_dest_recv_time":"","transit_dest_lib":"","transit_source":"","transit_source_send_time":"","hold_type":"T","usr":"1000567"},
                {"author":"Kramer, Kathryn.","available_time":"2006-08-03","available_timestamp":"2006-08-03T15:32:58-0400","capture_time":"2006-08-03","capture_timestamp":"2006-08-03T15:32:58-0400","current_copy":"33207004030757","edition":"1st ed.","email_notify":"No","expire_time":"","fulfillment_time":"","id":"470","holdable_formats":"","isbn":"0375400834","notify_time":"2006-08-24T15:12:30-0400","notify_count":"1","patron_name":"21034000217210 Jenkins, George","phone_notify":"229-985-3464","pickup_lib_shortname":"ARL-ATH","pickup_lib":"Athens-Clarke County Library","prev_check_time":"2006-08-03T12:15:03-0400","pubdate":"1998","publisher":"Knopf","request_time":"2006-07-28","request_timestamp":"2006-07-28","requestor":"3","selection_depth":"0","status":"Ready for pickup","tcn":"PIN03053147 ","target":"313678","title":"Sweet water ","transit_dest_recv_time":"","transit_dest_lib":"","transit_source":"","transit_source_send_time":"","hold_type":"T","usr":"1001151"},
                {"author":"Silva, Daniel","available_time":"2006-08-03","available_timestamp":"2006-08-03T15:39:35-0400","capture_time":"2006-08-03","capture_timestamp":"2006-08-03T15:39:35-0400","current_copy":"33207004323517","edition":"1st ed.","email_notify":"No","expire_time":"","fulfillment_time":"","id":"448","holdable_formats":"","isbn":"0375500898 (alk. paper)","notify_time":"","notify_count":"0","patron_name":"21099000002755 Broome, Sandra","phone_notify":"706-236-4632","pickup_lib_shortname":"ARL-ATH","pickup_lib":"Athens-Clarke County Library","prev_check_time":"2006-08-02T17:16:39-0400","pubdate":"c1999","publisher":"Random House","request_time":"2006-07-27","request_timestamp":"2006-07-27","requestor":"1000001","selection_depth":"0","status":"Ready for pickup","tcn":"ocm40444117 ","target":"77772","title":"The  marching season :  a novel","transit_dest_recv_time":"","transit_dest_lib":"","transit_source":"","transit_source_send_time":"","hold_type":"T","usr":"1000846"},
                {"author":"Seuss","available_time":"2006-08-13","available_timestamp":"2006-08-13T20:55:02-0400","capture_time":"2006-08-13","capture_timestamp":"2006-08-13T20:55:02-0400","current_copy":"20070805","edition":"","email_notify":"No","expire_time":"","fulfillment_time":"","id":"1697","holdable_formats":"","isbn":"039480001X :","notify_time":"","notify_count":"0","patron_name":"4545 Tripper, Jack","phone_notify":"444-333-2222","pickup_lib_shortname":"ARL-ATH","pickup_lib":"Athens-Clarke County Library","prev_check_time":"2006-08-13T20:45:09-0400","pubdate":"1992, c1957","publisher":"Seedlings Braille Books for Children","request_time":"2006-08-13","request_timestamp":"2006-08-13","requestor":"1000000","selection_depth":"0","status":"Ready for pickup","tcn":"ocm47673093 ","target":"1534993","title":"The  cat in the hat","transit_dest_recv_time":"","transit_dest_lib":"","transit_source":"","transit_source_send_time":"","hold_type":"T","usr":"1002261"},
                {"author":"Potter, Sally.","available_time":"2006-08-09","available_timestamp":"2006-08-09T18:06:10-0400","capture_time":"2006-08-09","capture_timestamp":"2006-08-09T18:06:10-0400","current_copy":"31001000843129","edition":"","email_notify":"No","expire_time":"","fulfillment_time":"","id":"1004","holdable_formats":"","isbn":"0783262663","notify_time":"2006-08-10T15:24:46-0400","notify_count":"12","patron_name":"2222233333 Erickson, Bill","phone_notify":"999-999-9999","pickup_lib_shortname":"ARL-ATH","pickup_lib":"Athens-Clarke County Library","prev_check_time":"2006-08-09T12:15:27-0400","pubdate":"c2001","publisher":"Universal Studios","request_time":"2006-08-08","request_timestamp":"2006-08-08","requestor":"3","selection_depth":"0","status":"Ready for pickup","tcn":"ocm48683123 ","target":"1572303","title":"The  man who cried","transit_dest_recv_time":"","transit_dest_lib":"","transit_source":"","transit_source_send_time":"","hold_type":"T","usr":"3"}],
                'bills' : [{"balance_owed":"-5.00","xact_finish":"2006-05-08","xact_start":"2006-05-08","mbts_id":"9","last_billing_ts":"2006-05-08 18:53","last_billing_note":"test","last_billing_type":"Miscellaneous charges","last_payment_ts":"2006-05-08 18:53","last_payment_note":"","last_payment_type":"cash_payment","total_owed":"0.00","total_paid":"5.00","xact_type":"grocery","usr":"Id = 1000502"},
                {"balance_owed":"-5.00","xact_finish":"2006-05-08","xact_start":"2006-05-08","mbts_id":"11","last_billing_ts":"2006-05-08 19:11","last_billing_note":"test","last_billing_type":"Miscellaneous","last_payment_ts":"2006-05-08 19:12","last_payment_note":"","last_payment_type":"cash_payment","total_owed":"0.00","total_paid":"5.00","xact_type":"grocery","usr":"Id = 1000502"},
                {"balance_owed":"-50.00","xact_finish":"2006-05-08","xact_start":"2006-05-08","mbts_id":"18","last_billing_ts":"2006-05-08 20:20","last_billing_note":"","last_billing_type":"Miscellaneous","last_payment_ts":"2006-05-08 21:27","last_payment_note":"","last_payment_type":"cash_payment","total_owed":"0.00","total_paid":"50.00","xact_type":"grocery","usr":"Id = 1000502"},
                {"balance_owed":"1.00","xact_finish":"2006-06-14","xact_start":"2006-06-14","mbts_id":"451","last_billing_ts":"2006-06-14 16:49","last_billing_note":"SYSTEM GENERATED","last_billing_type":"Lost Materials","last_payment_ts":"2006-06-14 16:49","last_payment_note":"","last_payment_type":"cash_payment","total_owed":"6.00","total_paid":"5.00","xact_type":"circulation","usr":"Id = 1000502"},
                {"balance_owed":"-1.00","xact_finish":"2006-06-17","xact_start":"2006-06-17","mbts_id":"3689","last_billing_ts":"2006-06-17 04:01","last_billing_note":"","last_billing_type":"Miscellaneous","last_payment_ts":"2006-06-17 18:51","last_payment_note":"","last_payment_type":"cash_payment","total_owed":"10.00","total_paid":"11.00","xact_type":"grocery","usr":"Id = 1000502"},
                {"balance_owed":".66","xact_finish":"","xact_start":"2006-06-27","mbts_id":"5589","last_billing_ts":"2006-08-22 00:00","last_billing_note":"Overdue Fine","last_billing_type":"Overdue materials","last_payment_ts":"2006-09-04 17:31","last_payment_note":"","last_payment_type":"cash_payment","total_owed":"5.60","total_paid":"4.94","xact_type":"circulation","usr":"Id = 1000502"},
                {"balance_owed":".70","xact_finish":"","xact_start":"2006-06-27","mbts_id":"5593","last_billing_ts":"2006-08-22 00:00","last_billing_note":"Overdue Fine","last_billing_type":"Overdue materials","last_payment_ts":"2006-08-16 11:01","last_payment_note":"","last_payment_type":"cash_payment","total_owed":"5.50","total_paid":"4.80","xact_type":"circulation","usr":"Id = 1000502"},
                {"balance_owed":"5.00","xact_finish":"","xact_start":"2006-08-16","mbts_id":"14834","last_billing_ts":"2006-08-16 12:25","last_billing_note":"","last_billing_type":"Damaged material","last_payment_ts":"","last_payment_note":"","last_payment_type":"","total_owed":"5.00","total_paid":"0.00","xact_type":"grocery","usr":"Id = 1000502"},
                {"balance_owed":"10.00","xact_finish":"","xact_start":"2006-08-16","mbts_id":"14858","last_billing_ts":"2006-08-16 12:34","last_billing_note":"","last_billing_type":"Damaged material","last_payment_ts":"","last_payment_note":"","last_payment_type":"","total_owed":"10.00","total_paid":"0.00","xact_type":"grocery","usr":"Id = 1000502"}],
                'payment' : [{"bill_id":5559,"payment":"-0.04","last_billing_type":"Overdue materials","last_billing_note":"Overdue Fine","title":"Hali Bote Azikaban de tao fan","barcode":"a16"},{"bill_id":5589,"payment":"0.04","last_billing_type":"Overdue materials","last_billing_note":"Overdue Fine","title":"Hali Bote Azikaban de tao fan","barcode":"a47"}],
                'patrons' : [],
                'transits' : [{"transit_item_author":"Arvetis, Chris.","transit_item_barcode":"3947801748348","transit_item_callnumber":"JE ARV","transit_item_title":"Why do birds sing?","transit_target_copy":"2385751","transit_dest_lib":"PIED-WIN","transit_id":"25","transit_source":"ARL-ATH","transit_source_send_time":"2006-05-24T16:37:09-0400","capture_time":"   ","capture_timestamp":"   ","expire_time":"   ","patron_name":"undefined undefined, undefined","request_time":"   ","request_timestamp":"   ","hold_type":"   "},
                {"transit_item_author":"Pine, Tillie S.","transit_item_barcode":"3635300990762","transit_item_callnumber":"F","transit_item_title":"Water all around ","transit_target_copy":"1","transit_dest_lib":"URRLS-SC","transit_id":"26","transit_source":"ARL-ATH","transit_source_send_time":"2006-05-27T22:49:40-0400","capture_time":"   ","capture_timestamp":"   ","expire_time":"   ","patron_name":"undefined undefined, undefined","request_time":"   ","request_timestamp":"   ","hold_type":"   "},
                {"transit_item_author":"","transit_item_barcode":"31057000861941","transit_item_callnumber":"CD J 781.5246 CASPE","transit_item_title":"Casper's spookiest songs and sounds  10 spooky songs plus creepy sound effects","transit_target_copy":"7923932","transit_dest_lib":"WGRL-LS","transit_id":"98","transit_source":"ARL-ATH","transit_source_send_time":"2006-06-29T16:34:38-0400","capture_time":"   ","capture_timestamp":"   ","expire_time":"   ","patron_name":"undefined undefined, undefined","request_time":"   ","request_timestamp":"   ","hold_type":"   "},
                {"transit_item_author":"Davidson, MaryJanice.","transit_item_barcode":"31027005649112","transit_item_callnumber":"AC DAV","transit_item_title":"Undead and unreturnable ","transit_target_copy":"7924995","transit_dest_lib":"HCLS-LG","transit_id":"100","transit_source":"ARL-ATH","transit_source_send_time":"2006-07-07T16:02:32-0400","capture_time":"   ","capture_timestamp":"   ","expire_time":"   ","patron_name":"undefined undefined, undefined","request_time":"   ","request_timestamp":"   ","hold_type":"   "},
                {"transit_item_author":"Evanovich, Janet.","transit_item_barcode":"31001001097295","transit_item_callnumber":"813/.54","transit_item_title":"Two for the dough","transit_target_copy":"8000335","transit_dest_lib":"ARL-BOG","transit_id":"102","transit_source":"ARL-ATH","transit_source_send_time":"2006-07-11T12:12:11-0400","capture_time":"   ","capture_timestamp":"   ","expire_time":"   ","patron_name":"undefined undefined, undefined","request_time":"   ","request_timestamp":"   ","hold_type":"   "},
                {"transit_item_author":"Edwards, Anne","transit_item_barcode":"39021423853564","transit_item_callnumber":"780.92 STREISAND","transit_item_title":"Streisand a biography","transit_target_copy":"949781","transit_dest_lib":"ECGR-BKM","transit_id":"110","transit_source":"ARL-ATH","transit_source_send_time":"2006-07-14T10:00:01-0400","capture_time":"   ","capture_timestamp":"   ","expire_time":"   ","patron_name":"undefined undefined, undefined","request_time":"   ","request_timestamp":"   ","hold_type":"   "},
                {"transit_item_author":"Riese, Randall.","transit_item_barcode":"31025900460205","transit_item_callnumber":"921 STREISAND 1993","transit_item_title":"Her name is Barbra an intimate portrait of the real Barbra Streisand","transit_target_copy":"2210566","transit_dest_lib":"HALL-BPL","transit_id":"112","transit_source":"ARL-ATH","transit_source_send_time":"2006-07-14T10:01:39-0400","capture_time":"   ","capture_timestamp":"   ","expire_time":"   ","patron_name":"undefined undefined, undefined","request_time":"   ","request_timestamp":"   ","hold_type":"   "},
                {"transit_item_author":"Rowling, J. K.","transit_item_barcode":"a45","transit_item_callnumber":"JROWLING2","transit_item_title":"Hali Bote Azikaban de tao fan","transit_target_copy":"8000297","transit_dest_lib":"WGRL-LS","transit_id":"118","transit_source":"ARL-ATH","transit_source_send_time":"2006-07-19T13:52:38-0400","capture_time":"   ","capture_timestamp":"   ","expire_time":"   ","patron_name":"undefined undefined, undefined","request_time":"   ","request_timestamp":"   ","hold_type":"   "},
                {"transit_item_author":"Some Author","transit_item_barcode":"321","transit_item_callnumber":"UNCATALOGED","transit_item_title":"Big Book","transit_target_copy":"8000387","transit_dest_lib":"ROCK-NG","transit_id":"119","transit_source":"ARL-ATH","transit_source_send_time":"2006-07-19T13:58:21-0400","capture_time":"   ","capture_timestamp":"   ","expire_time":"   ","patron_name":"undefined undefined, undefined","request_time":"   ","request_timestamp":"   ","hold_type":"   "},
                {"transit_item_author":"Thomas, Joyce Carol.","transit_item_barcode":"31036000522216","transit_item_callnumber":"E THOMAS","transit_item_title":"The  gospel Cinderella","transit_target_copy":"7422951","transit_dest_lib":"NCLS-COVTN","transit_id":"200","transit_source":"ARL-ATH","transit_source_send_time":"2006-07-25T15:20:00-0400","capture_time":"   ","capture_timestamp":"   ","expire_time":"   ","patron_name":"undefined undefined, undefined","request_time":"   ","request_timestamp":"   ","hold_type":"   "},
                {"transit_item_author":"Robinson, Barbara","transit_item_barcode":"31036000545159","transit_item_callnumber":"J ROBINSON","transit_item_title":"The  best Halloween ever","transit_target_copy":"7487432","transit_dest_lib":"NCLS-COVTN","transit_id":"206","transit_source":"ARL-ATH","transit_source_send_time":"2006-07-25T15:25:44-0400","capture_time":"   ","capture_timestamp":"   ","expire_time":"   ","patron_name":"undefined undefined, undefined","request_time":"   ","request_timestamp":"   ","hold_type":"   "},
                {"transit_item_author":"Robinson, Barbara","transit_item_barcode":"31036000545142","transit_item_callnumber":"J ROBINSON","transit_item_title":"The  best Halloween ever","transit_target_copy":"7487431","transit_dest_lib":"NCLS-COVTN","transit_id":"207","transit_source":"ARL-ATH","transit_source_send_time":"2006-07-25T15:25:49-0400","capture_time":"   ","capture_timestamp":"   ","expire_time":"   ","patron_name":"undefined undefined, undefined","request_time":"   ","request_timestamp":"   ","hold_type":"   "},
                {"transit_item_author":"Grafton, Sue.","transit_item_barcode":"31036000527900","transit_item_callnumber":"F GRAFTON","transit_item_title":"\"H\" is for homicide","transit_target_copy":"7273824","transit_dest_lib":"NCLS-COVTN","transit_id":"208","transit_source":"ARL-ATH","transit_source_send_time":"2006-07-25T15:25:58-0400","capture_time":"   ","capture_timestamp":"   ","expire_time":"   ","patron_name":"undefined undefined, undefined","request_time":"   ","request_timestamp":"   ","hold_type":"   "},
                {"transit_item_author":"Beaumont, Karen.","transit_item_barcode":"31036000521853","transit_item_callnumber":"E BEAUMONT","transit_item_title":"I like myself!","transit_target_copy":"7387328","transit_dest_lib":"NCLS-COVTN","transit_id":"211","transit_source":"ARL-ATH","transit_source_send_time":"2006-07-25T15:26:08-0400","capture_time":"   ","capture_timestamp":"   ","expire_time":"   ","patron_name":"undefined undefined, undefined","request_time":"   ","request_timestamp":"   ","hold_type":"   "},
                {"transit_item_author":"Sandler, Martin W.","transit_item_barcode":"31036000522612","transit_item_callnumber":"J 388.42 SANDLER","transit_item_title":"Straphanging in the USA trolleys and subways in American life","transit_target_copy":"7360328","transit_dest_lib":"NCLS-COVTN","transit_id":"212","transit_source":"ARL-ATH","transit_source_send_time":"2006-07-25T15:35:17-0400","capture_time":"   ","capture_timestamp":"   ","expire_time":"   ","patron_name":"undefined undefined, undefined","request_time":"   ","request_timestamp":"   ","hold_type":"   "},
                {"transit_item_author":"Bohjalian, Christopher A.","transit_item_barcode":"31036000538303","transit_item_callnumber":"F BOHJALIAN","transit_item_title":"Before you know kindness :  a novel","transit_target_copy":"7544549","transit_dest_lib":"NCLS-COVTN","transit_id":"218","transit_source":"ARL-ATH","transit_source_send_time":"2006-07-26T10:23:20-0400","capture_time":"   ","capture_timestamp":"   ","expire_time":"   ","patron_name":"undefined undefined, undefined","request_time":"   ","request_timestamp":"   ","hold_type":"   "},],
                'offline_checkout' : [],
                'offline_checkin' : [],
                'offline_renew' : [],
                'offline_inhouse_use' : []
            }

            obj.controller_init();
            obj.controller.render(); obj.controller.view.template_name_menu.focus();

            obj.post_init();

        } catch(E) {
            alert('init: ' + E);
            this.error.sdump('D_ERROR','print_list.init: ' + E + '\n');
        }
    },

    'post_init' : function() {
        var obj = this;
        setTimeout(
            function() {
                var tmp = obj.data.print_list_templates[ obj.controller.view.template_name_menu.value ];
                if (tmp.inherit) {
                    tmp = obj.data.print_list_templates[ tmp.inherit ];
                    // if someone wants to implement recursion later, feel free
                }
                obj.controller.view.template_type_menu.value = tmp.type;
                obj.controller.view.header.value = tmp.header;
                obj.controller.view.line_item.value = tmp.line_item;
                obj.controller.view.footer.value = tmp.footer;
                obj.controller.view.template_context_menu.value = tmp.context;
                obj.preview();
            }, 0
        );
    },

    'controller_init' : function() {
        try {
            var obj = this;
            JSAN.use('util.controller'); obj.controller = new util.controller();
            obj.controller.init(
                {
                    control_map : {
                        'sample' : [ ['command'], function() { } ],
                        'header' : [ ['change'], function() { obj.preview(); } ],
                        'line_item' : [ ['change'], function() { obj.preview(); } ],
                        'footer' : [ ['change'], function() { obj.preview(); } ],
                        'preview' : [
                            ['command'],
                            function() {
                                obj.preview();
                            }
                        ],
                        'save' : [
                            ['command'],
                            function() {
                                obj.save_template( obj.controller.view.template_name_menu.value );
                            }
                        ],
                        'export' : [
                            ['command'],
                            function() {
                                obj.export_templates();
                            }
                        ],
                        'import' : [
                            ['command'],
                            function() {
                                obj.import_templates();
                            }
                        ],
                        'default' : [
                            ['command'],
                            function() {
                                obj.data.print_list_defaults();
                                obj.post_init();
                            }
                        ],
                        'macros' : [
                            ['command'],
                            function() {
                                try {
                                    JSAN.use('util.functional');
                                    var template_type = obj.controller.view.template_type_menu.value;
                                    var macros = [];
                                    switch(template_type) {
                                        case 'items':
                                            JSAN.use('circ.util');
                                            macros = util.functional.map_list(
                                                circ.util.columns( {} ),
                                                function(o) {
                                                    return '%' + o.id + '%';
                                                }
                                            );
                                        break;
                                        case 'holds':
                                            JSAN.use('circ.util');
                                            macros = util.functional.map_list(
                                                circ.util.hold_columns( {} ),
                                                function(o) {
                                                    return '%' + o.id + '%';
                                                }
                                            );
                                        break;
                                        case 'transits':
                                            JSAN.use('circ.util');
                                            macros = util.functional.map_list(
                                                circ.util.transit_columns( {} ),
                                                function(o) {
                                                    return '%' + o.id + '%';
                                                }
                                            );
                                        break;
                                        case 'offline_checkout':
                                            JSAN.use('circ.util');
                                            macros = util.functional.map_list(
                                                circ.util.offline_checkout_columns( {} ),
                                                function(o) {
                                                    return '%' + o.id + '%';
                                                }
                                            );
                                        break;
                                        case 'offline_checkin':
                                            JSAN.use('circ.util');
                                            macros = util.functional.map_list(
                                                circ.util.offline_checkin_columns( {} ),
                                                function(o) {
                                                    return '%' + o.id + '%';
                                                }
                                            );
                                        break;
                                        case 'offline_renew':
                                            JSAN.use('circ.util');
                                            macros = util.functional.map_list(
                                                circ.util.offline_renew_columns( {} ),
                                                function(o) {
                                                    return '%' + o.id + '%';
                                                }
                                            );
                                        break;
                                        case 'offline_inhouse_use':
                                            JSAN.use('circ.util');
                                            macros = util.functional.map_list(
                                                circ.util.offline_inhouse_use_columns( {} ),
                                                function(o) {
                                                    return '%' + o.id + '%';
                                                }
                                            );
                                        break;
                                        case 'bills':
                                            JSAN.use('patron.util');
                                            macros = util.functional.map_list(
                                                patron.util.mbts_columns( {} ),
                                                function(o) {
                                                    return '%' + o.id + '%';
                                                }
                                            );
                                        break;
                                        case 'patrons':
                                            JSAN.use('patron.util');
                                            macros = util.functional.map_list(
                                                patron.util.columns( {} ),
                                                function(o) {
                                                    return '%' + o.id + '%';
                                                }
                                            );
                                        break;
                                        case 'payment' : 
                                            macros = [ '%original_balance%', '%payment_received%', '%payment_applied%', '%payment_type%', '%voided_balance%', '%change_given%', '%new_balance%', '%note%', '%bill_id%', '%payment%', '%title%' ];
                                        break;
                                    }
                                    var macro_string = macros.join(', ');
                                    JSAN.use('util.window');
                                    var win = new util.window();
                                    win.open('data:text/html,'
                                        + window.escape(
                                            '<html style="width: 600; height: 400;">'
                                            + '<head><title>' 
                                            + document.getElementById('circStrings').getString('staff.circ.print_list_template.window.title')
                                            + '</title></head>'
                                            + '<body onload="document.getElementById(\'btn\').focus()">'
                                            + '<h1>' 
                                            + document.getElementById('circStrings').getString('staff.circ.print_list_template.window.heading')
                                            + '</h1>'
                                            + '<p>%LIBRARY%, %SHORTNAME%, %LINE_NO%, '
                                            + '%STAFF_FIRSTNAME%, %STAFF_LASTNAME%, %STAFF_BARCODE%, %STAFF_PROFILE%, '
                                            + '%PATRON_FIRSTNAME%, %PATRON_ALIAS%, %PATRON_ALIAS_OR_FIRSTNAME%, %PATRON_LASTNAME%, '
                                            + '%PATRON_BARCODE%, %patron_barcode%, '
                                            + '%TODAY%, %TODAY_TRIM%, %TODAY_m%, %TODAY_d%, %TODAY_Y%, %TODAY_H%, %TODAY_I%, '
                                            + '%TODAY_M%, %TODAY_D%, %TODAY_F% '
                                            + '</p>'
                                            + '<h1>'
                                            + document.getElementById('circStrings').getFormattedString('staff.circ.print_list_template.window.template_type', [template_type])
                                            + '</h1>'
                                            + '<p>' 
                                            + macro_string 
                                            + '</p>'
                                            + '<button id="btn" onclick="window.close()">'
                                            + document.getElementById('circStrings').getString('staff.circ.print_list_template.window.close')
                                            + '</button>'
                                            + '</body></html>'
                                        ), 'title', 'chrome,resizable');
                                } catch(E) {
                                    alert(E);
                                }
                            }
                        ],
                        'template_name_menu_placeholder' : [
                            ['render'],
                            function(e) {
                                return function() {
                                    JSAN.use('util.widgets'); JSAN.use('util.functional');
                                    util.widgets.remove_children(e);
                                    var ml = util.widgets.make_menulist(
                                        util.functional.map_object_to_list(
                                            obj.data.print_list_templates,
                                            function(o,i) { return [i,i]; }
                                        )
                                    );
                                    ml.setAttribute('id','template_name_menu');
                                    //ml.setAttribute('editable','true');
                                    ml.setAttribute('flex','1');
                                    e.appendChild(ml);
                                    obj.controller.view.template_name_menu = ml;
                                    ml.addEventListener(
                                        'command',
                                        function(ev) {
                                            var tmp = obj.data.print_list_templates[ ev.target.value ];
                                            if (tmp.inherit) {
                                                tmp = obj.data.print_list_templates[ tmp.inherit ];
                                                // if someone wants to implement recursion later, feel free
                                            }
                                            obj.controller.view.template_type_menu.value = tmp.type;
                                            obj.controller.view.header.value = tmp.header;
                                            obj.controller.view.line_item.value = tmp.line_item;
                                            obj.controller.view.footer.value = tmp.footer;
                                            obj.controller.view.template_context_menu.value = tmp.context;
                                            obj.preview();
                                        },
                                        false
                                    );
                                }
                            }
                        ],
                        'template_type_menu_placeholder' : [
                            ['render'],
                            function(e) {
                                return function() {
                                    JSAN.use('util.widgets'); JSAN.use('util.functional');
                                    util.widgets.remove_children(e);
                                    var ml = util.widgets.make_menulist(
                                        util.functional.map_list(
                                            obj.data.print_list_types,
                                            function(o) { return [o,o]; }
                                        )
                                    );
                                    ml.setAttribute('id','template_types_menu');
                                    ml.setAttribute('disabled','true');
                                    e.appendChild(ml);
                                    obj.controller.view.template_type_menu = ml;
                                }
                            }
                        ],
                        'template_context_menu_placeholder' : [
                            ['render'],
                            function(e) {
                                return function() {
                                    JSAN.use('util.widgets'); JSAN.use('util.functional');
                                    util.widgets.remove_children(e);
                                    var ml = util.widgets.make_menulist(
                                        [['',null]].concat(
                                            util.functional.map_list(
                                                obj.data.print_list_contexts,
                                                function(o) { return [o,o]; }
                                            )
                                        )
                                    );
                                    ml.setAttribute('id','template_context_menu');
                                    e.appendChild(ml);
                                    obj.controller.view.template_context_menu = ml;
                                }
                            }
                        ]


                    }
                }
            );
        } catch(E) {
            alert('controller_init: ' + E );
        }
    },

    'preview' : function () { 
        try {
            var list = this.test_list[ this.controller.view.template_type_menu.value ];
            if (typeof list == 'undefined') list = [];
            var data = this.test_data[ this.controller.view.template_type_menu.value ];
            if (typeof data == 'undefined') data = {};

            var params = { 
                'patron' : this.test_patron, 
                'lib' : this.data.hash.aou[ this.data.list.au[0].ws_ou() ],
                'staff' : this.data.list.au[0],
                'header' : this.controller.view.header.value,
                'line_item' : this.controller.view.line_item.value,
                'footer' : this.controller.view.footer.value,
                'type' : this.controller.view.template_type_menu.value,
                'list' : list,
                'data' : data,
                'sample_frame' : this.controller.view.sample
            };
            JSAN.use('util.print'); var print = new util.print();
            print.tree_list( params );
        } catch(E) {
            this.error.sdump('D_ERROR', document.getElementById('circStrings').getString('staff.circ.print_list_template.preview') + ' ' + E);
            alert(document.getElementById('circStrings').getString('staff.circ.print_list_template.preview') + ' ' + E);
        }
    },

    'save_template' : function(name) {
        var obj = this;
        obj.data.print_list_templates[name].inherit = null;
        obj.data.print_list_templates[name].header = obj.controller.view.header.value;
        obj.data.print_list_templates[name].line_item = obj.controller.view.line_item.value;
        obj.data.print_list_templates[name].footer = obj.controller.view.footer.value;
        obj.data.print_list_templates[name].type = obj.controller.view.template_type_menu.value;
        obj.data.print_list_templates[name].context = obj.controller.view.template_context_menu.value;
        obj.data.stash( 'print_list_templates' );
        JSAN.use('util.file'); var file = new util.file('print_list_templates');
        file.set_object(obj.data.print_list_templates); file.close();
        alert(document.getElementById('circStrings').getString('staff.circ.print_list_template.save') + '\n' + js2JSON(obj.data.print_list_templates[name]));
    },

    'export_templates' : function() {
        try {
            var obj = this;
            JSAN.use('util.file'); var f = new util.file('');
            f.export_file( { 'title' : document.getElementById('circStrings').getString('staff.circ.print_list_template.save_as'), 'data' : obj.data.print_list_templates } );

        } catch(E) {
            this.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.print_list_template.export.error'),E);
        }
    },

    'import_templates' : function() {
        try {
            var obj = this;
            JSAN.use('util.file'); var f = new util.file('');
            var temp = f.import_file( { 'title' : document.getElementById('circStrings').getString('staff.circ.print_list_template.import') } );
            if (!temp) { return; }
            var s = '';
            function set_t(k,v) {
                obj.data.print_list_templates[k] = v;
                if (s) s+= ', '; s += k;
            }
            for (var i in temp) { set_t(i,temp[i]); }
            obj.data.stash('print_list_templates');
            alert(document.getElementById('circStrings').getFormattedString('staff.circ.print_list_template.import_results', [s]));
            if (xulG) { 
                xulG.set_tab(xulG.url_prefix('XUL_PRINT_LIST_TEMPLATE_EDITOR'), {}, {});
            } else {
                alert(document.getElementById('circStrings').getString('staff.circ.print_list_template.reload'));
            }
    
        } catch(E) {
            this.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.print_list_template.import.error'),E);
        }
    }

}

dump('exiting print_list_template_editor.js\n');
