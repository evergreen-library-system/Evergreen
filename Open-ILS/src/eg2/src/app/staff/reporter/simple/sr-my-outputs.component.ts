import { Component, OnInit, ViewChild, inject } from '@angular/core';
import {AuthService} from '@eg/core/auth.service';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {ReporterService} from '../share/reporter.service';
import { StaffCommonModule } from '@eg/staff/common.module';

@Component({
    selector: 'eg-sr-outputs',
    templateUrl: 'sr-my-outputs.component.html',
    imports: [StaffCommonModule]
})

export class SROutputsComponent implements OnInit {
    private auth = inject(AuthService);
    private pcrud = inject(PcrudService);
    private idl = inject(IdlService);
    private toast = inject(ToastService);
    private srSvc = inject(ReporterService);


    gridSource: GridDataSource;
    @ViewChild('srOutputsGrid', { static: true }) outputsGrid: GridComponent;
    @ViewChild('confirmDelete', { static: false }) confirmDeleteDialog: ConfirmDialogComponent;
    @ViewChild('deleted', { static: true} ) deletedString: StringComponent;
    @ViewChild('delete', { static: true} ) confirmDeleteString: StringComponent;

    cellTextGenerator: GridCellTextGenerator;

    constructor() {
        // These values are all replaced via custom templates and cause warnings if not specified here.
        this.cellTextGenerator = {
            _output: row => ''
        };

    }

    ngOnInit() {
        this.gridSource = this.srSvc.getSOutputDatasource();

    }

    // Expects an rt object with fleshed report to grab the template id.
    outputPath(row: any, file: string) {
        return `/reporter/${row.template_id}/${row.report_id}/${row.id}/${file}?ses=${this.auth.token()}`;
    }

    zeroSelectedRows(rows: any) {
        return rows.length === 0;
    }

    notOneSelectedRow(rows: any) {
        return rows.length !== 1;
    }

    deleteOutputs(rows: any[]) {
        if ( rows.length <= 0 ) { return; }
        this.confirmDeleteString.current({ num: rows.length })
            .then(str => {
                this.confirmDeleteDialog.dialogBody = str;
                this.confirmDeleteDialog.open()
                    .subscribe(confirmed => {
                        if ( confirmed ) { this.doDeleteOutputs(rows.map(x => x._rs)); }
                    });
            });
    }

    doDeleteOutputs(outs: IdlObject[]) {
        const deletedCount = outs.length;
        this.pcrud.remove(outs).toPromise()
            .then(res => {
                this.outputsGrid.reload();
                this.deletedString.current({num: outs.length})
                    .then(str => {
                        this.toast.success(str);
                    });
            });

    }

    refreshGrid($event) {
        this.outputsGrid.reload();
    }

}

