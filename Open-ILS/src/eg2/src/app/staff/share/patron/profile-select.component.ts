import {Component, Input, Output, OnInit,
    EventEmitter, ViewChild, forwardRef} from '@angular/core';
import {ControlValueAccessor, NG_VALUE_ACCESSOR} from '@angular/forms';
import {Observable, of} from 'rxjs';
import {map} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ComboboxEntry, ComboboxComponent
    } from '@eg/share/combobox/combobox.component';

/* User permission group select comoboxbox.
 *
 * <eg-profile-select
 *  [(ngModel)]="pgtObject" [useDisplayEntries]="true">
 * </eg-profile-select>
 */

// Use a unicode char for spacing instead of ASCII=32 so the browser
// won't collapse the nested display entries down to a single space.
const PAD_SPACE = ' '; // U+2007

@Component({
  selector: 'eg-profile-select',
  templateUrl: './profile-select.component.html',
  providers: [{
    provide: NG_VALUE_ACCESSOR,
    useExisting: forwardRef(() => ProfileSelectComponent),
    multi: true
  }]
})
export class ProfileSelectComponent implements ControlValueAccessor, OnInit {

    // If true, attempt to build the selector from
    // permission.grp_tree_display_entry's for the current org unit.
    // If false OR if no permission.grp_tree_display_entry's exist
    // build the selector from the full permission.grp_tree
    @Input() useDisplayEntries: boolean;

    // Emits the selected 'pgt' object or null if the selector is cleared.
    @Output() profileChange: EventEmitter<IdlObject>;

    @ViewChild('combobox', {static: false}) cbox: ComboboxComponent;

    initialValue: number;
    cboxEntries: ComboboxEntry[] = [];
    profiles: {[id: number]: IdlObject} = {};

    // Stub functions required by ControlValueAccessor
    propagateChange = (_: any) => {};
    propagateTouch = () => {};

    constructor(
        private org: OrgService,
        private auth: AuthService,
        private pcrud: PcrudService) {
        this.profileChange = new EventEmitter<IdlObject>();
    }

    ngOnInit() {
        this.collectGroups().then(grps => this.sortGroups(grps));
    }

    collectGroups(): Promise<IdlObject[]> {

        if (!this.useDisplayEntries) {
            return this.fetchPgt();
        }

        return this.pcrud.search('pgtde',
            {org: this.org.ancestors(this.auth.user().ws_ou(), true)},
            {flesh: 1, flesh_fields: {'pgtde': ['grp']}},
            {atomic: true}

        ).toPromise().then(groups => {

            if (groups.length === 0) { return this.fetchPgt(); }

            // In the query above, we fetch display entries for our org
            // unit plus ancestors.  However, we only want to use one
            // collection of display entries, those owned at our org
            // unit or our closest ancestor.
            let closestOrg = this.org.get(groups[0].org());
            groups.forEach(g => {
                const org = this.org.get(g.org());
                if (closestOrg.ou_type().depth() < org.ou_type().depth()) {
                    closestOrg = org;
                }
            });
            groups = groups.filter(g => g.org() === closestOrg.id());

            // Link the display entry to its pgt.
            const pgtList = [];
            groups.forEach(display => {
                const pgt = display.grp();
                pgt._display = display;
                pgtList.push(pgt);
            });

            return pgtList;
        });
    }

    fetchPgt(): Promise<IdlObject[]> {
        return this.pcrud.retrieveAll('pgt', {}, {atomic: true}).toPromise();
    }

    grpLabel(groups: IdlObject[], grp: IdlObject): string {
        let tmp = grp;
        let depth = 0;

        do {
            const pid = tmp._display ? tmp._display.parent() : tmp.parent();
            if (!pid) { break; } // top of the tree

            // Should always produce a value unless a perm group
            // display tree is poorly structured.
            tmp = groups.filter(g => g.id() === pid)[0];

            depth++;

        } while (tmp);

        return PAD_SPACE.repeat(depth) + grp.name();
    }

    sortGroups(groups: IdlObject[], grp?: IdlObject) {
        if (!grp) {
            grp = groups.filter(g => g.parent() === null)[0];
        }

        this.profiles[grp.id()] = grp;
        this.cboxEntries.push(
            {id: grp.id(), label: this.grpLabel(groups, grp)});

        groups
            .filter(g => g.parent() === grp.id())
            .sort((a, b) => {
                if (a._display) {
                    return a._display.position() < b._display.position() ? -1 : 1;
                } else {
                    return a.name() < b.name() ? -1 : 1;
                }
            })
            .forEach(child => this.sortGroups(groups, child));
    }

    writeValue(pgt: IdlObject) {
        const id = pgt ? pgt.id() : null;
        if (this.cbox) {
            this.cbox.selectedId = id;
        } else {
            // Will propagate to cbox after its instantiated.
            this.initialValue = id;
        }
    }

    registerOnChange(fn) {
        this.propagateChange = fn;
    }

    registerOnTouched(fn) {
        this.propagateTouch = fn;
    }

    propagateCboxChange(entry: ComboboxEntry) {
        if (entry) {
            const grp = this.profiles[entry.id];
            this.propagateChange(grp);
            this.profileChange.emit(grp);
        } else {
            this.profileChange.emit(null);
            this.propagateChange(null);
        }
    }
}

