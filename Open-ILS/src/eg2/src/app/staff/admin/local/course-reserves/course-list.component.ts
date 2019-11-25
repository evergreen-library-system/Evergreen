import {Component, Input, ViewChild, OnInit} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {CourseService} from '@eg/staff/share/course.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {GridDataSource, GridColumn} from '@eg/share/grid/grid';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';

import {CourseAssociateMaterialComponent
    } from './course-associate-material.component';

@Component({
    templateUrl: './course-list.component.html'
})

export class CourseListComponent implements OnInit { 
 
    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('grid', { static: true }) grid: GridComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('createString', { static: false }) createString: StringComponent;
    @ViewChild('createErrString', { static: false }) createErrString: StringComponent;
    @ViewChild('updateFailedString', { static: false }) updateFailedString: StringComponent;
    @ViewChild('deleteFailedString', { static: true }) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', { static: true }) deleteSuccessString: StringComponent;
    @ViewChild('archiveFailedString', { static: true }) archiveFailedString: StringComponent;
    @ViewChild('archiveSuccessString', { static: true }) archiveSuccessString: StringComponent;
    @ViewChild('courseMaterialDialog', {static: true})
        private courseMaterialDialog: CourseAssociateMaterialComponent;
    @Input() sort_field: string;
    @Input() idl_class = "acmc";
    @Input() dialog_size: 'sm' | 'lg' = 'lg';
    @Input() table_name = "Course";
    grid_source: GridDataSource = new GridDataSource();
    currentMaterials: any[] = [];
    search_value = '';

    constructor(
        private auth: AuthService,
        private courseSvc: CourseService,
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService,
        private toast: ToastService,
    ){}

    ngOnInit() {
        this.getSource();
    }

    /**
     * Gets the data, specified by the class, that is available.
     */
    getSource() {
        this.grid_source.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};
            if (sort.length) {
                // Sort specified from grid
                orderBy[this.idl_class] = sort[0].name + ' ' + sort[0].dir;
            } else if (this.sort_field) {
                // Default sort field
                orderBy[this.idl_class] = this.sort_field;
            }
            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };
            return this.pcrud.retrieveAll(this.idl_class, searchOps, {fleshSelectors: true});
        };
    }

    showEditDialog(standingPenalty: IdlObject): Promise<any> {
        this.editDialog.mode = 'update';
        this.editDialog.recordId = standingPenalty['id']();
        return new Promise((resolve, reject) => {
            this.editDialog.open({size: this.dialog_size}).subscribe(
                result => {
                    this.successString.current()
                        .then(str => this.toast.success(str));
                    this.grid.reload();
                    resolve(result);
                },
                error => {
                    this.updateFailedString.current()
                        .then(str => this.toast.danger(str));
                    reject(error);
                }
            );
        });
    }

    createNew() {
        this.editDialog.mode = 'create';
        this.editDialog.recordId = null;
        this.editDialog.record = null;
        this.editDialog.open({size: this.dialog_size}).subscribe(
            ok => {
                this.createString.current()
                    .then(str => this.toast.success(str));
                this.grid.reload();
            },
            rejection => {
                if (!rejection.dismissed) {
                    this.createErrString.current()
                        .then(str => this.toast.danger(str));
                }
            }
        );
    }

    editSelected(fields: IdlObject[]) {
        // Edit each IDL thing one at a time
        const editOneThing = (field_object: IdlObject) => {
            if (!field_object) { return; }
            this.showEditDialog(field_object).then(
                () => editOneThing(fields.shift()));
        };
        editOneThing(fields.shift());
    }

    archiveSelected(course: IdlObject[]) {
        this.courseSvc.disassociateMaterials(course).then(res => {
            course.forEach(course => {
                console.log(course);
                course.is_archived(true);
            });
            this.pcrud.update(course).subscribe(
                val => {
                    console.debug('archived: ' + val);
                    this.archiveSuccessString.current()
                        .then(str => this.toast.success(str));
                }, err => {
                    this.archiveFailedString.current()
                        .then(str => this.toast.danger(str));
                }, () => {
                    this.grid.reload();
                }
            );
        });
    }

    deleteSelected(idl_object: IdlObject[]) {
        this.courseSvc.disassociateMaterials(idl_object).then(res => {
            idl_object.forEach(idl_object => {
                idl_object.isdeleted(true)
            });
            this.pcrud.autoApply(idl_object).subscribe(
                val => {
                    console.debug('deleted: ' + val);
                    this.deleteSuccessString.current()
                        .then(str => this.toast.success(str));
                },
                err => {
                    this.deleteFailedString.current()
                        .then(str => this.toast.danger(str));
                },
                () => this.grid.reload()
            );
        });
    };

    fetchCourseMaterials(course, currentMaterials): Promise<any> {
        return new Promise((resolve, reject) => {
            this.pcrud.search('acmcm', {course: course}).subscribe(res => {
                if (res) this.fleshItemDetails(res.item(), res.relationship());
            }, err => {
                reject(err);
            }, () => resolve(this.courseMaterialDialog.gridDataSource.data));
        });
    }

    fleshItemDetails(itemId, relationship): Promise<any> {
        return new Promise((resolve, reject) => {
            this.net.request(
                'open-ils.circ',
                'open-ils.circ.copy_details.retrieve',
                this.auth.token(), itemId
            ).subscribe(res => {
                if (res) {
                    let item = res.copy;
                    item.call_number(res.volume);
                    item._title = res.mvr.title();
                    item.circ_lib(this.org.get(item.circ_lib()));
                    item._relationship = relationship;
                    this.courseMaterialDialog.gridDataSource.data.push(item);
                }
            }, err => {
                reject(err);
            }, () => resolve(this.courseMaterialDialog.gridDataSource.data));
        });
    }

    openMaterialsDialog(course) {
        let currentMaterials = []
        this.courseMaterialDialog.gridDataSource.data = [];
        this.fetchCourseMaterials(course[0].id(), currentMaterials).then(res => {
            this.courseMaterialDialog.currentCourse = course[0];
            this.courseMaterialDialog.materials = currentMaterials;
            this.courseMaterialDialog.open({size: 'lg'}).subscribe(res => {
                console.log(res);
            });
        });
    }
}

