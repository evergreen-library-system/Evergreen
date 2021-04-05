import {Component, OnInit, Input} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PrintService} from '@eg/share/print/print.service';
import {PatronService, PatronStats, PatronAlerts} from './patron.service';

@Component({
  templateUrl: 'summary.component.html',
  styleUrls: ['summary.component.css'],
  selector: 'eg-patron-summary'
})
export class PatronSummaryComponent implements OnInit {

    @Input() patron: IdlObject;
    @Input() stats: PatronStats;
    @Input() alerts: PatronAlerts;

    constructor(
        private org: OrgService,
        private net: NetService,
        private printer: PrintService,
        public patronService: PatronService
    ) {}

    ngOnInit() {
    }

    hasPrefName(): boolean {
        if (this.patron) {
            return (
                this.patron.pref_first_given_name() ||
                this.patron.pref_second_given_name() ||
                this.patron.pref_family_name()
            );
        }
    }

    printAddress(addr: IdlObject) {
        this.printer.print({
            templateName: 'patron_address',
            contextData: {
                patron: this.patron,
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
        node.focus();
        node.select();

        if (!document.execCommand('copy')) {
            console.error('Copy command failed');
        }

        node.style.visibility = 'hidden';
    }

    orgSn(orgId: number): string {
        const org = this.org.get(orgId);
        return org ? org.shortname() : '';
    }
}

