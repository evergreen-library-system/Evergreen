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
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {CourseService} from '@eg/staff/share/course.service';

@Component({
    selector: 'eg-course-associate-users-dialog',
    templateUrl: './course-associate-users.component.html'
})

export class CourseAssociateUsersComponent extends DialogComponent implements OnInit {
    @Input() currentCourse: IdlObject;
    @Input() courseId: any;
    @Input() displayMode: String;
    users: any[] = [];
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('usersGrid', {static: true}) usersGrid: GridComponent;
    @ViewChild('userDeleteFailedString', { static: true })
        userDeleteFailedString: StringComponent;
    @ViewChild('userDeleteSuccessString', { static: true })
        userDeleteSuccessString: StringComponent;
    @ViewChild('userAddSuccessString', { static: true })
        userAddSuccessString: StringComponent;
    @ViewChild('userAddFailedString', { static: true })
        userAddFailedString: StringComponent;
    @ViewChild('userEditSuccessString', { static: true })
        userEditSuccessString: StringComponent;
    @ViewChild('userEditFailedString', { static: true })
        userEditFailedString: StringComponent;
    usersDataSource: GridDataSource;
    @Input() userBarcode: String;
    @Input() userRoleInput: String;
    @Input() isPublicRole: Boolean;

    constructor(
        private auth: AuthService,
        private course: CourseService,
        private event: EventService,
        private idl: IdlService,
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService,
        private route: ActivatedRoute,
        private toast: ToastService,
        private modal: NgbModal
    ) {
        super(modal);
        this.usersDataSource = new GridDataSource();
    }

    ngOnInit() {
        this.usersDataSource.getRows = (pager: Pager, sort: any[]) => {
            return this.loadUsersGrid(pager);
        }
    }

    isDialog(): boolean {
        return this.displayMode === 'dialog';
    }

    loadUsersGrid(pager: Pager): Observable<any> {
        return new Observable<any>(observer => {
            this.course.getUsers(this.courseId).then(users => {
                users.forEach(user => {
                    this.course.fleshUser(user).then(fleshed_user => {
                        this.usersDataSource.data.push(fleshed_user);
                    });
                    observer.complete();
                });
            });
        });
    }

    associateUser(barcode) {
        if (barcode) {
            let args = {
                currentCourse: this.currentCourse,
                barcode: barcode,
                role: this.userRoleInput,
                is_public: this.isPublicRole
            }

            this.userBarcode = null;

            this.net.request(
                'open-ils.actor',
                'open-ils.actor.user.retrieve_id_by_barcode_or_username',
                this.auth.token(), barcode
            ).subscribe(patron => {
                let associatedUser = this.course.associateUsers(patron, args).then(res => {
                    this.course.fleshUser(res).then(fleshed_user => {
                        this.usersDataSource.data.push(fleshed_user);
                        this.userAddSuccessString.current().then(str => this.toast.success(str));
                    });
                }, err => {
                    this.userAddFailedString.current().then(str => this.toast.danger(str));
                });
            });
        }
    }

    editSelectedUsers(userFields: IdlObject[]) {
        // Edit each IDL thing one at a time
        const editOneThing = (user: IdlObject) => {
            if (!user) { return; }

            this.showEditDialog(user).then(
                () => editOneThing(userFields.shift()));
        };

        editOneThing(userFields.shift());
    }

    showEditDialog(user: IdlObject): Promise<any> {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = user._id;
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: 'lg'}).subscribe(
                result => {
                    this.userEditSuccessString.current()
                        .then(str => this.toast.success(str));
                    this.pcrud.retrieve('acmcu', result).subscribe(u => {
                        if (u.course() != this.courseId) {
                            this.usersDataSource.data.splice(this.usersDataSource.data.indexOf(user, 0), 1);
                        } else {
                            user._is_public = u.is_public();
                            user._role = u.usr_role();
                        }
                    });
                    resolve(result);
                },
                error => {
                    this.userEditFailedString.current()
                        .then(str => this.toast.danger(str));
                    reject(error);
                }
            );
        });
    }

    deleteSelectedUsers(users) {
        let user_ids = [];
        users.forEach(user => {
            this.usersDataSource.data.splice(this.usersDataSource.data.indexOf(user, 0), 1);
            user_ids.push(user.id())
        });
        this.pcrud.search('acmcu', {course: this.courseId, usr: user_ids}).subscribe(user => {
            user.isdeleted(true);
            this.pcrud.autoApply(user).subscribe(
                val => {
                    console.debug('deleted: ' + val);
                    this.userDeleteSuccessString.current().then(str => this.toast.success(str));
                },
                err => {
                    this.userDeleteFailedString.current()
                        .then(str => this.toast.danger(str));
                }
            );
        });
    }

}