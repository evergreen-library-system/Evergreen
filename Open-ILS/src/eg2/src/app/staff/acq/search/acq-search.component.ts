import {Component, OnInit, ViewChild, ViewChildren, QueryList, OnDestroy} from '@angular/core';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {Router, ActivatedRoute, ParamMap, RouterEvent, NavigationEnd} from '@angular/router';
import {filter, takeUntil} from 'rxjs/operators';
import {Subject} from 'rxjs';
import {AcqSearchTerm} from './acq-search.service';
import {LineitemResultsComponent} from './lineitem-results.component';
import {PurchaseOrderResultsComponent} from './purchase-order-results.component';
import {InvoiceResultsComponent} from './invoice-results.component';
import {PicklistResultsComponent} from './picklist-results.component';

@Component({
    templateUrl: './acq-search.component.html'
})

export class AcqSearchComponent implements OnInit, OnDestroy {

    searchType = '';
    validSearchTypes = ['lineitems', 'purchaseorders', 'invoices', 'selectionlists'];
    defaultSearchType = 'lineitems';

    urlSearchTerms: AcqSearchTerm[] = [];

    onTabChange: ($event: NgbNavChangeEvent) => void;
    @ViewChild('acqSearchTabs', { static: true }) tabs: NgbNav;
    @ViewChildren(LineitemResultsComponent) liResults: QueryList<PurchaseOrderResultsComponent>;
    @ViewChildren(PurchaseOrderResultsComponent) poResults: QueryList<PurchaseOrderResultsComponent>;
    @ViewChildren(InvoiceResultsComponent) invResults: QueryList<PurchaseOrderResultsComponent>;
    @ViewChildren(PicklistResultsComponent) plResults: QueryList<PicklistResultsComponent>;

    previousUrl: string = null;
    public destroyed = new Subject<any>();

    constructor(
        private router: Router,
        private route: ActivatedRoute,
    ) {
        this.route.queryParamMap.subscribe((params: ParamMap) => {
            this.urlSearchTerms = [];
            const fields = params.getAll('f');
            const ops = params.getAll('op');
            const values1 = params.getAll('val1');
            const values2 = params.getAll('val2');
            fields.forEach((f, idx) => {
                const term: AcqSearchTerm = {
                    field:  f,
                    op:     '',
                    value1: '',
                    value2: ''
                };
                if (idx < ops.length) {
                    term.op = ops[idx];
                }
                if (idx < values1.length) {
                    term.value1 = values1[idx];
                    if (term.value1 === 'null') {
                        // convert the string 'null' to a true
                        // null value, mostly for the benefit of the
                        // open invoices navigation link
                        term.value1 = null;
                    }
                }
                if (idx < values2.length) {
                    term.value2 = values2[idx];
                }
                this.urlSearchTerms.push(term);
                this.ngOnInit(); // TODO: probably overkill
            });
        });
        this.router.events.pipe(
            filter((event): event is NavigationEnd => event instanceof NavigationEnd),
            takeUntil(this.destroyed)
        ).subscribe(routeEvent => {
            if (routeEvent instanceof NavigationEnd) {
                // force reset of grid data source if we're navigating from
                // a search tab to the same search tab
                // eslint-disable-next-line eqeqeq
                if (this.previousUrl != null) {
                    const prevRoute = this.previousUrl.match(/acq\/search\/([a-z]+)/);
                    const newRoute = routeEvent.url.match(/acq\/search\/([a-z]+)/);
                    // eslint-disable-next-line eqeqeq
                    const prevTab = prevRoute  == null ? 'lineitems' : prevRoute[1];
                    // eslint-disable-next-line eqeqeq
                    const newTab = newRoute  == null ? 'lineitems' : newRoute[1];
                    if (prevTab === newTab) {
                        switch (newTab) {
                            case 'lineitems':
                                this.liResults.toArray()[0].gridSource.reset();
                                this.liResults.toArray()[0].acqSearchForm.ngOnInit();
                                break;
                            case 'purchaseorders':
                                this.poResults.toArray()[0].gridSource.reset();
                                this.poResults.toArray()[0].acqSearchForm.ngOnInit();
                                break;
                            case 'invoices':
                                this.invResults.toArray()[0].gridSource.reset();
                                this.invResults.toArray()[0].acqSearchForm.ngOnInit();
                                break;
                            case 'selectionlists':
                                this.plResults.toArray()[0].gridSource.reset();
                                this.plResults.toArray()[0].acqSearchForm.ngOnInit();
                                break;
                        }
                    }
                }
                this.previousUrl = routeEvent.url;
                this.ngOnInit(); // TODO: probably overkill
            }
        });
    }

    ngOnInit() {
        const self = this;

        const searchTypeParam = this.route.snapshot.paramMap.get('searchtype');

        if (searchTypeParam) {
            if (this.validSearchTypes.includes(searchTypeParam)) {
                this.searchType = searchTypeParam;
            } else {
                this.searchType = this.defaultSearchType;
                this.router.navigate(['/staff', 'acq', 'search', this.searchType]);
            }
        } else {
            this.searchType = this.defaultSearchType;
        }

        this.onTabChange = ($event) => {
            if (this.validSearchTypes.includes($event.nextId)) {
                this.searchType = $event.nextId;
                this.urlSearchTerms = [];
                this.router.navigate(['/staff', 'acq', 'search', $event.nextId]);
            }
        };
    }

    ngOnDestroy(): void {
        this.destroyed.next(null);
        this.destroyed.complete();
    }

}
