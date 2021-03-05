import {Component, Input, OnInit, AfterViewInit} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';

@Component({
  templateUrl: 'bills.component.html',
  selector: 'eg-patron-bills',
  styleUrls: ['bills.component.css']
})
export class BillsComponent implements OnInit, AfterViewInit {

    @Input() patronId: number;
    summary: IdlObject;
    sessionVoided = 0;
    paymentType = 'cash_payment';
    checkNumber: string;
    annotatePayment = false;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private store: ServerStoreService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {
        this.load();
    }

    ngAfterViewInit() {
        const node = document.getElementById('pay-amount');
        if (node) { node.focus(); }
    }

    load() {

        this.pcrud.retrieve('mous', this.patronId, {}, {authoritative : true})
        .subscribe(sum => this.summary = sum);
    }

    patron(): IdlObject {
        return this.context.patron;
    }

    // TODO
    refundsAvailable(): number {
        return 0;
    }

    // TODO
    paidSelected(): number {
        return 0;
    }

    // TODO
    owedSelected(): number {
        return 0;
    }

    // TODO
    billedSelected(): number {
        return 0;
    }

    pendingPayment(): number {
        return 0;
    }

    pendingChange(): number {
        return 0;
    }

}

