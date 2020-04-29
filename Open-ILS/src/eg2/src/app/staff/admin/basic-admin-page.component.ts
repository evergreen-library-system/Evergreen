import {Component, OnInit} from '@angular/core';
import {ActivatedRoute} from '@angular/router';
import {IdlService} from '@eg/core/idl.service';

/**
 * Generic IDL class editor page.
 */

@Component({
    template: `
      <eg-title i18n-prefix prefix="{{classLabel}} Administration">
      </eg-title>
      <eg-staff-banner bannerText="{{classLabel}} Configuration" i18n-bannerText>
      </eg-staff-banner>
      <eg-admin-page persistKeyPfx="{{persistKeyPfx}}" idlClass="{{idlClass}}"
        configLinkBasePath="{{configLinkBasePath}}"
        readonlyFields="{{readonlyFields}}"
        [disableOrgFilter]="disableOrgFilter"></eg-admin-page>
    `
})

export class BasicAdminPageComponent implements OnInit {

    idlClass: string;
    classLabel: string;
    persistKeyPfx: string;
    readonlyFields = '';
    configLinkBasePath = '/staff/admin';

    // Tell the admin page to disable and hide the automagic org unit filter
    disableOrgFilter: boolean;

    constructor(
        private route: ActivatedRoute,
        private idl: IdlService
    ) {
    }

    ngOnInit() {
        let schema = this.route.snapshot.paramMap.get('schema');
        if (!schema) {
            // Allow callers to pass the schema via static route data
            const data = this.route.snapshot.data[0];
            if (data) { schema = data.schema; }
        }
        let table = this.route.snapshot.paramMap.get('table');
        if (!table) {
            const data = this.route.snapshot.data[0];
            if (data) { table = data.table; }
        }
        const fullTable = schema + '.' + table;

        // Set the prefix to "server", "local", "workstation",
        // extracted from the URL path.
        // For admin pages that use none of these, avoid setting
        // the prefix because that will cause it to double-up.
        // e.g. eg.grid.acq.acq.cancel_reason
        this.persistKeyPfx = this.route.snapshot.parent.url[0].path;
        const selfPrefixers = ['acq', 'booking'];
        if (selfPrefixers.indexOf(this.persistKeyPfx) > -1) {
            // ACQ is a special case, because unlike 'server', 'local',
            // 'workstation', the schema ('acq') is the root of the path.
            this.persistKeyPfx = '';
        } else {
            this.configLinkBasePath += '/' + this.persistKeyPfx;
        }

        // Pass the readonlyFields param if available
        if (this.route.snapshot.data && this.route.snapshot.data[0]) {
            // snapshot.data is a HASH.
            const data = this.route.snapshot.data[0];

            if (data.readonlyFields) {
                this.readonlyFields = data.readonlyFields;
            }

            if (data.disableOrgFilter) {
                this.disableOrgFilter = true;
            }
        }

        Object.keys(this.idl.classes).forEach(class_ => {
            const classDef = this.idl.classes[class_];
            if (classDef.table === fullTable) {
                this.idlClass = class_;
                this.classLabel = classDef.label;
            }
        });

        if (!this.idlClass) {
            throw new Error('Unable to find IDL class for table ' + fullTable);
        }
    }
}


