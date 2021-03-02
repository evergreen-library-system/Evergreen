import {Component, OnInit, Input} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';
import {PrintService} from '@eg/share/print/print.service';

@Component({
  templateUrl: 'summary.component.html',
  styleUrls: ['summary.component.css'],
  selector: 'eg-patron-summary'
})
export class SummaryComponent implements OnInit {

    constructor(
        private org: OrgService,
        private net: NetService,
        private printer: PrintService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {
    }

    patron(): IdlObject {
        return this.context.patron;
    }

    printAddress(addr: IdlObject) {
        this.printer.print({
            templateName: 'patron_address',
            contextData: {
                patron: this.context.patron,
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

}

