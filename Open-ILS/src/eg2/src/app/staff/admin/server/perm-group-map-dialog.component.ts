import {Component, Input, ViewChild, TemplateRef, OnInit} from '@angular/core';
import {Observable, from, empty, throwError} from 'rxjs';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
  selector: 'eg-perm-group-map-dialog',
  templateUrl: './perm-group-map-dialog.component.html'
})

/**
 * Ask the user which part is the lead part then merge others parts in.
 */
export class PermGroupMapDialogComponent
    extends DialogComponent implements OnInit {

    @Input() permGroup: IdlObject;

    @Input() permissions: IdlObject[];

    // List of grp-perm-map objects that relate to the selected permission
    // group or are linked to a parent group.
    @Input() permMaps: IdlObject[];

    @Input() orgDepths: number[];

    // Note we have all of the permissions on hand, but rendering the
    // full list of permissions can caus sluggishness.  Render async instead.
    permEntries: (term: string) => Observable<ComboboxEntry>;

    // Permissions the user may apply to the current group.
    trimmedPerms: IdlObject[];

    depth: number;
    grantable: boolean;
    perm: number;

    constructor(
        private idl: IdlService,
        private pcrud: PcrudService,
        private modal: NgbModal) {
        super(modal);
    }

    ngOnInit() {
        this.depth = 0;
        this.grantable = false;

        this.permissions = this.permissions
            .sort((a, b) => a.code() < b.code() ? -1 : 1);

        this.onOpen$.subscribe(() => this.trimPermissions());


        this.permEntries = (term: string) => {
            if (term === null || term === undefined) { return empty(); }
            term = ('' + term).toLowerCase();

            // Find entries whose code or description match the search term

            const entries: ComboboxEntry[] =  [];
            this.trimmedPerms.forEach(p => {
                if (p.code().toLowerCase().includes(term) ||
                    (p.description() || '').toLowerCase().includes(term)) {
                    entries.push({id: p.id(), label: p.code()});
                }
            });

            return from(entries);
        };
    }

    trimPermissions() {
        this.trimmedPerms = [];

        this.permissions.forEach(p => {

            // Prevent duplicate permissions, for-loop for early exit.
            for (let idx = 0; idx < this.permMaps.length; idx++) {
                const map = this.permMaps[idx];
                if (map.perm().id() === p.id() &&
                    map.grp().id() === this.permGroup.id()) {
                    return;
                }
            }

            this.trimmedPerms.push(p);
        });
    }

    create() {
        const map = this.idl.create('pgpm');

        map.grp(this.permGroup.id());
        map.perm(this.perm);
        map.grantable(this.grantable ? 't' : 'f');
        map.depth(this.depth);

        this.pcrud.create(map).subscribe(
            newMap => this.close(newMap),
            err => throwError(err)
        );
    }
}


