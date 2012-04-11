package OpenILS::WWW::TemplateBatchBibUpdate;
use strict;
use warnings;
use bytes;

use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT DECLINED NOT_FOUND :log);
use APR::Const    -compile => qw(:error SUCCESS);
use APR::Table;

use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::RequestUtil;
use CGI;
use Data::Dumper;
use Text::CSV;

use OpenSRF::EX qw(:try);
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::Cache;
use OpenSRF::System;
use OpenSRF::AppSession;
use XML::LibXML;
use XML::LibXSLT;

use Encode;
use Unicode::Normalize;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger qw/$logger/;

use MARC::Record;
use MARC::File::XML ( BinaryEncoding => 'UTF-8' );

use UNIVERSAL::require;

our @formats = qw/USMARC UNIMARC XML BRE/;

# set the bootstrap config and template include directory when
# this module is loaded
my $bootstrap;

sub import {
    my $self = shift;
    $bootstrap = shift;
}


sub child_init {
    OpenSRF::System->bootstrap_client( config_file => $bootstrap );
    Fieldmapper->import(IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));
    return Apache2::Const::OK;
}

sub handler {
    my $r = shift;
    my $cgi = new CGI;

    my $authid = $cgi->cookie('ses') || $cgi->param('ses');
    my $usr = verify_login($authid);
    return show_template($r) unless ($usr);

    my $template = $cgi->param('template');
    return show_template($r) unless ($template);


    my $rsource = $cgi->param('recordSource');
    # find some IDs ...
    my @records;

    if ($rsource eq 'r') {
        @records = map { $_ ? ($_) : () } $cgi->param('recid');
    }

    if ($rsource eq 'c') { # try for a file
        my $file = $cgi->param('idfile');
        if ($file) {
            my $col = $cgi->param('idcolumn') || 0;
            my $csv = new Text::CSV;

            while (<$file>) {
                $csv->parse($_);
                my @data = $csv->fields;
                my $id = $data[$col];
                $id =~ s/\D+//o;
                next unless ($id);
                push @records, $id;
            }
        }
    }

    my $e = OpenSRF::AppSession->connect('open-ils.cstore');
    $e->request('open-ils.cstore.transaction.begin')->gather(1);
    $e->request('open-ils.cstore.set_audit_info', $authid, $usr->id, $usr->wsid)->gather(1);

    # still no records ...
    my $container = $cgi->param('containerid');
    if ($rsource eq 'b') {
        if ($container) {
            my $bucket = $e->request(
                'open-ils.cstore.direct.container.biblio_record_entry_bucket.retrieve',
                $container
            )->gather(1);
            unless($bucket) {
                $e->request('open-ils.cstore.transaction.rollback')->gather(1);
                $e->disconnect;
                $r->log->error("No such bucket $container");
                $logger->error("No such bucket $container");
                return Apache2::Const::NOT_FOUND;
            }
            my $recs = $e->request(
                'open-ils.cstore.direct.container.biblio_record_entry_bucket_item.search.atomic',
                { bucket => $container }
            )->gather(1);
            @records = map { ($_->target_biblio_record_entry) } @$recs;
        }
    }

    unless (@records) {
        $e->request('open-ils.cstore.transaction.rollback')->gather(1);
        $e->disconnect;
        return show_template($r);
    }

    # we have a template and some record ids, so...

    # insert the template record
    my $min_id = $e->request(
        'open-ils.cstore.json_query',
        { select => { bre => [{ column => 'id', transform => 'min', aggregate => 1}] }, from => 'bre' }
    )->gather(1)->{id} - 1;

    warn "new template bib id = $min_id\n";

    my $tmpl_rec = Fieldmapper::biblio::record_entry->new;
    $tmpl_rec->id($min_id);
    $tmpl_rec->deleted('t');
    $tmpl_rec->active('f');
    $tmpl_rec->marc($template);
    $tmpl_rec->creator($usr->id);
    $tmpl_rec->editor($usr->id);

    warn "about to create bib $min_id\n";
    $e->request('open-ils.cstore.direct.biblio.record_entry.create', $tmpl_rec )->gather(1);

    # create the new container for the records and the template
    my $bucket = Fieldmapper::container::biblio_record_entry_bucket->new;
    $bucket->owner($usr->id);
    $bucket->btype('template_merge');

    my $bname = $cgi->param('bname') || 'Temporary Merge Bucket '. localtime() . ' ' . $usr->id;
    $bucket->name($bname);

    $bucket = $e->request('open-ils.cstore.direct.container.biblio_record_entry_bucket.create', $bucket )->gather(1);

    # create items in the bucket
    my $item = Fieldmapper::container::biblio_record_entry_bucket_item->new;
    $item->bucket($bucket->id);
    $item->target_biblio_record_entry($min_id);

    $e->request('open-ils.cstore.direct.container.biblio_record_entry_bucket_item.create', $item )->gather(1);

    my %seen;
    for my $r (@records) {
        next if ($seen{$r});
        $item->target_biblio_record_entry($r);
        $e->request('open-ils.cstore.direct.container.biblio_record_entry_bucket_item.create', $item )->gather(1);
        $seen{$r}++;
    }

    $e->request('open-ils.cstore.transaction.commit')->gather(1);
    $e->disconnect;

    # fire the background bucket processor
    my $cache_key = OpenSRF::AppSession
        ->create('open-ils.cat')
        ->request('open-ils.cat.container.template_overlay.background', $authid, $bucket->id)
        ->gather(1);

    return show_processing_template($r, $bucket->id, \@records, $cache_key);
}

sub verify_login {
        my $auth_token = shift;
        return undef unless $auth_token;

        my $user = OpenSRF::AppSession
                ->create("open-ils.auth")
                ->request( "open-ils.auth.session.retrieve", $auth_token )
                ->gather(1);

        if (ref($user) eq 'HASH' && $user->{ilsevent} == 1001) {
                return undef;
        }

        return $user if ref($user);
        return undef;
}

sub show_processing_template {
    my $r = shift;
    my $bid = shift;
    my $recs = shift;
    my $cache_key = shift;

    my $rec_string = @$recs;

    $r->content_type('text/html');
    $r->print(<<HTML);
<html xmlns="http://www.w3.org/1999/xhtml">

    <head>
        <title>Merging records...</title>
        <style type="text/css">
            \@import '/js/dojo/dojo/resources/dojo.css';
            \@import '/js/dojo/dijit/themes/tundra/tundra.css';
            .hide_me { display: none; visibility: hidden; }
            th       { font-weight: bold; }
        </style>

        <script type="text/javascript">
            var djConfig= {
                isDebug: false,
                parseOnLoad: true,
                AutoIDL: ['aou','aout','pgt','au','cbreb']
            }
        </script>

        <script src='/js/dojo/dojo/dojo.js'></script>
        <!-- <script src="/js/dojo/dojo/openils_dojo.js"></script> -->

        <script type="text/javascript">

            dojo.require('fieldmapper.AutoIDL');
            dojo.require('fieldmapper.dojoData');
            dojo.require('openils.User');
            dojo.require('openils.CGI');
            dojo.require('openils.widget.ProgressDialog');

            var cgi = new openils.CGI();
            var u = new openils.User({ authcookie : 'ses' });

            dojo.addOnLoad(function () {
                progress_dialog.show(true);
                progress_dialog.update({maximum:$rec_string});

                var interval;
                interval = setInterval( function() {
                    fieldmapper.standardRequest(
                        ['open-ils.actor','open-ils.actor.anon_cache.get_value'],
                        { async : false,
                          params: [ u.authtoken, 'res_list' ],
                          onerror : function (r) { progress_dialog.hide(); },
                          onresponse : function (r) {
                            var counter = { success : 0, fail : 0, total : 0 };
                            dojo.forEach( openils.Util.readResponse(r), function(x) {
                                if (x.complete) {
                                    clearInterval(interval);
                                    progress_dialog.hide();
                                    if (x.success == 't') dojo.byId('complete_msg').innerHTML = 'Overlay completed successfully';
                                    else dojo.byId('complete_msg').innerHTML = 'Overlay did not complet successfully';
                                } else {
                                    counter.total++;
                                    switch (x.success) {
                                        case 't':
                                            counter.success++;
                                            break;
                                        default:
                                            counter.fail++;
                                            break;
                                    }
                                }
                            });

                            // update the progress dialog
                            progress_dialog.update({progress:counter.total});
                            dojo.byId('success_count').innerHTML = counter.success;
                            dojo.byId('fail_count').innerHTML = counter.fail;
                            dojo.byId('total_count').innerHTML = counter.total;
                          }
                        }
                    );
                }, 1000);

            });
        </script>
    </head>

    <body style="margin:10px;" class='tundra'>
        <div class="hide_me"><div dojoType="openils.widget.ProgressDialog" jsId="progress_dialog"></div></div>

        <table style="width:100%; margin-top:100px;">
            <th>
                <td>Status</td>
                <td>Record Count</td>
            </th>
            <tr>
                <td>Success</td>
                <td id='success_count'></td>
            </tr>
            <tr>
                <td>Failure</td>
                <td id='fail_count'></td>
            </tr>
            <tr>
                <td></td>
                <td id='total_count'></td>
            </tr>
        </table>

        <div id='complete_msg'></div>

    </body>
</html>
HTML

    return Apache2::Const::OK;
}


sub show_template {
    my $r = shift;

    $r->content_type('text/html');
    $r->print(<<'HTML');
<html xmlns="http://www.w3.org/1999/xhtml">

    <head>
        <title>Merge Template Builder</title>
        <style type="text/css">
            @import '/js/dojo/dojo/resources/dojo.css';
            @import '/js/dojo/dijit/themes/tundra/tundra.css';
            .hide_me { display: none; visibility: hidden; }
            table.ruleTable th { padding: 5px; border-collapse: collapse; border-bottom: solid 1px gray; font-weight: bold; }
            table.ruleTable td { padding: 5px; border-collapse: collapse; border-bottom: solid 1px gray; }
        </style>

        <script type="text/javascript">
            var djConfig= {
                isDebug: false,
                parseOnLoad: true,
                AutoIDL: ['aou','aout','pgt','au','cbreb']
            }
        </script>

        <script src='/js/dojo/dojo/dojo.js'></script>
        <!-- <script src="/js/dojo/dojo/openils_dojo.js"></script> -->

        <script type="text/javascript">

            dojo.require('dojo.data.ItemFileReadStore');
            dojo.require('dijit.form.Form');
            dojo.require('dijit.form.NumberSpinner');
            dojo.require('dijit.form.FilteringSelect');
            dojo.require('dijit.form.TextBox');
            dojo.require('dijit.form.Textarea');
            dojo.require('dijit.form.Button');
            dojo.require('MARC.Batch');
            dojo.require('fieldmapper.AutoIDL');
            dojo.require('fieldmapper.dojoData');
            dojo.require('openils.User');
            dojo.require('openils.CGI');

            var cgi = new openils.CGI();
            var u = new openils.User({ authcookie : 'ses' });

            var bucketStore = new dojo.data.ItemFileReadStore(
                { data : cbreb.toStoreData(
                        fieldmapper.standardRequest(
                            ['open-ils.actor','open-ils.actor.container.retrieve_by_class.authoritative'],
                            [u.authtoken, u.user.id(), 'biblio', 'staff_client']
                        )
                    )
                }
            );

            function render_preview () {
                var rec = ruleset_to_record();
                dojo.byId('marcPreview').innerHTML = rec.toBreaker();
            }

            function render_from_template () {
                var kid_number = dojo.byId('ruleList').childNodes.length;
                var clone = dojo.query('*[name=ruleTable]', dojo.byId('ruleTemplate'))[0].cloneNode(true);

                var typeSelect = dojo.query('*[name=typeSelect]',clone).instantiate(dijit.form.FilteringSelect, {
                    onChange : function (val) {
                        switch (val) {
                            case 'a':
                            case 'r':
                                dijit.byNode(dojo.query('*[name=marcDataContainer] .dijit',clone)[0]).attr('disabled',false);
                                break;
                            default :
                                dijit.byNode(dojo.query('*[name=marcDataContainer] .dijit',clone)[0]).attr('disabled',true);
                        };
                        render_preview();
                    }
                })[0];

                var marcData = dojo.query('*[name=marcData]',clone).instantiate(dijit.form.TextBox, {
                    onChange : render_preview
                })[0];


                var tag = dojo.query('*[name=tag]',clone).instantiate(dijit.form.TextBox, {
                    onChange : function (newtag) {
                        var md = dijit.byNode(dojo.query('*[name=marcDataContainer] .dijit',clone)[0]);
                        var current_marc = md.attr('value');

                        if (newtag.length == 3) {
                            if (current_marc.length == 0) newtag += ' \\\\';
                            if (current_marc.substr(0,3) != newtag) current_marc = newtag + current_marc.substr(3);
                        }
                        md.attr('value', current_marc);
                        render_preview();
                    }
                })[0];

                var sf = dojo.query('*[name=sf]',clone).instantiate(dijit.form.TextBox, {
                    onChange : function (newsf) {
                        var md = dijit.byNode(dojo.query('*[name=marcDataContainer] .dijit',clone)[0]);
                        var current_marc = md.attr('value');
                        var sf_list = newsf.split('');

                        for (var i in sf_list) {
                            var re = '\\$' + sf_list[i];
                            if (current_marc.match(re)) continue;
                            current_marc += '$' + sf_list[i];
                        }

                        md.attr('value', current_marc);
                        render_preview();
                    }
                })[0];

                var matchSF = dojo.query('*[name=matchSF]',clone).instantiate(dijit.form.TextBox, {
                    onChange : render_preview
                })[0];

                var matchRE = dojo.query('*[name=matchRE]',clone).instantiate(dijit.form.TextBox, {
                    onChange : render_preview
                })[0];

                var removeButton = dojo.query('*[name=removeButton]',clone).instantiate(dijit.form.Button, {
                    onClick : function() {
                        dojo.addClass(
                            dojo.byId('ruleList').childNodes[kid_number],
                            'hide_me'
                        );
                        render_preview();
                    }
                })[0];

                dojo.place(clone,'ruleList');
            }

            function ruleset_to_record () {
                var rec = new MARC.Record ({ delimiter : '$' });

                dojo.forEach( 
                    dojo.query('#ruleList *[name=ruleTable]').filter( function (node) {
                        if (node.className.match(/hide_me/)) return false;
                        return true;
                    }),
                    function (tbl) {
                        var rule_tag = new MARC.Field ({
                            tag : '905',
                            ind1 : ' ',
                            ind2 : ' '
                        });
                        var rule_txt = dijit.byNode(dojo.query('*[name=tagContainer] .dijit',tbl)[0]).attr('value');
                        rule_txt += dijit.byNode(dojo.query('*[name=sfContainer] .dijit',tbl)[0]).attr('value');

                        var reSF = dijit.byNode(dojo.query('*[name=matchSFContainer] .dijit',tbl)[0]).attr('value');
                        if (reSF) {
                            var reRE = dijit.byNode(dojo.query('*[name=matchREContainer] .dijit',tbl)[0]).attr('value');
                            rule_txt += '[' + reSF + '~' + reRE + ']';
                        }

                        var rtype = dijit.byNode(dojo.query('*[name=typeSelectContainer] .dijit',tbl)[0]).attr('value');
                        rule_tag.addSubfields( rtype, rule_txt )
                        rec.appendFields( rule_tag );

                        if (rtype == 'a' || rtype == 'r') {
                            rec.appendFields(
                                new MARC.Record ({
                                    delimiter : '$',
                                    marcbreaker : dijit.byNode(dojo.query('*[name=marcDataContainer] .dijit',tbl)[0]).attr('value')
                                }).fields[0]
                            );
                        }
                    }
                );

                return rec;
            }
        </script>
    </head>

    <body style="margin:10px;" class='tundra'>

        <div dojoType="dijit.form.Form" id="myForm" jsId="myForm" encType="multipart/form-data" action="" method="POST">
                <script type='dojo/method' event='onSubmit'>
                    var rec = ruleset_to_record();

                    if (rec.subfield('905','r') == '') { // no-op to force replace mode
                        rec.appendFields(
                            new MARC.Field ({
                                tag : '905',
                                ind1 : ' ',
                                ind2 : ' ',
                                subfields : [['r','901c']]
                            })
                        );
                    }

                    dojo.byId('template_value').value = rec.toXmlString();
                    return true;
                </script>

            <input type='hidden' id='template_value' name='template'/>

            <label for='inputTypeSelect'>Record source:</label>
            <select name='recordSource' dojoType='dijit.form.FilteringSelect'>
                <script type='dojo/method' event='onChange' args="val">
                    switch (val) {
                        case 'b':
                            dojo.removeClass('bucketListContainer','hide_me');
                            dojo.addClass('csvContainer','hide_me');
                            dojo.addClass('recordContainer','hide_me');
                            break;
                        case 'c':
                            dojo.addClass('bucketListContainer','hide_me');
                            dojo.removeClass('csvContainer','hide_me');
                            dojo.addClass('recordContainer','hide_me');
                            break;
                        case 'r':
                            dojo.addClass('bucketListContainer','hide_me');
                            dojo.addClass('csvContainer','hide_me');
                            dojo.removeClass('recordContainer','hide_me');
                            break;
                    };
                </script>
                <script type='dojo/method' event='postCreate'>
                    if (cgi.param('recordSource')) {
                        this.attr('value',cgi.param('recordSource'));
                        this.onChange(cgi.param('recordSource'));
                    }
                </script>
                <option value='b'>a Bucket</option>
                <option value='c'>a CSV File</option>
                <option value='r'>a specific record ID</option>
            </select>

            <table style='margin:10px; margin-bottom:20px;'>
<!--
                <tr>
                    <th>Merge template name (optional):</th>
                    <td><input id='bucketName' jsId='bucketName' type='text' dojoType='dijit.form.TextBox' name='bname' value=''/></td>
                </tr>
-->
                <tr class='' id='bucketListContainer'>
                    <td>Bucket named: 
                        <div name='containerid' jsId='bucketList' dojoType='dijit.form.FilteringSelect' store='bucketStore' searchAttr='name' id='bucketList'>
                            <script type='dojo/method' event='postCreate'>
                                if (cgi.param('containerid')) this.attr('value',cgi.param('containerid'));
                            </script>
                        </div>
                    </td>
                </tr>
                <tr class='hide_me' id='csvContainer'>
                    <td>
                        Column <input style='width:75px;' type='text' dojoType='dijit.form.NumberSpinner' name='idcolumn' value='0' constraints='{min:0,max:100,places:0}' /> of: 
                        <input id='idfile' type="file" name="idfile"/>
                        <br/>
                        <br/>
                        Columns are numbered starting at 0.  For instance, when looking at a CSV file in Excel, the column labeled A is the same as column 0, and the column labeled B is the same as column 1.
                    </td>
                </tr>
                <tr class='hide_me' id='recordContainer'>
                    <td>Record ID: <input dojoType='dijit.form.TextBox' name='recid' style='width:75px;' type='text' value=''/></td>
                </tr>
            </table>

            <button type="submit" dojoType='dijit.form.Button'>GO!</button> (After setting up your template below.)

            <br/>
            <br/>

        </div> <!-- end of the form -->

        <hr/>
        <table style='width: 100%'>
            <tr>
                <td style='width: 50%'><div id='ruleList'></div></td>
                <td valign='top'>Update Template Preview:<br/><pre id='marcPreview'></pre></td>
            </tr>
        </table>

        <button dojoType='dijit.form.Button'>Add Merge Rule
            <script type='dojo/connect' event='onClick'>render_from_template()</script>
            <script type='dojo/method' event='postCreate'>render_from_template()</script>
        </button>

        <div class='hide_me' id='ruleTemplate'>
        <div name='ruleTable'>
            <table class='ruleTable'>
                <tbody>
                    <tr>
                        <th style="text-align:center;">Rule Setup</th>
                        <th style="text-align:center;">Data</th>
                        <th style="text-align:center;">Help</th>
                    </tr>
                    <tr>
                        <th>Action (Rule Type)</th>
                        <td name='typeSelectContainer'>
                            <select name='typeSelect'>
                                <option value='r'>Replace</option>
                                <option value='a'>Add</option>
                                <option value='d'>Delete</option>
                            </select>
                        </td>
                        <td>How to change the existing records</td>
                    </tr>
                    <tr>
                        <th>MARC Tag</th>
                        <td name='tagContainer'><input style='with: 2em;' name='tag' type='text'></input</td>
                        <td>Three characters, no spaces, no indicators, etc. eg: 245</td>
                    </td>
                    <tr>
                        <th>Subfields (optional)</th>
                        <td name='sfContainer'><input name='sf' type='text'/></td>
                        <td>No spaces, no delimiters, eg: abcnp</td>
                    </tr>
                    <tr>
                        <th>MARC Data</th>
                        <td name='marcDataContainer'><input name='marcData' type='text'/></td>
                        <td>MARC-Breaker formatted data with indicators and subfield delimiters, eg:<br/>245 04$aThe End</td>
                    </tr>
                    <tr>
                        <th colspan='3' style='padding-top: 20px; text-align: center;'>Advanced Matching Restriction (Optional)</th>
                    </tr>
                    <tr>
                        <th>Subfield</th>
                        <td name='matchSFContainer'><input style='with: 2em;' name='matchSF' type='text'></input</td>
                        <td>A single subfield code, no delimiters, eg: a</td>
                    <tr>
                        <th>Regular Expression</th>
                        <td name='matchREContainer'><input name='matchRE' type='text'/></td>
                        <td>See <a href="http://perldoc.perl.org/perlre.html#Regular-Expressions" target="_blank">the Perl documentation</a>
                            for an explanation of Regular Expressions.
                        </td>
                    </tr>
                    <tr>
                        <td colspan='3' style='padding-top: 20px; text-align: center;'>
                            <button name='removeButton'>Remove this Template Rule</button>
                        </td>
                    </tr>
                </tbody>
            </table>
        <hr/>
        </div>
        </div>

    </body>
</html>
HTML

    return Apache2::Const::OK;
}

1;


