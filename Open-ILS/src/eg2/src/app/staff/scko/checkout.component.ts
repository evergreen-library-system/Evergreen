import {Component, OnDestroy} from '@angular/core';
import {SckoService} from './scko.service';
import { CommonModule } from '@angular/common';
import { DueDatePipe } from '@eg/core/format.service';

@Component({
    templateUrl: 'checkout.component.html',
    imports: [CommonModule, DueDatePipe]
})

export class SckoCheckoutComponent implements OnDestroy {

    constructor(
        public  scko: SckoService
    ) {}

    ngOnDestroy() {
        // Removew checkout errors when navigating away.
        this.scko.statusDisplayText = '';
    }

    printList() {
        this.scko.printReceipt();
    }
}

