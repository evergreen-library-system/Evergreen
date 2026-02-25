import { Component, OnInit, Input, inject } from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {EgEvent} from '@eg/core/event.service';
import {StringService} from '@eg/share/string/string.service';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { StringComponent } from '@eg/share/string/string.component';

/*
 * Prompt to confirm overriding circulation events.
 */

@Component({
    templateUrl: 'events-dialog.component.html',
    selector: 'eg-circ-events-dialog',
    imports: [
        CommonModule,
        RouterModule,
        StringComponent
    ]
})
export class CircEventsComponent extends DialogComponent implements OnInit {
    private modal: NgbModal;
    private strings = inject(StringService);


    @Input() events: EgEvent[] = [];
    @Input() mode: 'checkout' | 'renew' | 'checkin';
    modeLabel: string;
    clearHolds = false;
    patronId: number = null;
    patronName: string;
    copyBarcode: string;

    constructor() {
        const modal = inject(NgbModal);
        super(modal);
        this.modal = modal;
    }

    ngOnInit() {
        this.onOpen$.subscribe(_ => {
            this.strings.interpolate('circ.events.mode.' + this.mode)
                .then(str => this.modeLabel = str);
        });
    }

    isArray(target: any): boolean {
        return Array.isArray(target);
    }
}

