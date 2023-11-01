import {Component, OnInit} from '@angular/core';
import {SckoService} from './scko.service';

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
            if (this.canEmail()) {
                this.showEmailOption = true;
                this.receiptType = 'email';
            } else {
                this.showEmailOption = false;
                this.receiptType = 'print';
            }
        });
    }

    canEmail(): boolean {
        return Boolean(this.scko.patronSummary?.patron?.email());
    }
}

