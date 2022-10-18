import {Component, Input, ViewChild, OnInit} from '@angular/core';
import {Observable, merge, of, EMPTY} from 'rxjs';
import {switchMap} from 'rxjs/operators';
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

@Component({
    selector: 'eg-course-associate-material-dialog',
    templateUrl: './course-associate-material.component.html'
})

export class CourseAssociateMaterialComponent extends DialogComponent implements OnInit {
    @Input() currentCourse: IdlObject;
    @Input() courseId: any;
    @Input() courseIsArchived: string;
    @Input() displayMode: string;
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
    @ViewChild('confirmOtherLibraryDialog') confirmOtherLibraryDialog: DialogComponent;
    materialsDataSource: GridDataSource;
    @Input() barcodeInput: string;
    @Input() relationshipInput: string;
    @Input() tempCallNumber: string;
    @Input() tempStatus: number;
    @Input() tempLocation: number;
    @Input() tempCircMod: string;
    @Input() isModifyingStatus: boolean;
    @Input() isModifyingCircMod: boolean;
    @Input() isModifyingCallNumber: boolean;
    @Input() isModifyingLocation: boolean;
    bibId: number;
    itemCircLib: string;

    associateBriefRecord: (newRecord: string) => void;
    associateElectronicBibRecord: () => void;

    constructor(
        private auth: AuthService,
        private course: CourseService,
        private net: NetService,
        private pcrud: PcrudService,
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
                flesh: 3, flesh_fields: {acp: ['call_number', 'circ_lib']}
            }).pipe(switchMap(item => this.handleItemAtDifferentLibrary$(item)))
            .subscribe((originalItem) => {
                const associatedMaterial = this.course.associateMaterials(originalItem, args);
                associatedMaterial.material.then(res => {
                    const item = associatedMaterial.item;
                    let new_cn = item.call_number().label();
                    if (this.tempCallNumber) { new_cn = this.tempCallNumber; }
                    this.course.updateItem(item, this.currentCourse.owning_lib(),
                        new_cn, args.isModifyingCallNumber
                    ).then(resp => {
                        this.materialsGrid.reload();
                        this.materialAddSuccessString.current()
                        .then(str => this.toast.success(str));
                    });
                }, err => {
                    this.materialAddFailedString.current()
                    .then(str => this.toast.danger(str));
                });
            });
        }
    }

    deleteSelectedMaterials(items) {
        let deleteRequest$ = this.course.detachMaterials(items);
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

    handleItemAtDifferentLibrary$(item: IdlObject): Observable<any> {
        this.itemCircLib = item.circ_lib().shortname();
        if (item.circ_lib().id() !== this.currentCourse.owning_lib().id()) {
            return this.confirmOtherLibraryDialog.open()
            .pipe(switchMap(confirmed => {
                if (!confirmed) { return EMPTY; }
                return of(item);
            }));
        }
        return of(item);
    }
}
