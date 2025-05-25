import {Component, OnInit, Input} from '@angular/core';
import {AuthService} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {PatronService, PatronSummary} from './patron.service';

/**
 * Dialog for merging 2 patron accounts.
 */

const PATRON_FLESH_FIELDS = [
    'card',
    'cards',
    'settings',
    'standing_penalties',
    'addresses',
    'billing_address',
    'mailing_address',
    'waiver_entries',
    'usr_activity',
    'notes',
    'profile',
    'net_access_level',
    'ident_type',
    'ident_type2',
    'groups'
];

@Component({
    selector: 'eg-patron-merge-dialog',
    templateUrl: 'merge-dialog.component.html'
})

export class PatronMergeDialogComponent
    extends DialogComponent implements OnInit {

    @Input() patronIds: [number, number];

    summary1: PatronSummary;
    summary2: PatronSummary;

    leadAccount: number = null;
    loading = true;

    constructor(
        private modal: NgbModal,
        private auth: AuthService,
        private net: NetService,
        private evt: EventService,
        private patrons: PatronService
    ) { super(modal); }

    ngOnInit() {
        this.onOpen$.subscribe(_ => {
            this.loading = true;
            this.leadAccount = null;
            this.loadPatron(this.patronIds[0])
                .then(ctx => this.summary1 = ctx)
                .then(__ => this.loadPatron(this.patronIds[1]))
                .then(ctx => this.summary2 = ctx)
                .then(__ => this.loading = false);
        });
    }

    loadPatron(id: number): Promise<PatronSummary> {
        const sum = new PatronSummary();
        return this.patrons.getFleshedById(id, PATRON_FLESH_FIELDS)
            .then(patron => sum.patron = patron)
            .then(_ => this.patrons.getVitalStats(sum.patron))
            .then(stats => sum.stats = stats)
            .then(_ => this.patrons.compileAlerts(sum))
            .then(alerts => sum.alerts = alerts)
            .then(_ => sum);
    }

    merge() {

        const subId = this.leadAccount === this.patronIds[0] ?
            this.patronIds[1] : this.patronIds[0];

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.merge',
            this.auth.token(), this.leadAccount, [subId]
        ).subscribe(resp => {
            const evt = this.evt.parse(resp);
            if (evt) {
                console.error(evt);
                alert(evt);
                this.close(false);
            } else {
                this.close(true);
            }
        });
    }
}



