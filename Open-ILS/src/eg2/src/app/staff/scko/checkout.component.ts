import { Component, OnDestroy, inject } from '@angular/core';
import {SckoService} from './scko.service';

import { DueDatePipe } from '@eg/core/format.service';

@Component({
    templateUrl: 'checkout.component.html',
    imports: [DueDatePipe]
})

export class SckoCheckoutComponent implements OnDestroy {
    scko = inject(SckoService);


    ngOnDestroy() {
        // Removew checkout errors when navigating away.
        this.scko.statusDisplayText = '';
    }

    printList() {
        this.scko.printReceipt();
    }
}

