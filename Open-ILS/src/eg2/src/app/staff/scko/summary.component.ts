import { Component, OnInit, inject } from '@angular/core';
import {SckoService} from './scko.service';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterModule } from '@angular/router';
import { IdlObject } from '@eg/core/idl.service';

@Component({
    selector: 'eg-scko-summary',
    templateUrl: 'summary.component.html',
    imports: [
        CommonModule,
        FormsModule,
        RouterModule
    ]
})

export class SckoSummaryComponent implements OnInit {
    scko = inject(SckoService);


    showEmailOption = false;
    receiptType = 'email';

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

