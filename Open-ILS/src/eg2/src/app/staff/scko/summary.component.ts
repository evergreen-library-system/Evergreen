import {Component, OnInit} from '@angular/core';
import {SckoService} from './scko.service';
import { IdlObject } from '@eg/core/idl.service';

@Component({
    selector: 'eg-scko-summary',
    templateUrl: 'summary.component.html'
})

export class SckoSummaryComponent implements OnInit {

    showEmailOption = false;
    receiptType = 'email';

    constructor(
        public scko: SckoService
    ) {}

    ngOnInit() {
        this.scko.patronLoaded.subscribe(() => {
            this.showEmailOption = this.canEmail();
            this.receiptType = this.showEmailOption &&
                this.prefersEmail() ? 'email' : 'print';
        });
    }

    canEmail(): boolean {
        return Boolean(this.scko.patronSummary?.patron?.email());
    }

    prefersEmail(): boolean {
        const settings = this.scko.patronSummary?.patron?.settings();
        return (settings ?? []).some((setting: IdlObject) =>
            setting.name() === 'circ.send_email_checkout_receipts' &&
            setting.value() === 'true'
        );
    }
}

