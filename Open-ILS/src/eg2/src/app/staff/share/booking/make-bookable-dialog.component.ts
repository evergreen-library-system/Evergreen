import {Component, OnInit, OnDestroy, Input, ViewChild,
        Renderer2} from '@angular/core';
import {Subscription} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {StringComponent} from '@eg/share/string/string.component';

/**
 * Dialog for making items bookable
 */

@Component({
  selector: 'eg-make-bookable-dialog',
  templateUrl: 'make-bookable-dialog.component.html'
})
export class MakeBookableDialogComponent
    extends DialogComponent implements OnInit, OnDestroy {

    // Note copyIds must refer to copies that belong to a single
    // bib record.
    @Input() copyIds: number[];
    copies: IdlObject[];

    numSucceeded: number;
    numFailed: number;
    updateComplete: boolean;

    onOpenSub: Subscription;

    @ViewChild('successMsg') private successMsg: StringComponent;
    @ViewChild('errorMsg') private errorMsg: StringComponent;

    constructor(
        private modal: NgbModal, // required for passing to parent
        private toast: ToastService,
        private net: NetService,
        private pcrud: PcrudService,
        private evt: EventService,
        private renderer: Renderer2,
        private auth: AuthService) {
        super(modal); // required for subclassing
    }

    ngOnInit() {
        this.onOpenSub = this.onOpen$.subscribe(async () => {
            this.numSucceeded = 0;
            this.numFailed = 0;
            this.updateComplete = false;
        });
    }

    ngOnDestroy() {
        this.onOpenSub.unsubscribe();
    }
}



