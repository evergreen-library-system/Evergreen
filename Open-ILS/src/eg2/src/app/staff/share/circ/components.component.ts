import {Component, AfterViewInit, Output, Input, ViewChild, EventEmitter} from '@angular/core';
import {CircService} from './circ.service';
import {PrecatCheckoutDialogComponent
    } from '@eg/staff/share/circ/precat-dialog.component';

/* Container component for sub-components used by circulation actions.
 *
 * The CircService has to launch various dialogs for processing checkouts,
 * checkins, etc.  The service itself cannot contain components directly,
 * so we compile them here and provide references.
 * */

@Component({
  templateUrl: 'components.component.html',
  selector: 'eg-circ-components'
})
export class CircComponentsComponent implements AfterViewInit {

    @ViewChild('precatDialog')
        private precatDialog: PrecatCheckoutDialogComponent;

    constructor(private circ: CircService) {}

    ngAfterViewInit() {
        this.circ.precatDialog = this.precatDialog;
    }
}

