import {Component, OnInit, AfterViewInit, Input, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Observable, empty, of, from} from 'rxjs';
import {tap, switchMap} from 'rxjs/operators';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronManagerService} from './patron.service';
import {CheckoutResult, CircService} from '@eg/staff/share/circ/circ.service';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {GridDataSource, GridColumn, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {AudioService} from '@eg/share/util/audio.service';
import {CopyAlertsDialogComponent
    } from '@eg/staff/share/holdings/copy-alerts-dialog.component';
import {CircGridComponent} from '@eg/staff/share/circ/grid.component';

@Component({
  templateUrl: 'items.component.html',
  selector: 'eg-patron-items'
})
export class ItemsComponent implements OnInit, AfterViewInit {

    // Note we can get the patron id from this.context.patron.id(), but
    // on a new page load, this requires us to wait for the arrival of
    // the patron object before we can fetch our circs.  This is just simpler.
    @Input() patronId: number;

    itemsTab = 'checkouts';
    loading = false;
    mainList: number[] = [];
    altList: number[] = [];
    noncatDataSource: GridDataSource = new GridDataSource();

    @ViewChild('checkoutsGrid') private checkoutsGrid: CircGridComponent;

    constructor(
        private org: OrgService,
        private net: NetService,
        private auth: AuthService,
        public circ: CircService,
        private audio: AudioService,
        private store: StoreService,
        private serverStore: ServerStoreService,
        public patronService: PatronService,
        public context: PatronManagerService
    ) {}

    ngOnInit() {
    }

    ngAfterViewInit() {
        setTimeout(() => this.loadTab(this.itemsTab));
    }

    tabChange(evt: NgbNavChangeEvent) {
        setTimeout(() => this.loadTab(evt.nextId));
    }

    loadTab(name: string) {
        this.loading = true;
        let promise;
        if (name === 'checkouts') {
            promise = this.loadCheckoutsGrid();
        }

        promise.then(_ => this.loading = false);
    }

    loadCheckoutsGrid(): Promise<any> {
        this.mainList = [];
        this.altList = [];

        const promise = this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.checked_out.authoritative',
            this.auth.token(), this.patronId
        ).toPromise().then(checkouts => {
            this.mainList = checkouts.overdue.concat(checkouts.out);

            // TODO promise_circs, etc.
        });

        // TODO: fetch checked in

        return promise.then(_ => {
            this.checkoutsGrid.load(this.mainList)
            .subscribe(null, null, () => this.checkoutsGrid.reloadGrid());
        });
    }

    /*
    function get_circ_ids() {
        $scope.main_list = [];
        $scope.alt_list = [];

        // we can fetch these in parallel
        var promise1 = egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.user.checked_out.authoritative',
            egCore.auth.token(), $scope.patron_id
        ).then(function(outs) {
            $scope.main_list = outs.overdue.concat(outs.out);
            promote_circs(outs.lost, display_lost, true);
            promote_circs(outs.long_overdue, display_lo, true);
            promote_circs(outs.claims_returned, display_cr, true);
        });

        // only fetched checked-in-with-bills circs if configured to display
        var promise2 = !fetch_checked_in ? $q.when() : egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.user.checked_in_with_fines.authoritative',
            egCore.auth.token(), $scope.patron_id
        ).then(function(outs) {
            promote_circs(outs.lost, display_lost);
            promote_circs(outs.long_overdue, display_lo);
            promote_circs(outs.claims_returned, display_cr);
        });

        return $q.all([promise1, promise2]);
    }
    */

}


