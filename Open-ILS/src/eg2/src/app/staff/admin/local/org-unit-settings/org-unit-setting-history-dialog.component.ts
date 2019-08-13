import {Component, Input, ViewChild, OnInit, TemplateRef} from '@angular/core';
import {Observable, Observer, of} from 'rxjs';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {Pager} from '@eg/share/util/pager';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridToolbarCheckboxComponent
    } from '@eg/share/grid/grid-toolbar-checkbox.component';
import {OrgUnitSetting} from '@eg/staff/admin/local/org-unit-settings/org-unit-settings.component';

@Component({
    selector: 'eg-admin-ou-setting-history-dialog',
    templateUrl: './org-unit-setting-history-dialog.component.html'
})

export class OuSettingHistoryDialogComponent extends DialogComponent {

    entry: any = {};
    history: any[] = [];
    gridDataSource: GridDataSource;
    @ViewChild('historyGrid', { static:true }) historyGrid: GridComponent;


    constructor(
        private auth: AuthService,
        private net: NetService,
        private org: OrgService,
        private modal: NgbModal
    ) {
        super(modal);
        this.gridDataSource = new GridDataSource();
    }

    ngOnInit() {
        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            return this.fetchHistory(pager);
        };
    }

    fetchHistory(pager: Pager): Observable<any> {
        return new Observable<any>(observer => {
            this.gridDataSource.data = this.history;
            observer.complete();
        });
    }

    revert(log) {
        if (log) {
            var intTypes = ["integer", "currency", "link"];
            if (intTypes.includes(this.entry.dataType)) {
                log.new_value = parseInt(log.new_value);
            } else {
                log.new_value = log.new_value.replace(/^"(.*)"$/, '$1');
            }
            this.close({
                setting: {[this.entry.name]: log.new_value},
                context: this.org.get(log.org),
                revert: true
            });
            this.gridDataSource.data = null;
        }
    }
}