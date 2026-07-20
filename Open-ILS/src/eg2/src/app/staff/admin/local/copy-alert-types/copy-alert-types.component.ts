import { Component, OnInit, inject } from '@angular/core';
import { PcrudService } from '@eg/core/pcrud.service';
import { OrgService } from '@eg/core/org.service';
import { AuthService } from '@eg/core/auth.service';
import { ComboboxEntry } from '@eg/share/combobox/combobox.component';
import { IdlService, IdlObject } from '@eg/core/idl.service';
import { StaffCommonModule } from '@eg/staff/common.module';
import { AdminPageComponent } from '@eg/staff/share/admin-page/admin-page.component';
import { HoldingsService } from '@eg/staff/share/holdings/holdings.service';
import { firstValueFrom } from 'rxjs';

@Component({
    selector: 'eg-copy-alert-types',
    templateUrl: './copy-alert-types.component.html',
    imports: [AdminPageComponent, StaffCommonModule],
    providers: [HoldingsService]
})
export class CopyAlertTypesComponent implements OnInit {
    private auth = inject(AuthService);
    private idl = inject(IdlService);
    private org = inject(OrgService);
    private pcrud = inject(PcrudService);
    private holdings = inject(HoldingsService);

    copyStatuses: IdlObject[] = [];
    statusDisplayMap: { [id: number]: string } = {};
    alertTypeStateEntries: ComboboxEntry[] = [];
    defaultNewRecord: IdlObject;

    ngOnInit() {
        this.getAlertStatuses();
        this.getCopyStatuses();
        this.defaultNewRecord = this.idl.create('ccat');
        this.defaultNewRecord.in_renew(false);
        this.defaultNewRecord.next_status(null);
    }

    getAlertStatuses() {
        this.pcrud.search('ccat', {
            active : 't',
            scope_org: this.org.ancestors(this.auth.user().ws_ou(), true)
        }, {
            order_by: {ccat: ['event', 'id']}, // sort by event type (CHECKIN, CHECKOUT), then id
        },
        { atomic : true }).toPromise()
            .then(alertTypes => {
                this.alertTypeStateEntries = alertTypes.map(t => ({id: t.state(), label: t.name()}));
                console.debug('pcrud returned alert types: ', this.alertTypeStateEntries);
            })
            .catch(err => console.debug('pcrud returned error: ', err));
    }

    async getCopyStatuses() {
        const statuses: IdlObject[] = await firstValueFrom(
            this.pcrud.retrieveAll('ccs',
                { select: { ccs: ['id', 'name'] }},
                { atomic: true }
            )
        ).catch(err => console.debug('pcrud returned error: ', err));

        // "Magic" statuses are handled by circ workflows and shouldn't
        // be assigned arbitrarily, so don't include them as options
        // to be potentially selected for next_status.
        const magic = await this.holdings.getMagicCopyStatuses() ?? [];
        this.copyStatuses = (statuses ?? []).filter(
            status => !magic.includes(status.id())
        );

        // Map status names for easy lookup when displaying names.
        this.copyStatuses.forEach(status => {
            this.statusDisplayMap[status.id()] = status.name();
        });
    }

    getNextStatus(alertType: IdlObject): number[] {
        const next_status = alertType.next_status();
        if (!next_status) {
            return [];
        }
        // ATTN! next_status is stored as '{x,y,z}' (not JSON!)
        return JSON.parse(next_status.replace('{', '[').replace('}', ']'));
    }

    hasNextStatus(record, status_id) {
        const next_status = this.getNextStatus(record);
        return (next_status.length && next_status.includes(status_id));
    }

    recordNextStatus(alertType: IdlObject, event: Event): void {
        const checkbox = event?.target as HTMLInputElement;
        const statusId = Number(checkbox?.value);
        const current: number[] = this.getNextStatus(alertType);
        const nextStatus = checkbox?.checked
            ? current.includes(statusId)
                ? current
                : [...current, statusId]
            : current.filter(id => id !== statusId);
        // ATTN! next_status is stored as '{x,y,z}' (not JSON!)
        alertType.next_status(`{${ nextStatus.join(',') }}`);
    }

    displayNextStatus(alertType: IdlObject): string {
        return (this.getNextStatus(alertType))
            .filter(id => this.statusDisplayMap[id])
            .map(id => this.statusDisplayMap[id])
            .join(',');
    }
}
