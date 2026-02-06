import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {RouterModule} from '@angular/router';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {AcqSearchService, AcqSearchTerm, AcqSearch} from './acq-search.service';
import {AcqSearchFormComponent} from './acq-search-form.component';
import { GridModule } from '@eg/share/grid/grid.module';

@Component({
    selector: 'eg-purchase-order-results',
    templateUrl: 'purchase-order-results.component.html',
    imports: [
        AcqSearchFormComponent,
        GridModule,
        RouterModule,
    ]
})
export class PurchaseOrderResultsComponent implements OnInit {

    @Input() initialSearchTerms: AcqSearchTerm[] = [];

    gridSource: GridDataSource;
    @ViewChild('acqSearchForm', { static: true}) acqSearchForm: AcqSearchFormComponent;
    @ViewChild('acqSearchPurchaseOrdersGrid', { static: true }) purchaseOrderResultsGrid: GridComponent;

    cellTextGenerator: GridCellTextGenerator;

    fallbackSearchTerms: AcqSearchTerm[] = [{
        field:  'acqpo:ordering_agency',
        op:     '',
        value1: this.auth.user() ? this.auth.user().ws_ou() : '',
        value2: ''
    }, {
        field:  'acqpo:state',
        op:     '',
        value1: 'on-order',
        value2: ''
    }];

    constructor(
        private auth: AuthService,
        private acqSearch: AcqSearchService) {
    }

    ngOnInit() {
        this.gridSource = this.acqSearch.getAcqSearchDataSource('purchase_order');

        this.cellTextGenerator = {
            provider: row => row.provider().code(),
            name: row => row.name(),
        };
    }

    showRow(row: any) {
        window.open('/eg2/staff/acq/po/' + row.id(), '_blank');
    }

    doSearch(search: AcqSearch) {
        setTimeout(() => {
            this.acqSearch.setSearch(search);
            this.purchaseOrderResultsGrid.reload();
        });
    }
}
