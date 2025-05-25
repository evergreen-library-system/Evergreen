import {Component, ViewChild, OnInit} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlObject} from '@eg/core/idl.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {CourseService} from '@eg/staff/share/course.service';
import {CourseAssociateUsersComponent} from './course-associate-users.component';
import {CourseAssociateMaterialComponent} from './course-associate-material.component';

@Component({
    selector: 'eg-course-page',
    templateUrl: './course-page.component.html'
})

export class CoursePageComponent implements OnInit {

    currentCourse: IdlObject;
    courseId: any;
    courseIsArchived: String;

    // Materials Tab
    @ViewChild('courseMaterialDialog', {static: true})
    private courseMaterialDialog: CourseAssociateMaterialComponent;
    @ViewChild('courseUserDialog', {static: true})
    private courseUserDialog: CourseAssociateUsersComponent;

    // Edit Tab
    @ViewChild('archiveFailedString', { static: true })
        archiveFailedString: StringComponent;
    @ViewChild('archiveSuccessString', { static: true })
        archiveSuccessString: StringComponent;
    @ViewChild('unarchiveFailedString', { static: true })
        unarchiveFailedString: StringComponent;
    @ViewChild('unarchiveSuccessString', { static: true })
        unarchiveSuccessString: StringComponent;

    constructor(
        private course: CourseService,
        private pcrud: PcrudService,
        private route: ActivatedRoute,
        private toast: ToastService
    ) {
    }

    ngOnInit() {
        this.courseId = +this.route.snapshot.paramMap.get('id');
        this.course.getCourses([this.courseId]).then(course => {
            this.currentCourse = course[0];
            this.courseIsArchived = course[0].is_archived();
            console.log(this.courseIsArchived);
        });
    }

    // Edit Tab
    archiveCourse() {
        this.course.disassociateMaterials([this.currentCourse]).then(res => {
            this.currentCourse.is_archived('t');
            this.pcrud.update(this.currentCourse).subscribe({ next: val => {
                this.courseIsArchived = 't';
                console.debug('archived: ' + val);
                this.archiveSuccessString.current()
                    .then(str => this.toast.success(str));
            }, error: (err: unknown) => {
                this.archiveFailedString.current()
                    .then(str => this.toast.danger(str));
            } });
        });
    }

    unarchiveCourse() {
        this.course.disassociateMaterials([this.currentCourse]).then(res => {
            this.currentCourse.is_archived('f');
            this.pcrud.update(this.currentCourse).subscribe({ next: val => {
                this.courseIsArchived = 'f';
                console.debug('archived: ' + val);
                this.course.removeNonPublicUsers(this.currentCourse.id());
                this.unarchiveSuccessString.current()
                    .then(str => this.toast.success(str));
            }, error: (err: unknown) => {
                this.unarchiveFailedString.current()
                    .then(str => this.toast.danger(str));
            } });
        });
    }

    // Materials Tab

}
