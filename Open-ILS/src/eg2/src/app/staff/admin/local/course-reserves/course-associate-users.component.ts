import {Component, Input, ViewChild, OnInit, TemplateRef} from '@angular/core';
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
import {ToastService} from '@eg/share/toast/toast.service';
import {CourseService} from '@eg/staff/share/course.service';

@Component({
    selector: 'eg-course-associate-users-dialog',
    templateUrl: './course-associate-users.component.html'
})

export class CourseAssociateUsersComponent extends DialogComponent {

    @ViewChild('usersGrid', {static: true}) usersGrid: GridComponent;
    @ViewChild('deleteFailedString', { static: true }) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', { static: true }) deleteSuccessString: StringComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('failedString', { static: true }) failedString: StringComponent;
    @ViewChild('differentLibraryString', { static: true }) differentLibraryString: StringComponent;
    @Input() table_name = "Course Users";
    @Input() userRoleInput: String;
    
    idl_class = "acmcu";
    new_usr:any;
    currentCourse: IdlObject;
    users: any[];
    gridDataSource: GridDataSource;

    constructor(
        private auth: AuthService,
        private idl: IdlService,
        private net: NetService,
        private pcrud: PcrudService,
        private org: OrgService,
        private evt: EventService,
        private modal: NgbModal,
        private toast: ToastService,
        private courseSvc: CourseService
    ) {
        super(modal);
        this.gridDataSource = new GridDataSource();
    }

    ngOnInit() {
    }

    /**
     * Takes the user id and creates a course user based around it.
     * @param user_input The inputted user Id.
     */
    associateUsers(user_input) {
        if (user_input) {
            let user = this.idl.create('acmcu');
            user.course(this.currentCourse.id());
            user.usr(this.new_usr);
            user.usr_role(user_input);
            this.pcrud.create(user).subscribe(
            val => {
               console.debug('created: ' + val);
               this.successString.current().then(str => this.toast.success(str));
            }, err => {
                this.failedString.current().then(str => this.toast.danger(str));
            })
        }
    }

    /**
     * Delete a user based on the id selected from the grid.
     * @param users 
     */
    deleteSelected(users) {
        let user_ids = [];
        users.forEach(user => {
            this.gridDataSource.data.splice(this.gridDataSource.data.indexOf(user, 0), 1);
            user_ids.push(user.id())
        });
        this.pcrud.remove(users).subscribe(user => {
            this.pcrud.autoApply(user).subscribe(
                val => {
                    console.debug('deleted: ' + val);
                    this.deleteSuccessString.current().then(str => this.toast.success(str));
                },
                err => {
                    this.deleteFailedString.current()
                        .then(str => this.toast.danger(str));
                }
            );
        });
    }

}