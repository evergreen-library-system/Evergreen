// Some mock components for use in tests --
// Convenient if you are testing a parent component,
// but you don't want to have to re-implement all of
// the child's logic in your test

import { Component, Input } from '@angular/core';
import { ComboboxEntry } from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-combobox',
    template: ''
})
export class MockComboboxComponent {
    @Input() entries: ComboboxEntry[];
}

@Component({
    selector: 'eg-org-select',
    template: ''
})
export class MockOrgSelectComponent {
    @Input() disabled?: boolean;
    @Input() domId: string;
    @Input() limitPerms: string;
    @Input() ariaLabel?: string;
    @Input() disableOrgs: number[];
    @Input() required: boolean;

    @Input() applyOrgId(_id: number) {};
}
