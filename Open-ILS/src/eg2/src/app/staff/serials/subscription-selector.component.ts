import { CommonModule } from '@angular/common';
import { Component, Input, OnInit, Output, EventEmitter, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AuthService } from '@eg/core/auth.service';
import { FormatService } from '@eg/core/format.service';
import { IdlObject } from '@eg/core/idl.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { OrgFamily } from '@eg/share/org-family-select/org-family-select.component';
import { OrgFamilySelectModule } from '@eg/share/org-family-select/org-family-select.module';

interface SsubWhereClause {
    record_entry: any;
    owning_lib?: number[];
}

@Component({
    standalone: true,
    imports: [OrgFamilySelectModule, FormsModule, CommonModule],
    selector: 'eg-subscription-selector',
    templateUrl: './subscription-selector.component.html'
})
export class SubscriptionSelectorComponent implements OnInit {
    @Input() bibRecordId: number;
    @Output() subscriptionSelected = new EventEmitter<number>();
    selectedOrgUnits: OrgFamily;
    selectedSubscription: number;
    subscriptionList: {id: number, label: string}[];
    loaded = false;

    private auth: AuthService = inject(AuthService);
    private format: FormatService = inject(FormatService);
    private pcrud: PcrudService = inject(PcrudService);

    ngOnInit(): void {
        this.selectedOrgUnits = {primaryOrgId: this.auth.user().ws_ou(), includeDescendants: true};
    }

    findSubscriptions() {
        const newSubscriptions = [];
        this.pcrud.search('ssub', this.idlBaseQuery,
            {'flesh': 1, 'flesh_fields': {'ssub':['owning_lib']}})
            .subscribe({
                next: (result => {
                    newSubscriptions.push({id: result.id(), label: this.subscriptionLabel(result)});
                }),
                complete: () => {
                    this.subscriptionList = newSubscriptions;
                    if(this.subscriptionList?.length) {
                        this.selectedSubscription = this.subscriptionList[0].id;
                    }
                    this.loaded = true;
                }
            });
    }

    emitSelectedSubscription() {
        this.subscriptionSelected.emit(this.selectedSubscription);
    }

    private get idlBaseQuery(): SsubWhereClause {
        const query = {record_entry: this?.bibRecordId};
        if (this.selectedOrgUnits?.orgIds?.length) {
            query['owning_lib'] = this.selectedOrgUnits.orgIds;
        } else {
            query['owning_lib'] = [this.auth.user().ws_ou()];
        }
        return query;
    }

    private subscriptionLabel(subscription: IdlObject) {
        const startDate = this.format.transform({value: subscription.start_date(), datatype: 'timestamp'});
        const endDate = this.format.transform({value: subscription.end_date(), datatype: 'timestamp'});
        return $localize`Subscription ${subscription.id()} at ${subscription.owning_lib().shortname()} (${startDate}-${endDate})`;
    }
}
