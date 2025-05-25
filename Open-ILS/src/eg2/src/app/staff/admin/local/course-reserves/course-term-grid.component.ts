import {Component, Input, ViewChild, OnInit, AfterViewInit} from '@angular/core';
import {Router} from '@angular/router';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {CourseService} from '@eg/staff/share/course.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {GridDataSource, GridColumn} from '@eg/share/grid/grid';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {LocaleService} from '@eg/core/locale.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {OrgFamily} from '@eg/share/org-family-select/org-family-select.component';

@Component({
    selector: 'eg-course-term-grid',
    templateUrl: './course-term-grid.component.html'
})

export class TermListComponent implements OnInit, AfterViewInit {

    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('deleteLinkedTermWarning', { static: true }) deleteLinkedTermWarning: ConfirmDialogComponent;
    @ViewChild('grid') grid: GridComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('createString') createString: StringComponent;
    @ViewChild('createErrString') createErrString: StringComponent;
    @ViewChild('updateFailedString') updateFailedString: StringComponent;
    @ViewChild('deleteFailedString', { static: true }) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', { static: true }) deleteSuccessString: StringComponent;
    @ViewChild('deleteLinkedTermWarningString', { static: true }) deleteLinkedTermWarningString: StringComponent;

    @Input() sortField: string;
    @Input() idlClass = 'acmt';
    @Input() dialog_size: 'sm' | 'lg' = 'lg';
    @Input() tableName = 'Term';
    grid_source: GridDataSource = new GridDataSource();
    currentMaterials: any[] = [];
    search_value = '';
    defaultOuId: number;
    searchOrgs: OrgFamily;
    defaultTerm: IdlObject;
    termToDelete: String;


    constructor(
        private courseSvc: CourseService,
        private locale: LocaleService,
        private auth: AuthService,
        private idl: IdlService,
        private org: OrgService,
        private pcrud: PcrudService,
        private router: Router,
        private toast: ToastService
    ) {}

    ngOnInit() {
        this.getSource();
        this.defaultTerm = this.idl.create('acmt');
        this.defaultOuId = this.auth.user().ws_ou() || this.org.root().id();
        this.defaultTerm.owning_lib(this.defaultOuId);
        this.searchOrgs = {primaryOrgId: this.defaultOuId};
    }

    ngAfterViewInit() {
        this.grid.onRowActivate.subscribe((term: IdlObject) => {
            const idToEdit = term.id();
            this.editSelected([term]);
        });

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
            const search: any = new Array();
            const orgFilter: any = {};
            orgFilter['owning_lib'] =
                this.searchOrgs.orgIds || [this.defaultOuId];
            search.push(orgFilter);
            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };
            return this.pcrud.search(this.idlClass, search, searchOps, {fleshSelectors: true});
        };
    }

    createNew() {
        this.editDialog.mode = 'create';
        const course_module_term = this.idl.create('acmt');
        course_module_term.owning_lib(this.auth.user().ws_ou());
        this.editDialog.recordId = null;
        this.editDialog.record = course_module_term;
        this.editDialog.open({size: this.dialog_size}).subscribe(
            { next: ok => {
                this.createString.current()
                    .then(str => this.toast.success(str));
                this.grid.reload();
            }, error: (rejection: any) => {
                if (!rejection.dismissed) {
                    this.createErrString.current()
                        .then(str => this.toast.danger(str));
                }
            } }
        );
    }

    editSelected(fields: IdlObject[]) {
        this.editDialog.mode = 'update';
        // Edit each IDL thing one at a time
        const course_ids = [];
        fields.forEach(field => {
            this.editDialog.record = field;
            this.editDialog.open({size: this.dialog_size}).subscribe(
                { next: ok => {
                    this.createString.current()
                        .then(str => this.toast.success(str));
                    this.grid.reload();
                }, error: (rejection: any) => {
                    if (!rejection.dismissed) {
                        this.createErrString.current()
                            .then(str => this.toast.danger(str));
                    }
                } }
            );
        });
    }

    deleteSelected(fields: IdlObject[]) {
        console.log(this.deleteLinkedTermWarningString);
        fields.forEach(field => {
            let termHasLinkedCourses = false;
            this.courseSvc.getTermMaps(field.id()).subscribe({ next: map => {
                if (map) {
                    termHasLinkedCourses = true;
                }
            }, error: (err: unknown) => {
                console.error(err);
            }, complete: () => {
                if (termHasLinkedCourses) {
                    this.termToDelete = field.name();
                    this.deleteLinkedTermWarning.open().toPromise().then(yes => {
                        if (!yes) { return; }
                        this.doDelete(field);
                    });
                } else {
                    this.doDelete(field);
                }
            } });
        });

    }

    doDelete(idlThing: IdlObject) {
        idlThing.isdeleted(true);
        this.pcrud.autoApply(idlThing).subscribe(
            { next: val => {
                console.debug('deleted: ' + val);
                this.deleteSuccessString.current()
                    .then(str => this.toast.success(str));
            }, error: (err: unknown) => {
                this.deleteFailedString.current()
                    .then(str => this.toast.danger(str));
            }, complete: ()  => this.grid.reload() }
        );
    }
}
