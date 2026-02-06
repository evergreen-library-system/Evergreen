import {Component, OnInit, OnDestroy} from '@angular/core';
import { LineitemListComponent } from '../lineitem/lineitem-list.component';

@Component({
    templateUrl: 'batch_receive.component.html',
    selector: 'eg-acq-invoice-batch-receive',
    imports: [LineitemListComponent]
})
export class InvoiceBatchReceiveComponent implements OnInit, OnDestroy {

    constructor(
    ) {}

    ngOnInit() {
        console.debug('BatchReceiveComponent',this);
    }

    ngOnDestroy() {
        console.debug('BatchReceiveComponent onDestroy');
    }
}
