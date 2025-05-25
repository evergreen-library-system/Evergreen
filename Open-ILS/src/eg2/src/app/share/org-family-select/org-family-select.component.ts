/* eslint-disable no-unused-expressions */
import {Component, EventEmitter, OnInit, Input, Output, ViewChildren, QueryList, forwardRef} from '@angular/core';
import {ControlValueAccessor, FormGroup, FormControl, NG_VALUE_ACCESSOR} from '@angular/forms';
import {AuthService} from '@eg/core/auth.service';
import {IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {OrgSelectComponent} from '@eg/share/org-select/org-select.component';
import {ServerStoreService} from '@eg/core/server-store.service';

export interface OrgFamily {
  primaryOrgId: number;
  includeAncestors?: boolean;
  includeDescendants?: boolean;
  orgIds?: number[];
}

@Component({
    selector: 'eg-org-family-select',
    templateUrl: 'org-family-select.component.html',
    providers: [
        {
            provide: NG_VALUE_ACCESSOR,
            useExisting: forwardRef(() => OrgFamilySelectComponent),
            multi: true
        }
    ]
})
export class OrgFamilySelectComponent implements ControlValueAccessor, OnInit {

    // ARIA label for selector. Required if there is no <label> in the markup.
    @Input() ariaLabel?: string;

    // Global "disabled" flag
    @Input() disabled = false;

    // The label for this input
    @Input() labelText = 'Library';

    // Should the Ancestors checkbox be hidden?
    @Input() hideAncestorSelector = false;

    // Should the Descendants checkbox be hidden?
    @Input() hideDescendantSelector = false;

    // Should the Ancestors checkbox be checked by default?
    //
    // Ignored if [hideAncestorSelector]="true"
    @Input() ancestorSelectorChecked = false;

    // Should the Descendants checkbox be checked by default?
    //
    // Ignored if [hideDescendantSelector]="true"
    @Input() descendantSelectorChecked = false;

    // Default org unit
    @Input() selectedOrgId: number;

    // Only show the OUs that the user has certain permissions at
    @Input() limitPerms: string[];

    @Input() domId: string;

    @Input() persistKey: string;

    // eslint-disable-next-line @angular-eslint/no-output-on-prefix
    @Output() onChange = new EventEmitter<any>();

    @ViewChildren(OrgSelectComponent)  orgSelects: QueryList<OrgSelectComponent>;

    // this is the most up-to-date value used for ngModel and reactive form
    // subscriptions
    options: OrgFamily;

    orgOnChange: ($event: IdlObject) => void;
    emitArray: () => void;

    familySelectors: FormGroup;

    propagateChange = (_: OrgFamily) => {};
    propagateTouch = () => {};

    constructor(
        private auth: AuthService,
        private org: OrgService,
        private serverStore: ServerStoreService
    ) {
    }

    ngOnInit() {
        if (this.selectedOrgId) {
            this.options = {primaryOrgId: this.selectedOrgId};
        } else if (this.auth.user()) {
            this.options = {primaryOrgId: this.auth.user().ws_ou()};
        }

        this.familySelectors = new FormGroup({
            'includeAncestors': new FormControl({
                value: this.ancestorSelectorChecked,
                disabled: this.disableAncestorSelector()}),
            'includeDescendants': new FormControl({
                value: this.descendantSelectorChecked,
                disabled: this.disableDescendantSelector()}),
        });

        if (!this.domId) {
            // eslint-disable-next-line no-magic-numbers
            this.domId = 'org-family-select-' + Math.floor(Math.random() * 100000);
        }

        this.familySelectors.valueChanges.subscribe(val => {
            this.emitArray();
        });

        this.orgOnChange = ($event: IdlObject) => {
            this.options.primaryOrgId = $event?.id();
            this.disableAncestorSelector() ? this.includeAncestors.disable() : this.includeAncestors.enable();
            this.disableDescendantSelector() ? this.includeDescendants.disable() : this.includeDescendants.enable();
            this.emitArray();
        };

        this.emitArray = () => {
            // Prepare and emit an array containing the primary org id and
            // optionally ancestor and descendant org units, and flags that select those.

            this.options.orgIds = [this.options.primaryOrgId];
            this.options.includeAncestors = this.includeAncestors.value;
            this.options.includeDescendants = this.includeDescendants.value;

            if (this.includeAncestors.value) {
                this.options.orgIds = this.org.ancestors(this.options.primaryOrgId, true);
            }

            if (this.includeDescendants.value) {
                this.options.orgIds = this.options.orgIds.concat(
                    this.org.descendants(this.options.primaryOrgId, true));
            }

            // Using ancestors() and descendants() can result in
            // duplicate org ID's.  Be nice and uniqify.
            const hash: any = {};
            this.options.orgIds.forEach(id => hash[id] = true);
            this.options.orgIds = Object.keys(hash).map(id => Number(id));

            this.propagateChange(this.options);
            this.onChange.emit(this.options);

            if (this.persistKey) {
                const key = `eg.orgfamilyselect.${this.persistKey}`;
                this.serverStore.setItem(key, this.options);
            }
        };

        this.loadPersistedValues();
    }

    private loadPersistedValues() {
        if (!this.persistKey) {return;}

        const key = `eg.orgfamilyselect.${this.persistKey}`;

        this.serverStore.getItem(key).then(persistedOptions => {
            if (persistedOptions) {
                this.writeValue(persistedOptions);
            }
        });
    }

    writeValue(value: OrgFamily) {
        if (value) {
            this.selectedOrgId = value['primaryOrgId'];
            if (this.orgSelects) {
                this.orgSelects.toArray()[0].applyOrgId = this.selectedOrgId;
                this.options = {primaryOrgId: this.selectedOrgId};
            }
            this.familySelectors.patchValue({
                'includeAncestors': value['includeAncestors'] ? value['includeAncestors'] : false,
                'includeDescendants': value['includeDescendants'] ? value['includeDescendants'] : false,
            });
        }
    }

    registerOnChange(fn) {
        this.propagateChange = fn;
    }

    registerOnTouched(fn) {
        this.propagateTouch = fn;
    }

    disableAncestorSelector(): boolean {
        return this.disabled || this.options.primaryOrgId === this.org.root().id();
    }

    disableDescendantSelector(): boolean {
        const contextOrg = this.org.get(this.options.primaryOrgId);
        return this.disabled || (contextOrg ? contextOrg.children().length === 0 : true);
    }

    get includeAncestors() {
        return this.familySelectors.get('includeAncestors');
    }
    get includeDescendants() {
        return this.familySelectors.get('includeDescendants');
    }

}

