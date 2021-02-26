import {Component, OnInit, Output, Input, ViewChild, EventEmitter} from '@angular/core';
import {CircService} from './circ.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import {EgEvent} from '@eg/core/event.service';
import {StringService} from '@eg/share/string/string.service';

/*
 * Prompt to confirm overriding circulation events.
 */

@Component({
  templateUrl: 'events-dialog.component.html',
  selector: 'eg-circ-events-dialog'
})
export class CircEventsComponent extends DialogComponent implements OnInit {

    @Input() events: EgEvent[] = [];
    @Input() mode: 'checkout' | 'renew' | 'checkin';
    modeLabel: string;

    constructor(
        private modal: NgbModal,
        private strings: StringService
    ) { super(modal); }

    ngOnInit() {
        this.onOpen$.subscribe(_ => {
            this.strings.interpolate('circ.events.mode.' + this.mode)
                .then(str => this.modeLabel = str);
        });
    }
}

