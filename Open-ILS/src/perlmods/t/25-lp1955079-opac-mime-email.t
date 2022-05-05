#!perl -T

use strict; use warnings;
use Test::More tests => 4;

BEGIN {
  use_ok( 'OpenILS::Application::Search' );
}

use_ok( 'OpenILS::Application::Search::Biblio' );
can_ok( 'OpenILS::Application::Search::Biblio', '_create_mime_email' );

my $raw_email = <<'END_EMAIL';
To: test@example.com
From: no-reply@localhost.com
Date: Thu, 05 May 2022 18:21:48 -0000
Subject: Bibliographic Records
Auto-Submitted: auto-generated
END_EMAIL

my @expected_headers = [
  'To' => 'test@example.com',
  'From' => 'no-reply@localhost.com',
  'Date' => 'Thu, 05 May 2022 18:21:48 -0000',
  'Subject' => 'Bibliographic Records',
  'Auto-Submitted' => 'auto-generated',
  'MIME-Version' => '1.0',
  'Content-Type' => 'text/plain; charset=UTF-8',
  'Content-Transfer-Encoding' => '8bit'
];

my $mime_email = OpenILS::Application::Search::Biblio::_create_mime_email($raw_email);
my @actual_headers = $mime_email->header_str_pairs;

is_deeply(\@actual_headers, @expected_headers, 'Headers do not get mangled in the process');

1;

