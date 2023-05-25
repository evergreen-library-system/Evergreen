import {Component, OnInit, OnDestroy, Input} from '@angular/core';
// import {Subscription} from 'rxjs';
// import {IdlService, IdlObject} from '@eg/core/idl.service';
// import {OrgService} from '@eg/core/org.service';
// import {AuthService} from '@eg/core/auth.service';
// import {NetService} from '@eg/core/net.service';
// import {EventService} from '@eg/core/event.service';
// import {PcrudService} from '@eg/core/pcrud.service';
// import {InvoiceService} from './invoice.service';

@Component({
    templateUrl: 'batch_receive.component.html',
    selector: 'eg-acq-invoice-batch-receive'
})
export class InvoiceBatchReceiveComponent implements OnInit, OnDestroy {

    constructor(
        // private idl: IdlService,
        // private net: NetService,
        // private evt: EventService,
        // private auth: AuthService,
        // private pcrud: PcrudService,
        // private org: OrgService,
        // public  invoiceService: InvoiceService
    ) {}

    ngOnInit() {
        console.debug('BatchReceiveComponent',this);
    }

    ngOnDestroy() {
        console.debug('BatchReceiveComponent onDestroy');
    }
}
