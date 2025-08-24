import {Component, ViewChild} from '@angular/core';
import {BasketService} from '@eg/share/catalog/basket.service';
import {Router} from '@angular/router';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PrintService} from '@eg/share/print/print.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {StaffCatalogService} from './catalog.service';
import {BucketDialogComponent
} from '@eg/staff/share/buckets/bucket-dialog.component';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';

const MAX_FROM_SEARCH_RESULTS = 1000;

@Component({
    selector: 'eg-catalog-basket-actions',
    templateUrl: 'basket-actions.component.html'
})
export class BasketActionsComponent {

    basketAction: string;
    recordId: number;
    recordInBasket: boolean;

    @ViewChild('addBasketToBucketDialog', { static: true })
        addToBucketDialog: BucketDialogComponent;

    @ViewChild('addAllProgress', {static: true})
        addAllProgress: ProgressDialogComponent;

    constructor(
        private router: Router,
        private net: NetService,
        private auth: AuthService,
        private printer: PrintService,
        private basket: BasketService,
        private cat: CatalogService,
        private staffCat: StaffCatalogService,
    ) {
        this.basketAction = '';
    }

    ngOnInit() {
        this.recordId = this.staffCat.searchContext.currentRecordId;
        this.recordInBasket = this.basket.hasRecordId(this.recordId);
    }

    basketCount(): number {
        return this.basket.recordCount();
    }

    isRecordView(): Boolean {
        return !this.staffCat.searchContext.showBasket && this.recordId !== null && this.recordId !== undefined;
    }

    canAddRecord(): Boolean {
        return this.isRecordView() && !this.recordInBasket;
    }

    canRemoveRecord(): Boolean {
        return this.isRecordView() && this.recordInBasket;
    }

    isMetarecordSearch(): boolean {
        return this.staffCat.searchContext &&
            this.staffCat.searchContext.termSearch.isMetarecordSearch();
    }

    // TODO: confirmation dialogs?

    applyAction(action: string) {
        this.basketAction = action;

        switch (this.basketAction) {

            case 'add_all':
                // Add all search results to basket.

                this.addAllProgress.open();

                // eslint-disable-next-line no-case-declarations
                const ctx = this.staffCat.cloneContext(this.staffCat.searchContext);
                ctx.pager.offset = 0;
                ctx.pager.limit = MAX_FROM_SEARCH_RESULTS;

                this.cat.search(ctx)
                    .then(_ => this.basket.addRecordIds(ctx.currentResultIds()))
                    .then(_ => this.addAllProgress.close());

                break;

            case 'add_record':
                this.basket.addRecordIds([this.recordId]);
                this.recordInBasket = this.basket.hasRecordId(this.recordId);
                break;
            
            case 'remove_record':
                this.basket.removeRecordIds([this.recordId]);
                this.recordInBasket = this.basket.hasRecordId(this.recordId);
                break;

            case 'view':
                // This does not propagate search params -- unclear if needed.
                this.router.navigate(['/staff/catalog/search'],
                    {queryParams: {showBasket: true}});
                break;

            case 'clear':
                this.basket.removeAllRecordIds();
                break;

            case 'hold':
                this.basket.getRecordIds().then(ids => {
                    this.router.navigate(['/staff/catalog/hold/T'],
                        {queryParams: {target: ids}});
                });
                break;

            case 'print':
                this.basket.getRecordIds().then(ids => {
                    this.net.request(
                        'open-ils.search',
                        'open-ils.search.biblio.record.print', ids
                    ).subscribe(
                        at_event => {
                            // check for event..
                            const html = at_event.template_output().data();
                            this.printer.print({
                                text: html,
                                printContext: 'default'
                            });
                        }
                    );
                });
                break;

            case 'email':
                this.basket.getRecordIds().then(ids => {
                    this.net.request(
                        'open-ils.search',
                        'open-ils.search.biblio.record.email',
                        this.auth.token(), ids
                    ).toPromise(); // fire-and-forget
                });
                break;

            case 'export_marc':
                this.router.navigate(
                    ['/staff/cat/vandelay/export/basket'],
                    {queryParamsHandling: 'merge'}
                );
                break;

            case 'bucket':
                this.basket.getRecordIds().then(ids => {
                    this.addToBucketDialog.bucketClass = 'biblio';
                    this.addToBucketDialog.itemIds = ids;
                    this.addToBucketDialog.open({size: 'lg'});
                });
                break;

        }

        // Resetting basketAction inside its onchange handler
        // prevents the new value from propagating to Angular
        // Reset after the current thread.
        setTimeout(() => this.basketAction = ''); // reset
    }
}


