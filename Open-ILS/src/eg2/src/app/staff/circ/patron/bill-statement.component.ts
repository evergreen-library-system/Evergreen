import {Component, Input, OnInit, AfterViewInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {from, empty, range} from 'rxjs';
import {concatMap, tap, takeLast} from 'rxjs/operators';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService, PcrudContext} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService, BillGridEntry} from './patron.service';
import {GridDataSource, GridColumn, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {CircService, CircDisplayInfo} from '@eg/staff/share/circ/circ.service';
import {PrintService} from '@eg/share/print/print.service';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {CreditCardDialogComponent
    } from '@eg/staff/share/billing/credit-card-dialog.component';
import {BillingService, CreditCardPaymentParams} from '@eg/staff/share/billing/billing.service';
import {AddBillingDialogComponent} from '@eg/staff/share/billing/billing-dialog.component';
import {AudioService} from '@eg/share/util/audio.service';
import {ToastService} from '@eg/share/toast/toast.service';

@Component({
  templateUrl: 'bill-statement.component.html',
  selector: 'eg-patron-bill-statement'
})
export class BillStatementComponent implements OnInit {

    @Input() patronId: number;
    @Input() xactId: number;
    statement: any;
    statementTab = 'statement';
    gridDataSource: GridDataSource = new GridDataSource();
    cellTextGenerator: GridCellTextGenerator;

    //@ViewChild('grid') private billGrid: GridComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private audio: AudioService,
        private toast: ToastService,
        private org: OrgService,
        private evt: EventService,
        private net: NetService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private printer: PrintService,
        private serverStore: ServerStoreService,
        private circ: CircService,
        private billing: BillingService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {

        this.cellTextGenerator = {
        };

        this.gridDataSource.getRows = (pager: Pager, sort: any[]) => {
            return empty();
        };

        this.net.request(
            'open-ils.circ',
            'open-ils.circ.money.statement.retrieve',
            this.auth.token(), this.xactId
        ).subscribe(s => this.statement = s);
    }
}

