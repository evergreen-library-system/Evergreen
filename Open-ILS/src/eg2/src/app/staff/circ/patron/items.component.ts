/* eslint-disable no-bitwise, no-magic-numbers */
import {Component, OnInit, Input, ViewChild} from '@angular/core';
import {tap} from 'rxjs';
import {NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';
import {CheckoutResult, CircService} from '@eg/staff/share/circ/circ.service';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {AudioService} from '@eg/share/util/audio.service';
import {CircGridComponent, CircGridEntry} from '@eg/staff/share/circ/grid.component';

@Component({
    templateUrl: 'items.component.html',
    selector: 'eg-patron-items'
})
export class ItemsComponent implements OnInit {

    // Note we can get the patron id from this.context.patron.id(), but
    // on a new page load, this requires us to wait for the arrival of
    // the patron object before we can fetch our circs.  This is just simpler.
    @Input() patronId: number;

    itemsTab = 'checkouts';
    loading = false;
    mainList: number[] = [];
    altList: number[] = [];

    displayLost: number = null; // 1 | 2 | 5 | 6;
    displayLongOverdue: number = null;
    displayClaimsReturned: number = null;
    fetchCheckedIn = true;
    displayAltList = true;

    @ViewChild('checkoutsGrid') private checkoutsGrid: CircGridComponent;
    @ViewChild('otherGrid') private otherGrid: CircGridComponent;
    @ViewChild('nonCatGrid') private nonCatGrid: CircGridComponent;

    constructor(
        private org: OrgService,
        private net: NetService,
        private pcrud: PcrudService,
        private auth: AuthService,
        public circ: CircService,
        private audio: AudioService,
        private store: StoreService,
        private serverStore: ServerStoreService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {
        this.load(true);
    }

    load(firstLoad?: boolean): Promise<any> {
        this.loading = true;

        if (firstLoad) {
            return this.applyDisplaySettings()
                .then(_ => this.loadTab(this.itemsTab));
        } else {
            return this.loadTab(this.itemsTab)
                .then(_ => this.context.refreshPatron());
        }
    }

    tabChange(evt: NgbNavChangeEvent) {
        this.itemsTab = evt.nextId;
        setTimeout(() => this.loadTab(this.itemsTab));
    }

    loadTab(name: string): Promise<any> {
        this.loading = true;
        let promise;
        if (name === 'checkouts') {
            promise = this.loadMainGrid();
        } else if (name === 'other') {
            promise = this.loadAltGrid();
        } else {
            promise = this.loadNonCatGrid();
        }

        return promise.then(_ => this.loading = false);
    }

    applyDisplaySettings(): Promise<any> {

        if (this.displayLost !== null) {
            // Logic already executed
            return Promise.resolve();
        }

        return this.serverStore.getItemBatch([
            'ui.circ.items_out.lost',
            'ui.circ.items_out.longoverdue',
            'ui.circ.items_out.claimsreturned'
        ]).then(sets => {

            this.displayLost =
                Number(sets['ui.circ.items_out.lost']) || 2;
            this.displayLongOverdue =
                Number(sets['ui.circ.items_out.longoverdue']) || 2;
            this.displayClaimsReturned =
                Number(sets['ui.circ.items_out.claimsreturned']) || 2;

            if (this.displayLost & 4 &&
                this.displayLongOverdue & 4 &&
                this.displayClaimsReturned & 4) {

                // all special types are configured to be hidden once
                // checked in, so there's no need to fetch checked-in circs.
                this.fetchCheckedIn = false;

                if (this.displayLost & 1 &&
                    this.displayLongOverdue & 1 &&
                    this.displayClaimsReturned & 1) {
                    // additionally, if all types are configured to display
                    // in the main list while checked out, nothing will
                    // ever appear in the alternate list, so we can hide
                    // the alternate list from the UI.
                    this.displayAltList = false;
                }
            }
        });
    }

    // Determine which grid ('checkouts' or 'other') a circ should appear in.
    promoteCircs(list: number[], displayCode: number, xactOpen?: boolean) {
        if (xactOpen) {
            if (1 & displayCode) { // bitflag 1 == main list
                this.mainList = this.mainList.concat(list);
            } else {
                this.altList = this.altList.concat(list);
            }
        } else {
            if (4 & displayCode) { return; }  // bitflag 4 == hide on checkin
            this.altList = this.altList.concat(list);
        }
    }

    getCircIds(): Promise<any> {
        this.mainList = [];
        this.altList = [];

        const promise = this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.checked_out.authoritative',
            this.auth.token(), this.patronId
        ).toPromise().then(checkouts => {
            this.mainList = checkouts.overdue.concat(checkouts.out);
            this.promoteCircs(checkouts.lost, this.displayLost, true);
            this.promoteCircs(checkouts.long_overdue, this.displayLongOverdue, true);
            this.promoteCircs(checkouts.claims_returned, this.displayClaimsReturned, true);
        });

        if (!this.fetchCheckedIn) { return promise; }

        return promise.then(_ => {
            return this.net.request(
                'open-ils.actor',
                'open-ils.actor.user.checked_in_with_fines.authoritative',
                this.auth.token(), this.patronId
            ).toPromise().then(checkouts => {
                this.promoteCircs(checkouts.lost, this.displayLost);
                this.promoteCircs(checkouts.long_overdue, this.displayLongOverdue);
                this.promoteCircs(checkouts.claims_returned, this.displayClaimsReturned);
            });
        });
    }

    loadMainGrid(): Promise<any> {
        return this.getCircIds()
            .then(_ => this.checkoutsGrid.load(this.mainList).toPromise())
            .then(_ => this.checkoutsGrid.reloadGrid());
    }

    loadAltGrid(): Promise<any> {
        return this.getCircIds()
            .then(_ => this.otherGrid.load(this.altList).toPromise())
            .then(_ => this.otherGrid.reloadGrid());
    }

    loadNonCatGrid(): Promise<any> {

        return this.net.request(
            'open-ils.circ',
            'open-ils.circ.open_non_cataloged_circulation.user.batch.authoritative',
            this.auth.token(), this.patronId)

            .pipe(tap(circ => {
                const entry: CircGridEntry = {
                    index: `ancc-${circ.id()}`,
                    title: circ.item_type().name(),
                    dueDate: circ.duedate(),
                    copy: null,
                    author: '',
                    isbn: ''
                };

                this.nonCatGrid.appendGridEntry(entry);
            })).toPromise()

            .then(_ => this.nonCatGrid.reloadGrid());
    }
}


