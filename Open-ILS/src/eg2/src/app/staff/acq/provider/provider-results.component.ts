import {Component, OnInit, AfterViewInit, Output, EventEmitter, ViewChild, ElementRef} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {AcqProviderSearchService, AcqProviderSearch} from './acq-provider-search.service';
import {AcqProviderSearchFormComponent} from './acq-provider-search-form.component';

@Component({
    selector: 'eg-provider-results',
    templateUrl: 'provider-results.component.html',
    providers: [AcqProviderSearchService]
})
export class ProviderResultsComponent implements OnInit, AfterViewInit {

    gridSource: GridDataSource;
    @ViewChild('acqSearchProviderGrid', { static: true }) providerResultsGrid: GridComponent;
    @ViewChild('providerSearchForm', { static: true }) providerSearchForm: AcqProviderSearchFormComponent;

    cellTextGenerator: GridCellTextGenerator;
    @Output() previewRow: (row: any, hideSearchForm?: boolean) => void;
    @Output() desireSummarize: EventEmitter<number> = new EventEmitter<number>();
    @Output() summarizeSearchFormOpen: EventEmitter<number> = new EventEmitter<number>();

    constructor(
        private elementRef: ElementRef,
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService,
        private providerSearch: AcqProviderSearchService) {
    }

    ngOnInit() {
        this.gridSource = this.providerSearch.getDataSource();

        this.cellTextGenerator = {
            provider: row => row.provider().code(),
            name: row => row.name(),
        };

        this.previewRow = (row: any, hideSearchForm = true) => {
            if (hideSearchForm) {
                this.desireSummarize.emit(row.id());
            } else {
                this.summarizeSearchFormOpen.emit(row.id());
            }
        };
    }

    ngAfterViewInit() {
        // check if we're visible; if we are, we've
        // likely come in directly from the main Provider Search
        // menu item and should go ahead and submit the
        // form with default values
        // see: https://stackoverflow.com/questions/37843907/angular2-is-there-a-way-to-know-when-a-component-is-hidden
        const elm = this.elementRef.nativeElement;
        if (elm.offsetParent !== null) {
            setTimeout(x => this.providerSearchForm.submitSearch());
        }
    }

    retrieveRow(rows: IdlObject[]) {
        this.desireSummarize.emit(rows[0].id());
    }

    resetSearch() {
        this.providerSearchForm.clearSearch();
        setTimeout(x => this.providerSearchForm.submitSearch());
    }

    doSearch(search: AcqProviderSearch) {
        setTimeout(() => {
            this.providerSearch.setSearch(search);
            this.providerResultsGrid.reload();
        });
    }
}
