/** TODO PORT ME TO <eg-combobox> */
import {Component, OnInit, Input, Output, ViewChild, EventEmitter} from '@angular/core';
import {Observable, Subject} from 'rxjs';
import {map, mapTo, debounceTime, distinctUntilChanged, merge, filter} from 'rxjs/operators';
import {AuthService} from '@eg/core/auth.service';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {OrgService} from '@eg/core/org.service';
import {IdlObject} from '@eg/core/idl.service';
import {PermService} from '@eg/core/perm.service';
import {NgbTypeahead, NgbTypeaheadSelectItemEvent} from '@ng-bootstrap/ng-bootstrap';

/** Org unit selector
 *
 * The following precedence is used when applying a load-time value
 *
 * 1. initialOrg / initialOrgId
 * 2. Value from server setting specificed with persistKey (fires onload).
 * 3. Value from fallbackOrg / fallbackOrgId (fires onload).
 * 4. Default applyed when applyDefault is set (fires onload).
 *
 * Users can detect when the component has completed its load-time
 * machinations by subscribing to the componentLoaded Output which
 * fires exactly once when loading is completed.
 */

// Use a unicode char for spacing instead of ASCII=32 so the browser
// won't collapse the nested display entries down to a single space.
const PAD_SPACE = ' '; // U+2007

interface OrgDisplay {
  id: number;
  label: string;
  disabled: boolean;
}

@Component({
  selector: 'eg-org-select',
  templateUrl: './org-select.component.html'
})
export class OrgSelectComponent implements OnInit {

    selected: OrgDisplay;
    click$ = new Subject<string>();
    valueFromSetting: number = null;
    sortedOrgs: IdlObject[] = [];

    // Disable the entire input
    @Input() disabled: boolean;

    @ViewChild('instance', { static: false }) instance: NgbTypeahead;

    // Placeholder text for selector input
    @Input() placeholder = '';

    // ID to display in the DOM for this selector
    @Input() domId = '';

    // Org unit field displayed in the selector
    @Input() displayField = 'shortname';

    // if no initialOrg is provided, none could be found via persist
    // setting, and no fallbackoOrg is provided, apply a sane default.
    // First tries workstation org unit, then user home org unit.
    // An onChange event WILL be generated when a default is applied.
    @Input() applyDefault = false;

    @Input() readOnly = false;

    // List of org unit IDs to exclude from the selector
    hidden: number[] = [];
    @Input() set hideOrgs(ids: number[]) {
        if (ids) { this.hidden = ids; }
    }

    // List of org unit IDs to disable in the selector
    _disabledOrgs: number[] = [];
    @Input() set disableOrgs(ids: number[]) {
        if (ids) { this._disabledOrgs = ids; }
    }

    // Apply an org unit value at load time.
    // These will NOT result in an onChange event.
    @Input() initialOrg: IdlObject;
    @Input() initialOrgId: number;

    // Value is persisted via server setting with this key.
    // Key is prepended with 'eg.orgselect.'
    @Input() persistKey: string;

    // If no initialOrg is provided and no value could be found
    // from a persist setting, fall back to one of these values.
    // These WILL result in an onChange event
    @Input() fallbackOrg: IdlObject;
    @Input() fallbackOrgId: number;

    // Modify the selected org unit via data binding.
    // This WILL NOT result in an onChange event firing.
    @Input() set applyOrg(org: IdlObject) {
        if (org) {
            this.selected = this.formatForDisplay(org);
        }
    }

    // Modify the selected org unit by ID via data binding.
    // This WILL NOT result in an onChange event firing.
    @Input() set applyOrgId(id: number) {
        if (id) {
            this.selected = this.formatForDisplay(this.org.get(id));
        }
    }

    // Limit org unit display to those where the logged in user
    // has the following permissions.
    permLimitOrgs: number[];
    @Input() set limitPerms(perms: string[]) {
        this.applyPermLimitOrgs(perms);
    }

    // Emitted when the org unit value is changed via the selector.
    // Does not fire on initialOrg
    @Output() onChange = new EventEmitter<IdlObject>();

    // Emitted once when the component is done fetching settings
    // and applying its initial value.  For apps that use the value
    // of this selector to load data, this event can be used to reliably
    // detect when the selector is done with all of its automated
    // underground shuffling and landed on a value.
    @Output() componentLoaded: EventEmitter<void> = new EventEmitter<void>();

    // convenience method to get an IdlObject representing the current
    // selected org unit. One way of invoking this is via a template
    // reference variable.
    selectedOrg(): IdlObject {
        if (this.selected == null) {
            return null;
        }
        return this.org.get(this.selected.id);
    }

    constructor(
      private auth: AuthService,
      private store: StoreService,
      private serverStore: ServerStoreService,
      private org: OrgService,
      private perm: PermService
    ) { }

    ngOnInit() {

        // Sort the tree and reabsorb to propagate the sorted nodes to
        // the org.list() used by this component.  Maintain our own
        // copy of the org list in case the org service is sorted in a
        // different manner by other parts of the code.
        this.org.sortTree(this.displayField);
        this.org.absorbTree();
        this.sortedOrgs = this.org.list();

        if (this.initialOrg || this.initialOrgId) {
            this.selected = this.formatForDisplay(
                this.initialOrg || this.org.get(this.initialOrgId)
            );

            this.markAsLoaded();
            return;
        }

        const promise = this.persistKey ?
            this.getFromSetting() : Promise.resolve(null);

        promise.then((startupOrgId: number) => {

            if (!startupOrgId) {

                if (this.fallbackOrgId) {
                    startupOrgId = this.fallbackOrgId;

                } else if (this.fallbackOrg) {
                    startupOrgId = this.org.get(this.fallbackOrg).id();

                } else if (this.applyDefault && this.auth.user()) {
                    startupOrgId = this.auth.user().ws_ou();
                }
            }

            let startupOrg;
            if (startupOrgId) {
                startupOrg = this.org.get(startupOrgId);
                this.selected = this.formatForDisplay(startupOrg);
            }

            this.markAsLoaded(startupOrg);
        });
    }

    getFromSetting(): Promise<number> {

        const key = `eg.orgselect.${this.persistKey}`;

        return this.serverStore.getItem(key).then(
            value => this.valueFromSetting = value
        );
    }

    // Indicate all load-time shuffling has completed.
    markAsLoaded(onChangeOrg?: IdlObject) {
        setTimeout(() => { // Avoid emitting mid-digest
            this.componentLoaded.emit();
            this.componentLoaded.complete();
            if (onChangeOrg) { this.onChange.emit(onChangeOrg); }
        });
    }

    //
    applyPermLimitOrgs(perms: string[]) {

        if (!perms) {
            return;
        }

        // handle lazy clients that pass null perm names
        perms = perms.filter(p => p !== null && p !== undefined);

        if (perms.length === 0) {
            return;
        }

        // NOTE: If permLimitOrgs is useful in a non-staff context
        // we need to change this to support non-staff perm checks.
        this.perm.hasWorkPermAt(perms, true).then(permMap => {
            this.permLimitOrgs =
                // safari-friendly version of Array.flat()
                Object.values(permMap).reduce((acc, val) => acc.concat(val), []);
        });
    }

    // Format for display in the selector drop-down and input.
    formatForDisplay(org: IdlObject): OrgDisplay {
        let label = org[this.displayField]();
        if (!this.readOnly) {
            label = PAD_SPACE.repeat(org.ou_type().depth()) + label;
        }
        return {
            id : org.id(),
            label : label,
            disabled : false
        };
    }

    // Fired by the typeahead to inform us of a change.
    // TODO: this does not fire when the value is cleared :( -- implement
    // change detection on this.selected to look specifically for NULL.
    orgChanged(selEvent: NgbTypeaheadSelectItemEvent) {
        // console.debug('org unit change occurred ' + selEvent.item);
        this.onChange.emit(this.org.get(selEvent.item.id));

        if (this.persistKey && this.valueFromSetting !== selEvent.item.id) {
            // persistKey is active.  Update the persisted value when changed.

            const key = `eg.orgselect.${this.persistKey}`;
            this.valueFromSetting = selEvent.item.id;
            this.serverStore.setItem(key, this.valueFromSetting);
        }
    }

    // Remove the tree-padding spaces when matching.
    formatter = (result: OrgDisplay) => result ? result.label.trim() : '';

    // reset the state of the component
    reset() {
        this.selected = null;
    }

    filter = (text$: Observable<string>): Observable<OrgDisplay[]> => {
        return text$.pipe(
            debounceTime(200),
            distinctUntilChanged(),
            merge(
                // Inject a specifier indicating the source of the
                // action is a user click
                this.click$.pipe(filter(() => !this.instance.isPopupOpen()))
                .pipe(mapTo('_CLICK_'))
            ),
            map(term => {

                let orgs = this.sortedOrgs.filter(org =>
                    this.hidden.filter(id => org.id() === id).length === 0
                );

                if (this.permLimitOrgs) {
                    // Avoid showing org units where the user does
                    // not have the requested permission.
                    orgs = orgs.filter(org =>
                        this.permLimitOrgs.includes(org.id()));
                }

                if (term !== '_CLICK_') {
                    // For search-driven events, limit to the matching
                    // org units.
                    orgs = orgs.filter(org => {
                        return term === '' || // show all
                            org[this.displayField]()
                                .toLowerCase().indexOf(term.toLowerCase()) > -1;

                    });
                }

                return orgs.map(org => this.formatForDisplay(org));
            })
        );
    }
}


