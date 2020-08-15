import {Component, ViewChild, OnInit} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {GridDataSource} from '@eg/share/grid/grid';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {CourseService} from '@eg/staff/share/course.service';
import {CourseAssociateUsersComponent} from './course-associate-users.component';
import {CourseAssociateMaterialComponent} from './course-associate-material.component';
import {Pager} from '@eg/share/util/pager';

@Component({
    selector: 'eg-course-page',
    templateUrl: './course-page.component.html'
})

export class CoursePageComponent implements OnInit {

    currentCourse: IdlObject;
    courseId: any;

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

    // Course Tab
    termsDataSource: GridDataSource = new GridDataSource();
    defaultNewAcmtcm: IdlObject;

    constructor(
        private course: CourseService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private route: ActivatedRoute,
        private toast: ToastService
    ) {
    }

    ngOnInit() {
        this.courseId = +this.route.snapshot.paramMap.get('id');
        this.course.getCourses([this.courseId]).then(course => {
            this.currentCourse = course[0];
        });

        this.defaultNewAcmtcm = this.idl.create('acmtcm');
        this.defaultNewAcmtcm.course(this.courseId);

        this.termsDataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};
            if (sort.length) {
                orderBy.acmtcm = sort[0].name + ' ' + sort[0].dir;
            }
            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };

            return this.pcrud.search('acmtcm', {course: this.courseId},
                searchOps, {fleshSelectors: true});
        };
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
