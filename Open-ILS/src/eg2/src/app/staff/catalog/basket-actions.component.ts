import {Component, OnInit, ViewChild} from '@angular/core';
import {BasketService} from '@eg/share/catalog/basket.service';
import {Router} from '@angular/router';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PrintService} from '@eg/share/print/print.service';
import {BucketDialogComponent
    } from '@eg/staff/share/buckets/bucket-dialog.component';

@Component({
  selector: 'eg-catalog-basket-actions',
  templateUrl: 'basket-actions.component.html'
})
export class BasketActionsComponent implements OnInit {

    basketAction: string;

    @ViewChild('addBasketToBucketDialog', { static: true })
        addToBucketDialog: BucketDialogComponent;

    constructor(
        private router: Router,
        private net: NetService,
        private auth: AuthService,
        private printer: PrintService,
        private basket: BasketService
    ) {
        this.basketAction = '';
    }

    ngOnInit() {
    }

    basketCount(): number {
        return this.basket.recordCount();
    }

    // TODO: confirmation dialogs?

    applyAction(action: string) {
        this.basketAction = action;
        console.debug('Performing basket action', this.basketAction);

        switch (this.basketAction) {
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


