import {Component, Input, ViewChild, OnInit, TemplateRef} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {from, merge, Observable} from 'rxjs';
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
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {CourseService} from '@eg/staff/share/course.service';

@Component({
    selector: 'eg-course-associate-material-dialog',
    templateUrl: './course-associate-material.component.html'
})

export class CourseAssociateMaterialComponent extends DialogComponent implements OnInit {
    @Input() currentCourse: IdlObject;
    @Input() courseId: any;
    @Input() displayMode: String;
    materials: any[] = [];
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('materialsGrid', {static: false}) materialsGrid: GridComponent;
    @ViewChild('materialDeleteFailedString', { static: true })
        materialDeleteFailedString: StringComponent;
    @ViewChild('materialDeleteSuccessString', { static: true })
        materialDeleteSuccessString: StringComponent;
    @ViewChild('materialAddSuccessString', { static: true })
        materialAddSuccessString: StringComponent;
    @ViewChild('materialAddFailedString', { static: true })
        materialAddFailedString: StringComponent;
    @ViewChild('materialEditSuccessString', { static: true })
        materialEditSuccessString: StringComponent;
    @ViewChild('materialEditFailedString', { static: true })
        materialEditFailedString: StringComponent;
    @ViewChild('materialAddDifferentLibraryString', { static: true })
        materialAddDifferentLibraryString: StringComponent;
    materialsDataSource: GridDataSource;
    @Input() barcodeInput: String;
    @Input() relationshipInput: String;
    @Input() tempCallNumber: String;
    @Input() tempStatus: Number;
    @Input() tempLocation: Number;
    @Input() tempCircMod: String;
    @Input() isModifyingStatus: Boolean;
    @Input() isModifyingCircMod: Boolean;
    @Input() isModifyingCallNumber: Boolean;
    @Input() isModifyingLocation: Boolean;
    bibId: number;

    associateBriefRecord: (newRecord: string) => void;
    associateElectronicBibRecord: () => void;

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
        this.materialsDataSource = new GridDataSource();

        this.materialsDataSource.getRows = (pager: Pager, sort: any[]) => {
            return this.net.request(
                'open-ils.courses',
                'open-ils.courses.course_materials.retrieve.fleshed',
                {course: this.courseId}
            );
        };
    }

    ngOnInit() {
        this.associateBriefRecord = (newRecord: string) => {
            return this.net.request(
                'open-ils.courses',
                'open-ils.courses.attach.biblio_record',
                this.auth.token(),
                newRecord,
                this.courseId,
                this.relationshipInput
            ).subscribe(() => {
                this.materialsGrid.reload();
                this.materialAddSuccessString.current()
                    .then(str => this.toast.success(str));
            });
        };

        this.associateElectronicBibRecord = () => {
            return this.net.request(
                'open-ils.courses',
                'open-ils.courses.attach.electronic_resource',
                this.auth.token(),
                this.bibId,
                this.courseId,
                this.relationshipInput
            ).subscribe(() => {
                this.materialsGrid.reload();
                this.materialAddSuccessString.current()
                    .then(str => this.toast.success(str));
            });
         };

    }

    isDialog(): boolean {
        return this.displayMode === 'dialog';
    }

    editSelectedMaterials(itemFields: IdlObject[]) {
        // Edit each IDL thing one at a time
        const editOneThing = (item: IdlObject) => {
            if (!item) { return; }

            this.showEditDialog(item).then(
                () => editOneThing(itemFields.shift()));
        };

        editOneThing(itemFields.shift());
    }

    showEditDialog(courseMaterial: IdlObject): Promise<any> {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = courseMaterial.id();
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: 'lg'}).subscribe(
                result => {
                    this.materialEditSuccessString.current()
                        .then(str => this.toast.success(str));
                    this.pcrud.retrieve('acmcm', result).subscribe(material => {
                        if (material.course() !== this.courseId) {
                            this.materialsGrid.reload();
                        } else {
                            courseMaterial.relationship = material.relationship();
                        }
                    });
                    resolve(result);
                },
                error => {
                    this.materialEditFailedString.current()
                        .then(str => this.toast.danger(str));
                    reject(error);
                }
            );
        });
    }

    associateItem(barcode, relationship) {
        if (barcode) {
            const args = {
                barcode: barcode.trim(),
                relationship: relationship,
                isModifyingCallNumber: this.isModifyingCallNumber,
                isModifyingCircMod: this.isModifyingCircMod,
                isModifyingLocation: this.isModifyingLocation,
                isModifyingStatus: this.isModifyingStatus,
                tempCircMod: this.tempCircMod,
                tempLocation: this.tempLocation,
                tempStatus: this.tempStatus,
                currentCourse: this.currentCourse
            };
            this.barcodeInput = null;

            this.pcrud.search('acp', {barcode: args.barcode}, {
                flesh: 3, flesh_fields: {acp: ['call_number']}
            }).subscribe(item => {
                const associatedMaterial = this.course.associateMaterials(item, args);
                associatedMaterial.material.then(res => {
                    item = associatedMaterial.item;
                    let new_cn = item.call_number().label();
                    if (this.tempCallNumber) { new_cn = this.tempCallNumber; }
                    this.course.updateItem(item, this.currentCourse.owning_lib(),
                        new_cn, args.isModifyingCallNumber
                    ).then(resp => {
                        this.materialsGrid.reload();
                        if (item.circ_lib() !== this.currentCourse.owning_lib()) {
                            this.materialAddDifferentLibraryString.current()
                            .then(str => this.toast.warning(str));
                        } else {
                            this.materialAddSuccessString.current()
                            .then(str => this.toast.success(str));
                        }
                    });
                }, err => {
                    this.materialAddFailedString.current()
                    .then(str => this.toast.danger(str));
                });
            });
        }
    }

    deleteSelectedMaterials(items) {
        const deleteRequest$ = [];
        items.forEach(item => {
            deleteRequest$.push(this.net.request(
                'open-ils.courses', 'open-ils.courses.detach_material',
                this.auth.token(), item.id()));
        });
        merge(...deleteRequest$).subscribe(
            val => {
                this.materialDeleteSuccessString.current().then(str => this.toast.success(str));
            },
            err => {
                this.materialDeleteFailedString.current()
                    .then(str => this.toast.danger(str));
            }
        ).add(() => {
            this.materialsGrid.reload();
        });
    }
}
