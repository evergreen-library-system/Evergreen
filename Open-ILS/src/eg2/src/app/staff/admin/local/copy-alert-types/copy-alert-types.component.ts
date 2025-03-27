import { Component, OnInit } from '@angular/core';
import { PcrudService } from '@eg/core/pcrud.service';
import { OrgService } from '@eg/core/org.service';
import { AuthService } from '@eg/core/auth.service';
import { ComboboxEntry } from '@eg/share/combobox/combobox.component';
import { BasicAdminPageComponent } from '@eg/staff/admin/basic-admin-page.component';
import { IdlService, IdlObject } from '@eg/core/idl.service';

@Component({
  selector: 'eg-copy-alert-types',
  templateUrl: './copy-alert-types.component.html'
})
export class CopyAlertTypesComponent implements OnInit {

    copyStatuses: {};
    alertTypeStateEntries: ComboboxEntry[] = [];
    defaultNewRecord: IdlObject;

    constructor(
      private auth: AuthService,
      private idl: IdlService,
      private org: OrgService,
      private pcrud: PcrudService,
    ) {}

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

    getCopyStatuses() {
      this.pcrud.retrieveAll('ccs', { select: { ccs: ['id', 'name'] }}, {atomic: true})
          .toPromise().then(stats => {
              this.copyStatuses = stats;
              console.debug('pcrud returned copy statuses: ', this.copyStatuses);
      })
      .catch(err => console.debug('pcrud returned error: ', err));
    }

    getNextStatus(record) {
      const next_status = record.next_status();
      if (!next_status) {
        return null;
      }
      // ATTN! next_status is stored as '{x,y,z}' (not JSON!)
      return JSON.parse(next_status.replace('{', '[').replace('}', ']'));
    }

    hasNextStatus(record, status_id) {
      const next_status = this.getNextStatus(record);
      return (next_status && next_status.length && next_status.includes(status_id));
    }

    recordNextStatus(record) {
      // there should not be multiple inline copies of this component that would cause collisions,
      // but let's narrow it down to this record's fieldset to be safe
      const fieldset = document.getElementById(`next_status-${record.id()}`);
      const all_checked = fieldset?.querySelectorAll('input[name="next_status"]:checked') as NodeListOf<HTMLInputElement>;
      const all_values = Array.from(all_checked).map(checkbox => checkbox.value);
      console.debug('All checked values for next_status: ', `{${all_values.join(',')}}`);
      // ATTN! next_status is stored as '{x,y,z}' (not JSON!)
      record.next_status(`{${all_values.join(',')}}`);
    }
}
