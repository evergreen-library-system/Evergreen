import {Component, Input, ViewChild, OnInit, TemplateRef} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {Observable, Observer, of} from 'rxjs';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {Pager} from '@eg/share/util/pager';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {StringComponent} from '@eg/share/string/string.component';
import {StaffBannerComponent} from '@eg/staff/share/staff-banner.component';
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

    @ViewChild('courseMaterialDialog', {static: true})
        private courseMaterialDialog: CourseAssociateMaterialComponent;
    @ViewChild('courseUserDialog', {static: true})
        private courseUserDialog: CourseAssociateUsersComponent;
    
    // Edit Tab
    @ViewChild('archiveFailedString', { static: true })
        archiveFailedString: StringComponent;
    @ViewChild('archiveSuccessString', { static: true })
        archiveSuccessString: StringComponent;

    // Materials Tab

    constructor(
        private auth: AuthService,
        private course: CourseService,
        private event: EventService,
        private idl: IdlService,
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService,
        private route: ActivatedRoute,
        private toast: ToastService
    ) {
    }

    ngOnInit() {
        this.courseId = parseInt(this.route.snapshot.paramMap.get('id'));
        this.course.getCourses([this.courseId]).then(course => {
            this.currentCourse = course[0];
        });
    }

    // Edit Tab
    archiveCourse() {
        this.course.disassociateMaterials([this.currentCourse]).then(res => {
            this.currentCourse.is_archived('t');
            this.pcrud.update(this.currentCourse).subscribe(val => {
                console.debug('archived: ' + val);
                this.archiveSuccessString.current()
                    .then(str => this.toast.success(str));
            }, err => {
                this.archiveFailedString.current()
                    .then(str => this.toast.danger(str));
            });
        });
    }

    // Materials Tab
    
}