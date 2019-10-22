import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {Observable} from 'rxjs';
import {map} from 'rxjs/operators';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {AcqSearchService, AcqSearchTerm, AcqSearch} from './acq-search.service';
import {AcqSearchFormComponent} from './acq-search-form.component';

@Component({
  selector: 'eg-lineitem-results',
  templateUrl: 'lineitem-results.component.html',
  providers: [AcqSearchService]
})
export class LineitemResultsComponent implements OnInit {

    @Input() initialSearchTerms: AcqSearchTerm[] = [];

    gridSource: GridDataSource;
    @ViewChild('acqSearchForm', { static: true}) acqSearchForm: AcqSearchFormComponent;
    @ViewChild('acqSearchLineitemsGrid', { static: true }) lineitemResultsGrid: GridComponent;

    cellTextGenerator: GridCellTextGenerator;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService,
        private acqSearch: AcqSearchService) {
    }

    ngOnInit() {
        this.gridSource = this.acqSearch.getAcqSearchDataSource('lineitem');
        this.cellTextGenerator = {
            id: row => row.id(),
            title: row => {
                const filtered = row.attributes().filter(lia => lia.attr_name() === 'title');
                if (filtered.length > 0) {
                    return filtered[0].attr_value();
                } else {
                    return '';
                }
            },
            author: row => {
                const filtered = row.attributes().filter(lia => lia.attr_name() === 'author');
                if (filtered.length > 0) {
                    return filtered[0].attr_value();
                } else {
                    return '';
                }
            },
            provider: row => row.provider() ? row.provider().code() : '',
            _links: row => '',
            purchase_order: row => row.purchase_order() ? row.purchase_order().name() : '',
            picklist: row => row.picklist() ? row.picklist().name() : '',
        };
    }

    doSearch(search: AcqSearch) {
        setTimeout(() => {
            this.acqSearch.setSearch(search);
            this.lineitemResultsGrid.reload();
        });
    }

    showRow(row: any) {
        window.open('/eg/staff/acq/legacy/lineitem/worksheet/' + row.id(), '_blank');
    }
}
