import { Component, OnInit, Input, Output, OnChanges, SimpleChanges, EventEmitter, ViewChild } from '@angular/core';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import { ComboboxEntry, ComboboxComponent } from '@eg/share/combobox/combobox.component';

@Component({
    selector: 'eg-org-depth-selector',
    templateUrl: 'depth-select.component.html'
})
export class DepthSelectComponent implements OnInit, OnChanges {
    @Input() contextOrgId: number;
    @Input() disabled: boolean;
    @Output() depthChange = new EventEmitter<ComboboxEntry>();

    cbDepthEntry: ComboboxEntry;
    cbDepthEntries: ComboboxEntry[] = [];

    @ViewChild('depthBox') depthBox: ComboboxComponent;

    constructor(private org: OrgService, private auth: AuthService) {
        this.contextOrgId = this.auth.user().ws_ou(); // Default if not provided
    }

    ngOnInit() {
        this.loadDepthEntries();
    }

    ngOnChanges(changes: SimpleChanges) {
        if (changes.contextOrgId && !changes.contextOrgId.firstChange) {
            this.loadDepthEntries();  // Reload data when contextOrgId changes
        }
    }

    loadDepthEntries() {
        console.debug('DepthSelectComponent: setting up for org', this.contextOrgId);
        const contextOrg = this.org.get(this.contextOrgId);
        const ancestors = this.org.ancestors(this.contextOrgId);
        this.cbDepthEntries = ancestors.map(org => ({
            id: org.ou_type().depth(), label: org.ou_type().opac_label()
        })).reverse();
        this.cbDepthEntry = {
            id: contextOrg.ou_type().depth(), label: contextOrg.ou_type().opac_label()
        };
    }

    depthChanged(entry: ComboboxEntry) {
        this.depthChange.emit(entry);  // Emit the selected entry for external use
    }
}
