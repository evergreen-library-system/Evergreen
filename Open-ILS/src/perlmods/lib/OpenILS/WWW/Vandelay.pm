package OpenILS::WWW::Vandelay;
use strict;
use warnings;
use bytes;

use Apache2::Log;
use Apache2::Const -compile => qw(OK REDIRECT DECLINED NOT_FOUND AUTH_REQUIRED FORBIDDEN HTTP_UNAUTHORIZED HTTP_REQUEST_ENTITY_TOO_LARGE HTTP_INTERNAL_SERVER_ERROR :log);
use APR::Const    -compile => qw(:error SUCCESS);
use APR::Table;

use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::RequestUtil;
use CGI;
use Data::Dumper;
use Text::CSV;
use GD;

use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Cache;
use OpenSRF::System;
use OpenSRF::AppSession;
use XML::LibXML;

use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger qw/$logger/;

use MARC::Record;
use MARC::File::XML ( BinaryEncoding => 'UTF-8' );

use MIME::Base64;
use Digest::MD5 qw/md5_hex/;
use OpenSRF::Utils::SettingsClient;

use UNIVERSAL::require;

our @formats = qw/USMARC UNIMARC XML BRE/;
my $MAX_FILE_SIZE = 10737418240; #10G
my $MAX_JACKET_SIZE = 10737418240; #10G
my $FILE_READ_SIZE = 4096;

# set the bootstrap config and template include directory when
# this module is loaded
my $bootstrap;

sub import {
        my $self = shift;
        $bootstrap = shift;
}


sub child_init {
        OpenSRF::System->bootstrap_client( config_file => $bootstrap );
        return Apache2::Const::OK;
}

sub spool_marc {
    my $r = shift;
    my $cgi = new CGI;

    my $auth = $cgi->param('ses') || $cgi->cookie('ses') || $cgi->cookie('eg.auth.token');
    if ($auth =~ /^"(.+)"$/) {
        $auth = $1;
    }

    unless(verify_login($auth)) {
        $logger->error("authentication failed on vandelay record import: $auth");
        return Apache2::Const::FORBIDDEN;
    }

    my $data_fingerprint = '';
    my $purpose = $cgi->param('purpose') || '';
    my $infile = $cgi->param('marc_upload') || '';
    my $bib_source = $cgi->param('bib_source') || '';

    $logger->debug("purpose = $purpose, infile = $infile, bib_source = $bib_source");

    my $conf = OpenSRF::Utils::SettingsClient->new;
    my $dir = $conf->config_value(
        apps => 'open-ils.vandelay' => app_settings => databases => 'importer');

    unless(-w $dir) {
        $logger->error("We need some place to store our MARC files");
        return Apache2::Const::FORBIDDEN;
    }

    if($infile and -e $infile) {
        my ($total_bytes, $buf, $bytes) = (0);
        $data_fingerprint = md5_hex(time."$$".rand());
        my $outfile = "$dir/$data_fingerprint.mrc";

        unless(open(OUTFILE, ">$outfile")) {
            $logger->error("unable to open MARC file [$outfile] for writing: $@");
            return Apache2::Const::FORBIDDEN;
        }

        while($bytes = sysread($infile, $buf, $FILE_READ_SIZE)) {
            $total_bytes += $bytes;
            if($total_bytes >= $MAX_FILE_SIZE) {
                close(OUTFILE);
                unlink $outfile;
                $logger->error("import exceeded upload size: $MAX_FILE_SIZE");
                return Apache2::Const::FORBIDDEN;
            }
            print OUTFILE $buf;
        }

        close(OUTFILE);

        OpenSRF::Utils::Cache->new->put_cache(
            'vandelay_import_spool_' . $data_fingerprint,
            {   purpose => $purpose, 
                path => $outfile,
                bib_source => $bib_source,
            }
        );
    }

    $logger->info("uploaded MARC batch with key $data_fingerprint");
    $r->content_type('text/plain; charset=utf-8');
    print "$data_fingerprint";
    return Apache2::Const::OK;
}

sub spool_jacket {
    my $r = shift;
    my $cgi = new CGI;

    my $auth = $cgi->param('ses') || $cgi->cookie('ses') || $cgi->cookie('eg.auth.token');
    if ($auth =~ /^"(.+)"$/) {
        $auth = $1;
    }
    my $user = verify_login($auth);
    my $perm_check = verify_permission($auth, $user, $user->ws_ou, ['UPLOAD_COVER_IMAGE']);

    unless($user) {
        $logger->error("spool_jacket: authentication failed on jacket image import: $auth");
        print '"session not found"';
        return Apache2::Const::OK;
    }
    unless($perm_check) {
        $logger->error("spool_jacket: authorization failed on jacket image import: $auth");
        print '"permission denied"';
        return Apache2::Const::OK;
    }

    my $ses = OpenSRF::AppSession->create('open-ils.cstore');
    my $compression_flag = $ses->request( 'open-ils.cstore.direct.config.global_flag.retrieve', 'opac.cover_upload_compression' )->gather(1);
    my $compression_level = ($compression_flag && OpenILS::Application::AppUtils->is_true($compression_flag->enabled)) ? $compression_flag->value : -1;
    if ($compression_level < -1 || $compression_level > 9) {
        $r->content_type('text/plain; charset=utf-8');
        print '"invalid compression level"';
        return Apache2::Const::OK;
    }
    $logger->debug("spool_jacket: PNG compression set to $compression_level");

    my $max_jacket_size = OpenILS::Application::AppUtils->ou_ancestor_setting_value($user->ws_ou, 'opac.cover_upload_max_file_size') || $MAX_JACKET_SIZE;

    my $infile = $cgi->param('jacket_upload') || '';
    my $bib_record = $cgi->param('bib_record') || '';
    unless ($bib_record =~ /^-?\d+$/) {
        $logger->error("spool_jacket: passed bib_record = $bib_record");
        $r->content_type('text/plain; charset=utf-8');
        print '"bib not found"';
        return Apache2::Const::OK;
    }

    $logger->debug("infile = $infile, bib_record = $bib_record");

    my $conf = OpenSRF::Utils::SettingsClient->new;
    my $dir = $conf->config_value(
        apps => 'open-ils.vandelay' => app_settings => databases => 'jackets');

    unless(-w $dir) { # FIXME: good or bad idea to fallback to /openils/var/web/opac/extracs/ac if opensrf.xml is not updated?
        $logger->error("spool_jacket: We need some place to store our jacket files");
        print '"jacket location not configured"';
        return Apache2::Const::OK;
    }

    if($infile and -e $infile) {
        my $memcache = OpenSRF::Utils::Cache->new('global');

        my ($total_bytes, $buf, $bytes) = (0);
        my $outfile_large = "$dir/jacket/large/r/$bib_record";
        my $outfile_medium = "$dir/jacket/medium/r/$bib_record";
        my $outfile_small = "$dir/jacket/small/r/$bib_record";

        unless(open(OUTFILE_LARGE, ">$outfile_large.temp")) {
            $logger->error("spool_jacket: unable to open jacket file [$outfile_large.temp] for writing: $@");
            return Apache2::Const::FORBIDDEN;
            print '"unable to open file for writing"';
            return Apache2::Const::OK;
        }

        while($bytes = sysread($infile, $buf, $FILE_READ_SIZE)) {
            $total_bytes += $bytes;
            if($total_bytes >= $max_jacket_size) {
                close(OUTFILE_LARGE);
                unlink $outfile_large . ".temp";
                $logger->error("spool_jacket: import exceeded upload size: $max_jacket_size");
                print '"file too large"';
                return Apache2::Const::OK;
            }
            print OUTFILE_LARGE $buf;
        }

        close(OUTFILE_LARGE);

        my $image;
        eval { $image = GD::Image->newFromPng("$outfile_large.temp"); };
        eval { $image = $image || GD::Image->newFromJpeg("$outfile_large.temp"); };
        eval { $image = $image || GD::Image->newFromGif("$outfile_large.temp"); };
        eval { $image = $image || GD::Image->newFromXpm("$outfile_large.temp"); };
        eval { $image = $image || GD::Image->newFromWBMP("$outfile_large.temp"); };
        eval { $image = $image || GD::Image->newFromXbm("$outfile_large.temp"); };
        eval { $image = $image || GD::Image->newFromGd("$outfile_large.temp"); };
        eval { $image = $image || GD::Image->newFromGd2("$outfile_large.temp"); };
        unless ($image) {
            unlink $outfile_large . ".temp";
            $logger->error("spool_jacket: unable to parse $outfile_large.temp");
            $r->content_type('text/plain; charset=utf-8');
            print '"parse error"';
            return Apache2::Const::OK;
        }

        my ($image_width, $image_height) = $image->getBounds();

        #### resizing for small

        my $target_width = 55; # FIXME: get these from settings, but for now, using customer desired width and aspect ratio observed from OpenLibrary
        my $target_height = 91;

        my $width_ratio = $target_width / $image_width;
        my $height_ratio = $target_height / $image_height;

        my $best_ratio = $width_ratio < $height_ratio ? $width_ratio : $height_ratio;

        my ($new_width, $new_height) = ($image_width * $best_ratio, $image_height * $best_ratio);

        my $new_image = $image->copyScaleInterpolated($new_width, $new_height);

        unless(open(OUTFILE_SMALL, ">$outfile_small.temp")) {
            $logger->error("spool_jacket: unable to open jacket file [$outfile_small.temp] for writing: $@");
            print '"unable to open file for writing"';
            return Apache2::Const::OK;
        }
        print OUTFILE_SMALL $new_image->png($compression_level);
        close(OUTFILE_SMALL);

        #### resizing for medium

        $target_width = 120;
        $target_height = 200;

        $width_ratio = $target_width / $image_width;
        $height_ratio = $target_height / $image_height;

        $best_ratio = $width_ratio < $height_ratio ? $width_ratio : $height_ratio;

        ($new_width, $new_height) = ($image_width * $best_ratio, $image_height * $best_ratio);

        $new_image = $image->copyScaleInterpolated($new_width, $new_height);

        unless(open(OUTFILE_MEDIUM, ">$outfile_medium.temp")) {
            $logger->error("spool_jacket: unable to open jacket file [$outfile_medium.temp] for writing: $@");
            print '"unable to open file for writing"';
            return Apache2::Const::OK;
        }
        print OUTFILE_MEDIUM $new_image->png($compression_level);
        close(OUTFILE_MEDIUM);

        #### resizing for large

        $target_width = 475;
        $target_height = 787;

        $width_ratio = $target_width / $image_width;
        $height_ratio = $target_height / $image_height;

        $best_ratio = $width_ratio < $height_ratio ? $width_ratio : $height_ratio;

        ($new_width, $new_height) = ($image_width * $best_ratio, $image_height * $best_ratio);

        $new_image = $image->copyScaleInterpolated($new_width, $new_height);

        unless(open(OUTFILE_LARGE, ">$outfile_large.temp")) {
            $logger->error("spool_jacket: unable to open jacket file [$outfile_large.temp] for writing: $@");
            print "'unable to open file for writing'\n";
            return Apache2::Const::OK;
        }
        print OUTFILE_LARGE $new_image->png($compression_level);
        close(OUTFILE_LARGE);

        #### renaming temp files to final images

        rename "$outfile_small.temp", $outfile_small;
        rename "$outfile_medium.temp", $outfile_medium;
        rename "$outfile_large.temp", $outfile_large;

        #### clearing memcache

        my @jacket_sizes = ('large','medium','small');
        foreach my $size (@jacket_sizes) {
            my $key = "ac.jacket.$size.record_$bib_record";
            $memcache->delete_cache($key);
        }

    } else {
        $logger->error("spool_jacket: image not uploaded? check form action and encoding");
        print '"upload error"';
        return Apache2::Const::OK;
    }

    $logger->info("spool_jacket: uploaded jacket file for record $bib_record");
    $r->content_type('text/plain; charset=utf-8');
    print "1";
    return Apache2::Const::OK;
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

sub verify_permission { # FIXME: could refactor these verify_ subs in WWW/
    my ($token, $user, $org_unit, $permissions) = @_;

    my $failures = OpenSRF::AppSession
        ->create('open-ils.actor')
        ->request('open-ils.actor.user.perm.check', $token, $user->id, $org_unit, $permissions)
        ->gather(1);

    return !scalar(@$failures);
}

1;
