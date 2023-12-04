import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Observable} from 'rxjs';
import {map} from 'rxjs/operators';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {PrintService} from '@eg/share/print/print.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {AcqSearchService, AcqSearchTerm, AcqSearch} from './acq-search.service';
import {AcqSearchFormComponent} from './acq-search-form.component';

@Component({
    selector: 'eg-invoice-results',
    templateUrl: 'invoice-results.component.html'
})
export class InvoiceResultsComponent implements OnInit {

    @Input() initialSearchTerms: AcqSearchTerm[] = [];

    gridSource: GridDataSource;
    @ViewChild('acqSearchForm', { static: true}) acqSearchForm: AcqSearchFormComponent;
    @ViewChild('acqSearchInvoicesGrid', { static: true }) invoiceResultsGrid: GridComponent;
    @ViewChild('printfail', { static: true }) private printfail: AlertDialogComponent;

    noSelectedRows: (rows: IdlObject[]) => boolean;

    cellTextGenerator: GridCellTextGenerator;

    fallbackSearchTerms: AcqSearchTerm[] = [{
        field:  'acqinv:receiver',
        op:     '',
        value1: this.auth.user() ? this.auth.user().ws_ou() : '',
        value2: ''
    }, {
        field:  'acqinv:close_date',
        op:     '__isnull',
        value1: null,
        value2: ''
    }];

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private printer: PrintService,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
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
    }

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
            (res) => {
                if (this.evt.parse(res)) {
                    console.error(res);
                    this.printfail.open();
                } else {
                    html +=  res.template_output().data();
                }
            },
            (err: unknown) => {
                console.error(err);
                this.printfail.open();
            },
            () => this.printer.print({
                text: html,
                printContext: 'default'
            })
        );
    }

    showRow(row: any) {
        window.open('/eg/staff/acq/legacy/invoice/view/' + row.id(), '_blank');
    }

    doSearch(search: AcqSearch) {
        setTimeout(() => {
            this.acqSearch.setSearch(search);
            this.invoiceResultsGrid.reload();
        });
    }
}
