import {Component, OnInit, NgZone, HostListener} from '@angular/core';
import {Location} from '@angular/common';
import {Router, ActivatedRoute, NavigationEnd} from '@angular/router';
import {AuthService, AuthWsState} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {StoreService} from '@eg/core/store.service';
import {SckoService} from './scko.service';
import {OrgService} from '@eg/core/org.service';
import {EventService, EgEvent} from '@eg/core/event.service';

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
        if (!this.scko.patronSummary) { return false; }

        const patron = this.scko.patronSummary.patron;

        const setting = patron.settings().filter(
            s => s.name() === 'circ.send_email_checkout_receipts')[0];

        return (
            Boolean(patron.email())
            && patron.email().match(/.*@.*/) !== null
            && setting
            && setting.value() === 'true' // JSON
        );
    }
}

