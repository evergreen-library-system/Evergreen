import {Component, HostListener, OnDestroy, OnInit} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';
import {StaffCatalogService} from './catalog.service';
import {BasketService} from '@eg/share/catalog/basket.service';
import {Subject, takeUntil} from 'rxjs';

@Component({
    templateUrl: 'catalog.component.html'
})
export class CatalogComponent implements OnInit, OnDestroy {

    private onDestroy = new Subject<null>();

    constructor(
        private basket: BasketService,
        private staffCat: StaffCatalogService
    ) {}

    ngOnInit() {
        // Create the search context that will be used by all of my
        // child components.  After initial creation, the context is
        // reset and updated as needed to apply new search parameters.
        this.staffCat.createContext();

        // listen for hold patron target changes from other tabs
        // until there's a route change
        this.staffCat.onChangeHoldPatron().pipe(
            takeUntil(this.onDestroy)
        ).subscribe();

        // Subscribe to these emissions so that we can force
        // change detection in this component even though the
        // hold-for value was modified by a child component.
        this.staffCat.holdForChange.subscribe(() => {});
    }

    // Returns the 'au' object for the patron who we are
    // trying to place a hold for.
    holdForUser(): IdlObject {
        return this.staffCat.holdForUser;
    }

    clearHoldPatron() {
        this.staffCat.clearHoldPatron();
    }

    @HostListener('window:beforeunload')
    onBeforeUnload(): void {
        this.staffCat.onBeforeUnload();
    }

    ngOnDestroy(): void {
        this.clearHoldPatron();
        this.onDestroy.next(null);
    }
}

