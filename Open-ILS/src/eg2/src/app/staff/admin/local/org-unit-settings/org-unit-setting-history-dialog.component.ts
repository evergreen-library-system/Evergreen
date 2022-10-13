import {Component, OnInit, ViewChild} from '@angular/core';
import {Observable} from 'rxjs';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {OrgService} from '@eg/core/org.service';
import {Pager} from '@eg/share/util/pager';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {GridDataSource} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';

@Component({
    selector: 'eg-admin-ou-setting-history-dialog',
    templateUrl: './org-unit-setting-history-dialog.component.html'
})

export class OuSettingHistoryDialogComponent extends DialogComponent implements OnInit {

    entry: any = {};
    history: any[] = [];
    gridDataSource: GridDataSource;
    @ViewChild('historyGrid', { static: true }) historyGrid: GridComponent;


    constructor(
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
            if (log.original_value) {
                const intTypes = ['integer', 'currency', 'link'];
                if (intTypes.includes(this.entry.dataType)) {
                    log.original_value = Number(log.original_value);
                } else {
                    log.original_value = log.original_value.replace(/^"(.*)"$/, '$1');
                }

                if (this.entry.dataType === 'bool') {
                    if (log.original_value.match(/^t/)) {
                        log.original_value = true;
                    } else {
                        log.original_value = false;
                    }
                }
            }

            this.close({
                setting: {[this.entry.name]: log.original_value},
                context: this.org.get(log.org),
                revert: true
            });
            this.gridDataSource.data = null;
        }
    }
}
