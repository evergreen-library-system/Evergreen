import {Component, Input, ViewChild, OnInit, AfterViewInit} from '@angular/core';
import {Router} from '@angular/router';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {CourseService} from '@eg/staff/share/course.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {GridDataSource, GridColumn} from '@eg/share/grid/grid';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {LocaleService} from '@eg/core/locale.service';
import {AuthService} from '@eg/core/auth.service';

import {CourseAssociateMaterialComponent
    } from './course-associate-material.component';

import {CourseAssociateUsersComponent
    } from './course-associate-users.component';

@Component({
    templateUrl: './course-list.component.html'
})

export class CourseListComponent implements OnInit, AfterViewInit {

    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('grid') grid: GridComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('createString') createString: StringComponent;
    @ViewChild('createErrString') createErrString: StringComponent;
    @ViewChild('updateFailedString') updateFailedString: StringComponent;
    @ViewChild('deleteFailedString', { static: true }) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', { static: true }) deleteSuccessString: StringComponent;
    @ViewChild('archiveFailedString', { static: true }) archiveFailedString: StringComponent;
    @ViewChild('archiveSuccessString', { static: true }) archiveSuccessString: StringComponent;
    @ViewChild('courseMaterialDialog', {static: true})
        private courseMaterialDialog: CourseAssociateMaterialComponent;
    @ViewChild('courseUserDialog', {static: true})
        private courseUserDialog: CourseAssociateUsersComponent;

    @Input() sortField: string;
    @Input() idlClass = 'acmc';
    @Input() dialog_size: 'sm' | 'lg' = 'lg';
    @Input() tableName = 'Course';
    grid_source: GridDataSource = new GridDataSource();
    currentMaterials: any[] = [];
    search_value = '';
    defaultTerm: IdlObject;


    constructor(
        private courseSvc: CourseService,
        private locale: LocaleService,
        private auth: AuthService,
        private idl: IdlService,
        private pcrud: PcrudService,
        private router: Router,
        private toast: ToastService
    ) {}

    ngOnInit() {
        this.getSource();
        this.defaultTerm = this.idl.create('acmt');
        this.defaultTerm.owning_lib(this.auth.user().ws_ou());
    }

    ngAfterViewInit() {
        this.grid.onRowActivate.subscribe((course: IdlObject) => {
            const idToEdit = course.id();
            this.navigateToCoursePage(idToEdit);
        });

    }

    acmtcmQueryParams (row: any): {gridFilters: string} {
        return {gridFilters: '{"course":' + row.id() + '}'};
    }


    /**
     * Gets the data, specified by the class, that is available.
     */
    getSource() {
        this.grid_source.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};
            if (sort.length) {
                // Sort specified from grid
                orderBy[this.idlClass] = sort[0].name + ' ' + sort[0].dir;
            } else if (this.sortField) {
                // Default sort field
                orderBy[this.idlClass] = this.sortField;
            }
            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };
            return this.pcrud.retrieveAll(this.idlClass, searchOps, {fleshSelectors: true});
        };
    }

    navigateToCoursePage(id_arr: IdlObject[]) {
        if (typeof id_arr === 'number') { id_arr = [id_arr]; }
        const urls = [];
        id_arr.forEach(id => {console.log(this.router.url);
            urls.push([this.locale.currentLocaleCode() + this.router.url + '/' +  id]);
        });
        if (id_arr.length === 1) {
        this.router.navigate([this.router.url + '/' + id_arr[0]]);
        } else {
            urls.forEach(url => {
                window.open(url);
            });
        }
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
        const course_ids = [];
        fields.forEach(field => {
            if (typeof field['id'] === 'function') {
                course_ids.push(field.id());
            } else {
                course_ids.push(field['id']);
            }
        });
        this.navigateToCoursePage(course_ids);
    }

    archiveSelected(course: IdlObject[]) {
        this.courseSvc.disassociateMaterials(course).then(res => {
            course.forEach(courseToArchive => {
                courseToArchive.is_archived(true);
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

    deleteSelected(idlObject: IdlObject[]) {
        this.courseSvc.disassociateMaterials(idlObject).then(res => {
            idlObject.forEach(object => {
                object.isdeleted(true);
            });
            this.pcrud.autoApply(idlObject).subscribe(
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
    }
}

