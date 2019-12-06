package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_GONE HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST HTTP_NOT_FOUND);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use Net::HTTP::NB;
use IO::Select;
my $U = 'OpenILS::Application::AppUtils';

sub load_course {
    my $self = shift;
    my $ctx = $self->ctx;

    $ctx->{page} = 'course';
    $ctx->{readonly} = $self->cgi->param('readonly');

    my $course_id = $ctx->{page_args}->[0];

    return Apache2::Const::HTTP_BAD_REQUEST
        unless $course_id and $course_id =~ /^\d+$/;

    $ctx->{course} = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.courses.retrieve',
        [$course_id]
    )->[0];
    
    $ctx->{instructors} = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.course_users.retrieve',
        $course_id
    );

    $ctx->{course_materials} = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.course_materials.retrieve.fleshed',
        {course => $course_id}
    );
    return Apache2::Const::OK;
}