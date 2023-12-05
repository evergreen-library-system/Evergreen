import { Component, Input, inject } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { SubscriptionSelectorComponent } from './subscription-selector.component';
import { StaffCommonModule } from '../common.module';
import { NetService } from '@eg/core/net.service';
import { AuthService } from '@eg/core/auth.service';
import { firstValueFrom, map, tap, throwIfEmpty, toArray } from 'rxjs';
import { IdlObject } from '@eg/core/idl.service';
import { SerialsReceiveComponent } from './serials-receive.component';

@Component({
    standalone: true,
    selector: 'eg-quick-receive',
    imports: [StaffCommonModule, SubscriptionSelectorComponent, SerialsReceiveComponent],
    templateUrl: './quick-receive.component.html'
})
export class QuickReceiveComponent {
    @Input() bibRecordId: number;
    noReceivableItems = false;
    fleshedSitems: IdlObject[];

    private auth: AuthService = inject(AuthService);
    private net: NetService = inject(NetService);
    private route: ActivatedRoute = inject(ActivatedRoute);

    constructor() {
        this.bibRecordId = Number(this.route.snapshot.params['bibRecordId']);
    }

    checkForExpectedItems(subscriptionId: number): Promise<any> {
        const fleshedSitemRequest$ = this.net.request(
            'open-ils.serial',
            'open-ils.serial.items.receivable.by_subscription',
            this.auth.token(),
            subscriptionId)
            .pipe(
                throwIfEmpty(),
                toArray(),
                map((results: IdlObject[]) => {
                    // Make sure this list of items is unique by stream ID.
                    // If there are duplicates, take the one with the earlier
                    // issuance date published.
                    return results.reduce((accumulator, result) => {
                        const matchingIndex = accumulator.findIndex((existingEntry: IdlObject) => {
                            return existingEntry.stream().id() === result.stream().id();
                        });
                        if (matchingIndex > -1) {
                            const myDate = new Date(result.issuance().date_published());
                            const existingDate = new Date(accumulator[matchingIndex].issuance().date_published());
                            if (myDate < existingDate) {
                                accumulator.splice(matchingIndex, 1);
                            } else {
                                return accumulator;
                            }
                        }
                        accumulator.push(result);
                        return accumulator;
                    }, []);
                }),
                tap({
                    next: (results) => {
                        this.fleshedSitems = results;
                    },
                    error: (error: unknown) => {
                        this.handleNoRecievableItems();
                    }
                })
            );
        return firstValueFrom(fleshedSitemRequest$);
    }

    clearSelection() {
        this.fleshedSitems = null;
        this.noReceivableItems = false;
    }

    private handleNoRecievableItems() {
        this.noReceivableItems = true;
        this.fleshedSitems = null;
    }
}
