import {Pager} from '@eg/share/util/pager';
import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {Router} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
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

    @Input() dialogSize: 'sm' | 'lg' = 'lg';

    constructor(
        private auth: AuthService,
        private net: NetService,
        private pcrud: PcrudService,
        private toast: ToastService,
        private router: Router
    ) {
        this.gridDataSource = new GridDataSource();
    }

    ngOnInit() {
        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            return this.pcrud.retrieveAll('asv', {});
        };

        this.grid.onRowActivate.subscribe(
            (idlThing: IdlObject) => {
                const idToEdit = idlThing.id();
                this.navigateToEditPage(idToEdit);
            }
        );
    }

    showEditDialog(idlThing: IdlObject): Promise<any> {
        return;
    }

    editSelected = (surveys: IdlObject[]) => {
        const idToEdit = surveys[0].id();
        this.navigateToEditPage(idToEdit);
    }

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
    }

    deleteSelected = (surveys: IdlObject[]) => {
        for (let i = 0; i < surveys.length; i++) {
            const idToDelete = surveys[i].id();
            this.net.request(
                'open-ils.circ',
                'open-ils.circ.survey.delete.cascade.override',
                this.auth.token(), idToDelete
            ).subscribe(res => {
                this.deleteSuccessString.current()
                    .then(str => this.toast.success(str));
                this.grid.reload();
                return res;
            }, (err) => {
                this.deleteFailedString.current()
                    .then(str => this.toast.success(str));
            });
        }
    }

    navigateToEditPage(id: any) {
        this.router.navigate(['/staff/admin/local/action/survey/' + id]);
    }

    createNew = () => {
        this.editDialog.mode = 'create';
        this.editDialog.datetimeFields = 'start_date,end_date';
        this.editDialog.open({size: this.dialogSize}).subscribe(
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
}
