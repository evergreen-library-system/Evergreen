import {Component, OnInit, Input, Output, ViewChild, EventEmitter} from '@angular/core';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {HoldsService} from './holds.service';

/** Edit holds in single or batch mode. */

@Component({
  selector: 'eg-hold-manage',
  templateUrl: 'manage.component.html'
})
export class HoldManageComponent implements OnInit {

    // One holds ID means standard edit mode.
    // >1 hold IDs means batch edit mode.
    @Input() holdIds: number[];

    hold: IdlObject;
    smsEnabled: boolean;
    smsCarriers: ComboboxEntry[];
    activeFields: {[key: string]: boolean};

    // Emits true if changes were applied to the hold.
    @Output() onComplete: EventEmitter<boolean>;

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private pcrud: PcrudService,
        private holds: HoldsService
    ) {
        this.onComplete = new EventEmitter<boolean>();
        this.smsCarriers = [];
        this.holdIds = [];
        this.activeFields = {};
    }

    ngOnInit() {
        this.org.settings('sms.enable').then(sets => {
            this.smsEnabled = sets['sms.enable'];
            if (!this.smsEnabled) { return; }

            this.pcrud.search('csc', {active: 't'}, {order_by: {csc: 'name'}})
            .subscribe(carrier => {
                this.smsCarriers.push({
                    id: carrier.id(),
                    label: carrier.name()
                });
            });
        });

        this.fetchHold();
    }

    fetchHold() {
        this.hold = null;

        if (this.holdIds.length === 0) {
            return;

        } else if (this.isBatch()) {
            // Use a dummy hold to store form values.
            this.hold = this.idl.create('ahr');

        } else {
            // Form values are stored in the one hold we're editing.
            this.pcrud.retrieve('ahr', this.holdIds[0])
            .subscribe(hold => this.hold = hold);
        }
    }

    toFormData() {

    }

    isBatch(): boolean {
        return this.holdIds.length > 1;
    }

    pickupLibChanged(org: IdlObject) {
        if (org) {
            this.hold.pickup_lib(org.id());
        }
    }

    save() {
        if (this.isBatch()) {

            // Fields with edit-active checkboxes
            const fields = Object.keys(this.activeFields)
                .filter(field => this.activeFields[field]);

            const holds: IdlObject[] = [];
            this.pcrud.search('ahr', {id: this.holdIds})
            .subscribe(
                hold => {
                    // Copy form fields to each hold to update.
                    fields.forEach(field => hold[field](this.hold[field]()));
                    holds.push(hold);
                },
                err => {},
                ()  => {
                    this.saveBatch(holds);
                }
            );
        } else {
            this.saveBatch([this.hold]);
        }
    }

    saveBatch(holds: IdlObject[]) {
        let successCount = 0;
        this.holds.updateHolds(holds)
        .subscribe(
            res  => {
                if (Number(res) > 0) {
                    successCount++;
                    console.debug('hold update succeeded with ', res);
                } else {
                    // TODO: toast?
                }
            },
            err => console.error('hold update failed with ', err),
            ()  => {
                if (successCount === holds.length) {
                    this.onComplete.emit(true);
                } else {
                    // TODO: toast?
                    console.error('Some holds failed to update');
                }
            }
        );
    }

    exit() {
        this.onComplete.emit(false);
    }
}


