package OpenILS::WWW::FlatFielder;

use strict;
use warnings;

use Apache2::Log;
use Apache2::Const -compile => qw(
    OK HTTP_NOT_ACCEPTABLE HTTP_PAYMENT_REQUIRED HTTP_INTERNAL_SERVER_ERROR :log
);
use XML::LibXML;
use XML::LibXSLT;
use Text::Glob;
use CGI qw(:all -utf8);

use OpenSRF::Utils::JSON;
use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;

use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';


my $_parser = new XML::LibXML;
my $_xslt = new XML::LibXSLT;

# BEGIN package globals

# We'll probably never need this fanciness for autosuggest, but
# you can add handlers for different requested content-types here, and
# you can weight them to control what matches requests for things like
# 'application/*'


sub html_ish_output {
    my ($r, $args, $xslt) = @_;
    $args->{'stylesheet'} =
        OpenSRF::Utils::SettingsClient->new->config_value(dirs => 'xsl') . '/' . $xslt;
    print data_to_xml($args);
    return Apache2::Const::OK;
}

my $_output_handler_dispatch = {
    "text/csv" => {
        "prio" => 0,
        "code" => sub {
            my ($r, $args) = @_;
            $r->headers_out->set("Content-Disposition" => "attachment; filename=FlatSearch.csv");
            # Anecdotally, IE 8 needs name= here to provoke downloads, where
            # other browswers respect filename= in Content-Disposition.  Also,
            # we might want to make the filename choosable by CGI param later?
            # Or vary it by timestamp?
            $r->content_type('text/csv; name=FlatSearch.csv; charset=utf-8');
            print_data_as_csv($args, \*STDOUT);
            return Apache2::Const::OK;
        }
    },
    "text/html" => {
        "prio" => 0,
        "code" => sub {
            $_[0]->content_type("text/html; charset=utf-8");
            return html_ish_output( @_, 'FlatFielder2HTML.xsl' );
        }
    },
    "application/xml" => {
        "prio" => 0,
        "code" => sub {
            my ($r, $args) = @_;
            $r->content_type("application/xml; charset=utf-8");
            print data_to_xml($args);
            return Apache2::Const::OK;
        }
    },
    "application/json" => {
        "prio" => 1,
        "code" => sub {
            my ($r, $args) = @_;
            $r->content_type("application/json; charset=utf-8");
            print data_to_json($args);
            return Apache2::Const::OK;
        }
    }
};

my @_output_handler_types = sort {
    $_output_handler_dispatch->{$a}->{prio} <=>
        $_output_handler_dispatch->{$b}->{prio}
} keys %$_output_handler_dispatch;

# END package globals

=comment

<FlatSearch hint='foo' identifier='bar' label='Foo Bar' FS_key='ad1awe43a3a2a3ra32a23ra32ra23rar23a23r'>
  <row ordinal='1'>
    <column name='fiz'>YAY!</column>
    <column name='faz'>boooo</column>
  </row>
  <row ordinal='2'>
    <column name='fiz'>WHEEE!</column>
    <column name='faz'>noooo</column>
  </row>
</FlatSearch>

=cut

sub data_to_xml {
    my ($args) = @_;

    my $dom = new XML::LibXML::Document("1.0", "UTF-8");
    my $fs = $dom->createElement("FlatSearch");
    $fs->setAttribute("hint", $args->{hint}) if $args->{hint};
    $fs->setAttribute("identifier", $args->{id_field}) if $args->{id_field};
    $fs->setAttribute("label", $args->{label_field}) if $args->{label_field};
    $fs->setAttribute("FS_key", $args->{key}) if $args->{key};
    $dom->setDocumentElement($fs);

    my @columns;
    my %column_labels;
    if (@{$args->{columns}}) {
        @columns = @{$args->{columns}};
        if (@{$args->{labels}}) {
            my @labels = @{$args->{labels}};
            $column_labels{$columns[$_]} = $labels[$_] for (0..$#labels);
        }
    }

    my $rownum = 1;
    for my $i (@{$$args{data}}) {
        my $item = $dom->createElement("row");
        $item->setAttribute('ordinal', $rownum);
        $rownum++;
        @columns = keys %$i unless @columns;
        for my $k (@columns) {
            my $val = $dom->createElement('column');
            my $datum = $i->{$k};
            $datum = join(" ", @$datum) if ref $datum eq 'ARRAY';

            $val->setAttribute('name', $column_labels{$k} || $k);
            $val->appendText($datum);
            $item->addChild($val);
        }
        $fs->addChild($item);
    }

    # XML::LibXML::Document::toString() returns an encoded byte string, which
    # is why we don't need to binmode STDOUT, ':utf8'.

    return $_xslt->parse_stylesheet(
        $_parser->parse_file( $$args{stylesheet} )
    )->transform(
        $dom
    )->toString if ($$args{stylesheet}); # configured transform, early return

    return $dom->toString();
}

sub print_data_as_csv {
    my ($args, $fh) = @_;

    my @keys = sort keys %{ $$args{data}[0] };
    return unless @keys;

    my $csv = new Text::CSV({ always_quote => 1, eol => "\r\n" });

    $csv->print($fh, \@keys);

    for my $row (@{$$args{data}}) {
        $csv->print($fh, [map { $row->{$_} } @keys]);
    }
}

sub data_to_json {
    my ($args) = @_;

    # Turns out we don't want the data structure you'd use to initialize an
    # itemfilereadstore or similar. We just want rows.

#    return OpenSRF::Utils::JSON->perl2JSON({
#        ($$args{hint} ? (hint => $$args{hint}) : ()),
#        ($$args{id_field} ? (identifier => $$args{id_field}) : ()),
#        ($$args{label_field} ? (label => $$args{label_field}) : ()),
#        ($$args{key} ? (FS_key => $$args{key}) : ()),
#        items => $$args{data}
#    });
    return OpenSRF::Utils::JSON->perl2JSON($args->{data});
}

# Given data and the Apache request object, this sub picks a sub from a
# dispatch table based on the list of content-type encodings that the client
# has indicated it will accept, and calls that sub, which will deliver
# a response of appropriately encoded data.
sub output_handler {
    my ($r, $args) = @_;

    my @types = split /,/, $r->headers_in->{Accept};

    if ($$args{format}) {
        unshift @types, $$args{format};
    }

    foreach my $media_range (@types) {
        $media_range =~ s/;.+$//; # keep type, subtype. lose parameters.

        my ($match) = grep {
            Text::Glob::match_glob($media_range, $_)
        } @_output_handler_types;

        if ($match) {
            return $_output_handler_dispatch->{$match}{code}->($r, $args);
        }
    }

    return Apache2::Const::HTTP_NOT_ACCEPTABLE;
}

sub handler {
    my $r = shift;
    my $cgi = new CGI;

    my %args;
    $args{format} = $cgi->param('format');
    $args{auth} = $cgi->param('ses');
    $args{hint} = $cgi->param('hint');
    $args{map} = OpenSRF::Utils::JSON->JSON2perl($cgi->param('map'));
    $args{where} = OpenSRF::Utils::JSON->JSON2perl($cgi->param('where'));
    $args{slo} = OpenSRF::Utils::JSON->JSON2perl($cgi->param('slo'));
    $args{key} = $cgi->param('key');
    $args{id_field} = $cgi->param('identifier');
    $args{label_field} = $cgi->param('label');
    $args{columns} = [ $cgi->param('columns') ];
    $args{labels} = [ $cgi->param('labels') ];

    my $fielder = OpenSRF::AppSession->create('open-ils.fielder');
    if ($args{map}) {
        $args{data} = $fielder->request(
            'open-ils.fielder.flattened_search.atomic',
            @args{qw/auth hint map where slo/}
        )->gather(1);
    } else {
        $args{data} = $fielder->request(
            'open-ils.fielder.flattened_search.execute.atomic',
            @args{qw/auth key where slo/}
        )->gather(1);

        if (ref $args{data} and $args{data}[0] and
            $U->event_equals($args{data}[0], 'CACHE_MISS')) {

            # You have to pay the cache! I kill me.
            return Apache2::Const::HTTP_PAYMENT_REQUIRED;
        }
    }

    return output_handler( $r, \%args );

}

1;
