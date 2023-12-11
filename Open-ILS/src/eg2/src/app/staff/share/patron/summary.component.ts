import {Component, OnInit, Input} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PrintService} from '@eg/share/print/print.service';
import {PatronService, PatronSummary} from './patron.service';
import {ServerStoreService} from '@eg/core/server-store.service';

@Component({
    templateUrl: 'summary.component.html',
    styleUrls: ['summary.component.css'],
    selector: 'eg-patron-summary'
})
export class PatronSummaryComponent implements OnInit {

    private _summary: PatronSummary;
    @Input() set summary(s: PatronSummary) {
        if (s && this._summary && s.id !== this._summary.id) {
            this.showDob = this.showDobDefault;
        }
        this._summary = s;
    }

    get summary(): PatronSummary {
        return this._summary;
    }

    showDobDefault = false;
    showDob = false;
    penalties: number = 0;

    constructor(
        private org: OrgService,
        private net: NetService,
        private printer: PrintService,
        private serverStore: ServerStoreService,
        public patronService: PatronService
    ) {}

    ngOnInit() {
        this.serverStore.getItem('circ.obscure_dob').then(hide => {
            this.showDobDefault = this.showDob = !hide;
        });
    }

    p(): IdlObject { // patron shorthand
        return this.summary ? this.summary.patron : null;
    }

    hasPrefName(): boolean {
        if (this.p()) {
            return (
                this.p().pref_first_given_name() ||
                this.p().pref_second_given_name() ||
                this.p().pref_family_name()
            );
        }
    }

    penaltyLabel(pen: IdlObject): string {
        if (pen.usr_message()) {
            // They don't often have titles, but defaulting to
            // title, assuming it will be shorter and therefore more
            // appropriate for summary display.
            return pen.usr_message().title() || pen.usr_message().message();
        }
        return pen.standing_penalty().label();
    }

    printAddress(addr: IdlObject) {
        this.printer.print({
            templateName: 'patron_address',
            contextData: {
                patron: this.p(),
                address: addr
            },
            printContext: 'default'
        });
    }

    copyAddress(addr: IdlObject) {
        // Note navigator.clipboard requires special permissions.
        // This is hinky, but gets the job done without the perms.

        const node = document.getElementById(
            `patron-address-copy-${addr.id()}`) as HTMLTextAreaElement;

        // Un-hide the textarea just long enough to copy its data.
        // Using node.style instead of *ngIf in hopes it
        // will be quicker, so the user never sees the textarea.
        node.style.visibility = 'visible';
        node.style.display = 'block';
        node.focus();
        node.select();

        if (!document.execCommand('copy')) {
            console.error('Copy command failed');
        }

        node.style.visibility = 'hidden';
        node.style.display = 'none';
    }

    orgSn(orgId: number): string {
        const org = this.org.get(orgId);
        return org ? org.shortname() : '';
    }

    patronStatusCodes(): string[] {

        const patron = this.p();

        let codes = [];

        if (patron.barred() === 't') {
            codes.push('PATRON_BARRED');
        }

        if (patron.active() === 'f') {
            codes.push('PATRON_INACTIVE');
        }

        if (this.summary.stats.fines.balance_owed > 0) {
            codes.push('PATRON_HAS_BILLS');
        }

        if (this.summary.stats.checkouts.overdue > 0) {
            codes.push('PATRON_HAS_OVERDUES');
        }

        if (patron.notes().length > 0) {
            codes.push('PATRON_HAS_NOTES');
        }

        if (this.summary.stats.checkouts.lost > 0) {
            codes.push('PATRON_HAS_LOST');
        }

        let penalty: string;
        let penaltyCount = 0;

        patron.standing_penalties().some(p => {
            penaltyCount++;

            if (p.standing_penalty().staff_alert() === 't' ||
                p.standing_penalty().block_list()) {
                codes.push('PATRON_HAS_STAFF_ALERT');
            }

            const name = p.standing_penalty();

            switch (name) {
                case 'PATRON_EXCEEDS_CHECKOUT_COUNT':
                case 'PATRON_EXCEEDS_OVERDUE_COUNT':
                case 'PATRON_EXCEEDS_FINES':
                    penalty = name;
                    codes.push(name);
            }
        });

        if (penaltyCount > 1) {
            codes.push('MULTIPLE_PENALTIES');
        }
        else if (penaltyCount === 1) {
            codes.push('ONE_PENALTY');
        }
        else {
            codes.push('NO_PENALTIES');
        }

        this.penalties = penaltyCount;

        if (patron.juvenile() === 't') {
            codes.push('PATRON_JUVENILE');
        }

        if (this.summary.alerts.accountExpired || this.summary.alerts.accountExpiresSoon) {
            codes.push('PATRON_EXPIRED');
        }

        return codes;
    }
}

