import {Component, Input, ViewChild, TemplateRef} from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NgbModal, NgbModalOptions} from '@ng-bootstrap/ng-bootstrap';

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
        private modal: NgbModal) {
        super(modal);
    }

    mergeParts() {
        console.log('Merging parts into lead part ', this.leadPart);

        if (!this.leadPart) { return; }

        this.leadPart = Number(this.leadPart);

        // 1. Migrate copy maps to the lead part.
        const partIds = this.parts
            .filter(p => Number(p.id()) !== this.leadPart)
               .map(p => Number(p.id()));

        const maps = [];
        this.pcrud.search('acpm', {part: partIds})
        .subscribe(
            map => {
                map.part(this.leadPart);
                map.ischanged(true);
                maps.push(map);
            },
            err => {},
            ()  => {
                // 2. Delete the now-empty subordinate parts.  Note the
                // delete must come after the part map changes are committed.
                if (maps.length > 0) {
                    this.pcrud.autoApply(maps)
                        .toPromise().then(() => this.deleteParts());
                } else {
                    this.deleteParts();
                }
            }
        );
    }

    deleteParts() {
        const parts = this.parts.filter(p => Number(p.id()) !== this.leadPart);
        parts.forEach(p => p.isdeleted(true));
        this.pcrud.autoApply(parts).toPromise().then(res => this.close(res));
    }
}


