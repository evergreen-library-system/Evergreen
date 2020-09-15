import {Component, Input, ViewChild, OnInit} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {Pager} from '@eg/share/util/pager';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {IdlObject} from '@eg/core/idl.service';
import {StringComponent} from '@eg/share/string/string.component';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {CourseService} from '@eg/staff/share/course.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-course-associate-users-dialog',
    templateUrl: './course-associate-users.component.html'
})

export class CourseAssociateUsersComponent extends DialogComponent implements OnInit {
    @Input() currentCourse: IdlObject;
    @Input() courseId: number;
    @Input() displayMode: String;
    users: any[] = [];
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('usersGrid') usersGrid: GridComponent;
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
    userBarcode: String;
    userRoleInput: ComboboxEntry;

    constructor(
        private auth: AuthService,
        private course: CourseService,
        private net: NetService,
        private pcrud: PcrudService,
        private toast: ToastService,
        private modal: NgbModal
    ) {
        super(modal);
        this.usersDataSource = new GridDataSource();
    }

    ngOnInit() {
        this.usersDataSource.getRows = (pager: Pager, sort: any[]) => {
            return this.course.getUsers([this.courseId]);
        };
    }

    isDialog(): boolean {
        return this.displayMode === 'dialog';
    }

    associateUser(barcode) {
        if (barcode) {
            const args = {
                currentCourse: this.currentCourse,
                barcode: barcode.trim(),
            };

            if (this.userRoleInput) {
                args['role'] = this.userRoleInput.id;
            }

            this.userBarcode = null;

            this.net.request(
                'open-ils.actor',
                'open-ils.actor.user.retrieve_id_by_barcode_or_username',
                this.auth.token(), barcode.trim()
            ).subscribe(patron => {
                    this.course.associateUsers(patron, args)
                    .then(() => this.usersGrid.reload());
                }, err => {
                    this.userAddFailedString.current().then(str => this.toast.danger(str));
                }
            );
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
        this.editDialog.recordId = user.id();
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: 'lg'}).subscribe(
                result => {
                    this.userEditSuccessString.current()
                        .then(str => this.toast.success(str));
                    this.usersGrid.reload();
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
        const acmcu_ids = users.map(u => u.id());
        this.pcrud.search('acmcu', {course: this.courseId, id: acmcu_ids}).subscribe(user => {
            user.isdeleted(true);
            this.pcrud.autoApply(user).subscribe(
                val => {
                    console.debug('deleted: ' + val);
                    this.userDeleteSuccessString.current().then(str => this.toast.success(str));
                    this.usersGrid.reload();
                },
                err => {
                    this.userDeleteFailedString.current()
                        .then(str => this.toast.danger(str));
                }
            );
        }).add(() => this.usersGrid.reload());
    }

}
