import {Pager} from '@eg/share/util/pager';
import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {Router} from '@angular/router';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import { FmRecordEditorModule } from '@eg/share/fm-editor/fm-editor.module';
import { GridModule } from '@eg/share/grid/grid.module';
import { StaffCommonModule } from '@eg/staff/common.module';

@Component({
    templateUrl: './survey.component.html',
    standalone: true,
    imports: [
        FmRecordEditorModule,
        GridModule,
        StaffCommonModule
    ]
})

export class SurveyComponent implements OnInit {

    defaultNewRecord: IdlObject;
    gridDataSource: GridDataSource;

    @ViewChild('editDialog', { static: true }) editDialog: FmRecordEditorComponent;
    @ViewChild('grid', { static: true }) grid: GridComponent;

    @Input() sortField: string;
    @Input() idlClass = 'asv';
    @Input() dialogSize: 'sm' | 'lg' = 'lg';

    DAYS_IN_WEEK = 7;

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
        const now = new Date();
        const nextWeek = new Date();
        nextWeek.setDate(nextWeek.getDate() + this.DAYS_IN_WEEK);
        this.defaultNewRecord.start_date(now.toISOString());
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
                    this.toast.success($localize`Survey ended`);
                },
                async (err) => {
                    this.toast.warning($localize`Ending Survey failed or was not allowed`);
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
                this.toast.success($localize`Delete of Survey succeeded`);
                this.grid.reload();
                return res;
            }, error: (err: unknown) => {
                this.toast.success($localize`Delete of Survey failed or was not allowed`);
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
                this.toast.success($localize`New Survey Added`);
                this.grid.reload();
            }, error: (rejection: any) => {
                if (!rejection.dismissed) {
                    this.toast.danger($localize`Failed to Create New Survey`);
                }
            } }
        );
    };
}
