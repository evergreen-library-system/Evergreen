# Copyright (C) 2019 BC Libraries Cooperative
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

# ====================================================================== 
# Template Toolkit processing for RemoteAuth
# ====================================================================== 

package OpenILS::WWW::RemoteAuth::Template;
use strict; use warnings;

use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN AUTH_REQUIRED HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use List::MoreUtils qw/uniq/;
use Template;

sub new {
    my( $class, $args ) = @_;
    $args ||= {};
    $class = ref $class || $class;
    return bless($args, $class);
}

sub process {
    my ($self, $tname, $ctx, $r) = @_;

    if (!$tname) {
        $r->log->warn('RemoteAuth template name not defined');
        return Apache2::Const::DECLINED;
    }

    my $template;
    my @template_paths = uniq $r->dir_config->get('OILSRemoteAuthTemplatePath');
    for my $tpath (reverse @template_paths) {
        if (-r "$tpath/$tname.tt2") {
            $template = "$tname.tt2";
            $ctx->{template_path} = $tpath;
            last;
        }
    }
    if (!$template) {
        $r->log->warn("RemoteAuth template $tname not found");
        return Apache2::Const::DECLINED;
    }

    $ctx->{locale} = $r->dir_config('OILSRemoteAuthLocale') || 'en_us';

    # create template processor
    my $tt = Template->new({
        ENCODING => 'utf-8',
        INCLUDE_PATH => $ctx->{template_path}
    });

    if (!$tt) {
        $r->log->error("Error creating RemoteAuth template processor: $@");
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }   

    # process template
    unless($tt->process($template, { ctx => $ctx }, $r)) {
        $r->log->warn('RemoteAuth template error: ' . $tt->error);
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }

    return Apache2::Const::OK;
}

1;

