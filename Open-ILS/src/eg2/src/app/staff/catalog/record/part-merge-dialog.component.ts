import {Component, Input, ViewChild, TemplateRef} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import { HoldsService } from '@eg/staff/share/holds/holds.service';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';
import { EmptyError, firstValueFrom, lastValueFrom, map, tap, toArray} from 'rxjs';

@Component({
    selector: 'eg-catalog-part-merge-dialog',
    templateUrl: './part-merge-dialog.component.html'
})

/**
 * Ask the user which part is the lead part then merge others parts in.
 */
export class PartMergeDialogComponent extends DialogComponent {

    // What parts are we merging
    parts: IdlObject[];
    copyPartMaps: IdlObject[];
    leadPart: number;

    constructor(
        private idl: IdlService,
        private pcrud: PcrudService,
        private holds: HoldsService,
        private modal: NgbModal) {
        super(modal);
    }

    // 1. Apply lead part to all copies 2. Apply lead part to all holds 3. Delete subordinate parts - which should have no copies
    mergeParts() {

        if (!this.leadPart) { return; }
        this.leadPart = Number(this.leadPart);
        console.log('Merging parts into lead part ', this.leadPart);

        this.remapParts().then(() => {
            return this.updatePartHolds().then(() =>{
                return this.deleteParts();
            });
        });
    }

    remapParts() : Promise<any>{
        if (!this.leadPart) { return; }

        this.leadPart = Number(this.leadPart);

        // 1. Migrate copy maps to the lead part.
        const partIds = this.parts
            .filter(p => Number(p.id()) !== this.leadPart)
            .map(p => Number(p.id()));

        return lastValueFrom(
            this.pcrud.search('acpm', {part: partIds})
                .pipe(
                    map((acpm: IdlObject) => {
                        acpm.part(this.leadPart);
                        acpm.ischanged(true);
                        return acpm;
                    }),
                    toArray()
                ),
            {defaultValue: []}
        ).then((part_maps) => {
            if (part_maps.length > 0){
                console.log('Changing the part assigned to ' + part_maps.length + ' items...');
                return lastValueFrom(this.pcrud.autoApply(part_maps))
                    .then(() => console.log('Part assignment change finished'));
            } else {
                console.log('No items to reassign parts to, skipping...');
            }
        });
    }

    updatePartHolds() : Promise<any> {
        // 1. Find all active holds that are targeting the subordinate parts.
        const partIds = this.parts.filter(p => Number(p.id()) !== this.leadPart)
            .map(p => Number(p.id()));
        return lastValueFrom(
            this.pcrud.search('ahr', { target: partIds , hold_type: 'P', fulfillment_time: null})
                .pipe(
                    map((ahr : IdlObject) => {
                        // 2. Make each hold target the new lead part
                        ahr.target(this.leadPart);
                        ahr.ischanged(true);
                        return ahr;
                    }),
                    toArray()
                ),
            {defaultValue: []}
        ).then(part_holds => {
            if (part_holds.length > 0){
                // 3. Save the new holds as a batch
                console.log('Attempting to update ' + part_holds.length + ' holds...');
                return lastValueFrom(this.holds.updateHolds(part_holds))
                    .then(() => console.log('Hold Update Finished'));
            } else{
                console.log('No holds to update, skipping...');
            }
        });
    }

    deleteParts() {
        const parts = this.parts.filter(p => Number(p.id()) !== this.leadPart);
        parts.forEach(p => p.isdeleted(true));
        return lastValueFrom(this.pcrud.autoApply(parts)).then(res => this.close(res));
    }
}


