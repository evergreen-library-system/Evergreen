import {Pager} from '@eg/share/util/pager';
import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {Router} from '@angular/router';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';

@Component({
    templateUrl: './survey.component.html'
})

export class SurveyComponent implements OnInit {

    defaultNewRecord: IdlObject;
    gridDataSource: GridDataSource;

    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('grid', { static: true }) grid: GridComponent;
    @ViewChild('successString', { static: true }) successString: StringComponent;
    @ViewChild('createString', { static: true }) createString: StringComponent;
    @ViewChild('createErrString', { static: true }) createErrString: StringComponent;
    @ViewChild('updateFailedString', { static: true }) updateFailedString: StringComponent;
    @ViewChild('deleteFailedString', { static: true }) deleteFailedString: StringComponent;
    @ViewChild('deleteSuccessString', { static: true }) deleteSuccessString: StringComponent;
    @ViewChild('endSurveyFailedString', { static: true }) endSurveyFailedString: StringComponent;
    @ViewChild('endSurveySuccessString', { static: true }) endSurveySuccessString: StringComponent;

    @Input() sortField: string;
    @Input() idlClass = 'asv';
    @Input() dialogSize: 'sm' | 'lg' = 'lg';

    constructor(
        private auth: AuthService,
        private idl: IdlService,
        private net: NetService,
        private pcrud: PcrudService,
        private toast: ToastService,
        private router: Router
    ) {
        this.gridDataSource = new GridDataSource();
    }

    ngOnInit() {
        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
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
            return this.pcrud.retrieveAll('asv', searchOps, {});
        };

        this.grid.onRowActivate.subscribe(
            (idlThing: IdlObject) => {
                const idToEdit = idlThing.id();
                this.navigateToEditPage(idToEdit);
            }
        );

        this.defaultNewRecord = this.idl.create('asv');
        const nextWeek = new Date();
        // eslint-disable-next-line no-magic-numbers
        nextWeek.setDate(nextWeek.getDate() + 7);
        this.defaultNewRecord.end_date(nextWeek.toISOString());
    }

    showEditDialog(idlThing: IdlObject): Promise<any> {
        return;
    }

    editSelected = (surveys: IdlObject[]) => {
        const idToEdit = surveys[0].id();
        this.navigateToEditPage(idToEdit);
    };

    endSurvey = (surveys: IdlObject[]) => {
        const today = new Date().toISOString();
        for (let i = 0; i < surveys.length; i++) {
            surveys[i].end_date(today);
            this.pcrud.update(surveys[i]).toPromise().then(
                async (ok) => {
                    this.toast.success(await this.endSurveySuccessString.current());
                },
                async (err) => {
                    this.toast.warning(await this.endSurveyFailedString.current());
                }
            );
        }
    };

    deleteSelected = (surveys: IdlObject[]) => {
        for (let i = 0; i < surveys.length; i++) {
            const idToDelete = surveys[i].id();
            this.net.request(
                'open-ils.circ',
                'open-ils.circ.survey.delete.cascade.override',
                this.auth.token(), idToDelete
            ).subscribe({ next: res => {
                this.deleteSuccessString.current()
                    .then(str => this.toast.success(str));
                this.grid.reload();
                return res;
            }, error: (err: unknown) => {
                this.deleteFailedString.current()
                    .then(str => this.toast.success(str));
            } });
        }
    };

    navigateToEditPage(id: any) {
        this.router.navigate(['/staff/admin/local/action/survey/' + id]);
    }

    createNew = () => {
        this.editDialog.mode = 'create';
        this.editDialog.datetimeFields = 'start_date,end_date';
        this.editDialog.open({size: this.dialogSize}).subscribe(
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
    };
}
