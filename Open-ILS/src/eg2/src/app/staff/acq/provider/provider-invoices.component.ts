import {Component, OnInit, AfterViewInit, OnDestroy, Input, ViewChild} from '@angular/core';
import {Subscription} from 'rxjs';
import {Router, ActivatedRoute} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {PrintService} from '@eg/share/print/print.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {AcqSearchService, AcqSearchTerm} from '../search/acq-search.service';
import {AttrDefsService} from '../search/attr-defs.service';
import {ProviderRecordService} from './provider-record.service';

@Component({
    selector: 'eg-provider-invoices',
    templateUrl: 'provider-invoices.component.html',
    providers: [AcqSearchService, AttrDefsService]
})
export class ProviderInvoicesComponent implements OnInit, AfterViewInit, OnDestroy {

    @Input() initialSearchTerms: AcqSearchTerm[] = [];

    gridSource: GridDataSource;
    @ViewChild('acqProviderInvoicesGrid', { static: true }) providerInvoicesGrid: GridComponent;
    @ViewChild('printfail', { static: true }) private printfail: AlertDialogComponent;

    noSelectedRows: (rows: IdlObject[]) => boolean;

    cellTextGenerator: GridCellTextGenerator;

    subscription: Subscription;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private printer: PrintService,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private providerRecord: ProviderRecordService,
        private acqSearch: AcqSearchService) {
    }

    ngOnInit() {
        this.gridSource = this.acqSearch.getAcqSearchDataSource('invoice');
        this.noSelectedRows = (rows: IdlObject[]) => (rows.length === 0);
        this.cellTextGenerator = {
            inv_ident: row => row.inv_ident(),
            provider: row => row.provider().code(),
            shipper: row => row.shipper().code(),
        };
        this.subscription = this.providerRecord.providerUpdated$.subscribe(
            id => {
                this.resetSearch();
            }
        );
    }

    ngAfterViewInit() {
        this.resetSearch();
    }

    ngOnDestroy() {
        this.subscription.unsubscribe();
    }

    resetSearch() {
        const provider = this.providerRecord.current();
        if (provider) {
            setTimeout(() => {
                this.acqSearch.setSearch({
                    terms: [{
                        field:  'acqinv:provider',
                        op:     '',
                        value1: provider.id(),
                        value2: '',
                    }],
                    conjunction: 'all',
                });
                this.providerInvoicesGrid.reload();
            });
        }
    }

    // TODO - copied from InvoiceResultsComponent, could be
    // consolidated
    printSelectedInvoices(rows: IdlObject[]) {
        const that = this;
        let html = '<style type="text/css">.acq-invoice-' +
        'voucher {page-break-after:always;}' +
        '</style>\n';
        this.net.request(
            'open-ils.acq',
            'open-ils.acq.invoice.print.html',
            this.auth.token(), rows.map( invoice => invoice.id() )
        ).subscribe(
            { next: (res) => {
                if (this.evt.parse(res)) {
                    console.error(res);
                    this.printfail.open();
                } else {
                    html +=  res.template_output().data();
                }
            }, error: (err: unknown) => {
                console.error(err);
                this.printfail.open();
            }, complete: () => this.printer.print({
                text: html,
                printContext: 'default'
            }) }
        );
    }

}
