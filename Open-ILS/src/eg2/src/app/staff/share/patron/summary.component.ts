import {Component, OnInit, Input} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PrintService} from '@eg/share/print/print.service';
import {PatronService, PatronSummary} from './patron.service';

@Component({
  templateUrl: 'summary.component.html',
  styleUrls: ['summary.component.css'],
  selector: 'eg-patron-summary'
})
export class PatronSummaryComponent implements OnInit {

    @Input() summary: PatronSummary;

    constructor(
        private org: OrgService,
        private net: NetService,
        private printer: PrintService,
        public patronService: PatronService
    ) {}

    ngOnInit() {
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

    patronStatusColor(): string {

        const patron = this.p();

        if (patron.barred() === 't') {
            return 'PATRON_BARRED';
        }

        if (patron.active() === 'f') {
            return 'PATRON_INACTIVE';
        }

        if (this.summary.stats.fines.balance_owed > 0) {
           return 'PATRON_HAS_BILLS';
        }

        if (this.summary.stats.checkouts.overdue > 0) {
            return 'PATRON_HAS_OVERDUES';
        }

        if (patron.notes().length > 0) {
            return 'PATRON_HAS_NOTES';
        }

        if (this.summary.stats.checkouts.lost > 0) {
            return 'PATRON_HAS_LOST';
        }

        let penalty: string;
        let penaltyCount = 0;

        patron.standing_penalties().some(p => {
            penaltyCount++;

            if (p.standing_penalty().staff_alert() === 't' ||
                p.standing_penalty().block_list()) {
                penalty = 'PATRON_HAS_STAFF_ALERT';
                return true;
            }

            const name = p.standing_penalty();

            switch (name) {
                case 'PATRON_EXCEEDS_CHECKOUT_COUNT':
                case 'PATRON_EXCEEDS_OVERDUE_COUNT':
                case 'PATRON_EXCEEDS_FINES':
                    penalty = name;
                    return true;
            }
        });

        if (penalty) { return penalty; }

        if (penaltyCount === 1) {
            return 'ONE_PENALTY';
        } else if (penaltyCount > 1) {
            return 'MULTIPLE_PENALTIES';
        }

        if (patron.juvenile() === 't') {
            return 'PATRON_JUVENILE';
        }

        return 'NO_PENALTIES';
    }
}

