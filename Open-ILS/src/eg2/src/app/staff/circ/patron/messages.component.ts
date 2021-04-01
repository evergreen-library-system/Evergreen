import {Component, ViewChild, OnInit, Input, AfterViewInit} from '@angular/core';
import {empty} from 'rxjs';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';
import {GridDataSource, GridColumn, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {DateUtil} from '@eg/share/util/date';

@Component({
  selector: 'eg-patron-messages',
  templateUrl: 'messages.component.html'
})
export class PatronMessagesComponent implements OnInit {

    @Input() patronId: number;

    mainDataSource: GridDataSource = new GridDataSource();
    archiveDataSource: GridDataSource = new GridDataSource();

    startDateYmd: string;
    endDateYmd: string;

    @ViewChild('mainGrid') private mainGrid: GridComponent;
    @ViewChild('archiveGrid') private archiveGrid: GridComponent;

    constructor(
        private org: OrgService,
        private net: NetService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private serverStore: ServerStoreService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {

		const orgIds = this.org.fullPath(this.auth.user().ws_ou(), true);

        const start = new Date();
        start.setFullYear(start.getFullYear() - 1);
        this.startDateYmd = DateUtil.localYmdFromDate(start);
        this.endDateYmd = DateUtil.localYmdFromDate(); // now

        const flesh = {
            flesh: 1,
            flesh_fields: {
                ausp: ['standing_penalty', 'staff']
            },
            order_by: {}
        };

        this.mainDataSource.getRows = (pager: Pager, sort: any[]) => {

            const orderBy: any = {ausp: 'set_date'};
            if (sort.length) {
                orderBy.ausp = sort[0].name + ' ' + sort[0].dir;
            }

            const query = {
                usr: this.patronId,
                org_unit: orgIds,
                '-or' : [
                    {stop_date: null},
                    {stop_date: {'>' : 'now'}}
                ]
            };

            flesh.order_by = orderBy;
            return this.pcrud.search('ausp', query, flesh);
        }

        this.archiveDataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {ausp: 'set_date'};
            if (sort.length) {
                orderBy.ausp = sort[0].name + ' ' + sort[0].dir;
            }

            const query = {
                usr: this.patronId,
                org_unit: orgIds,
                stop_date: {'<' : 'now'},
                set_date: {between: this.dateRange()}
            };

            flesh.order_by = orderBy;

            return this.pcrud.search('ausp', query, flesh);
        }
    }

    dateRange(): string[] {

        let endDate = this.endDateYmd;
        const today = DateUtil.localYmdFromDate();

        if (endDate == today) { endDate = 'now'; }

        return [this.startDateYmd, endDate];
    }

    applyPenalty() {
    }
}



