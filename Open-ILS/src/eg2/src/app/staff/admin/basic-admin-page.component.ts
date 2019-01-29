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
      <eg-admin-page persistKeyPfx="{{persistKeyPfx}}" idlClass="{{idlClass}}"></eg-admin-page>
    `
})

export class BasicAdminPageComponent implements OnInit {

    idlClass: string;
    classLabel: string;
    persistKeyPfx: string;

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
        const table = schema + '.' + this.route.snapshot.paramMap.get('table');

        // Set the prefix to "server", "local", "workstation",
        // extracted from the URL path.
        this.persistKeyPfx = this.route.snapshot.parent.url[0].path;
        if (this.persistKeyPfx === 'acq') {
            // ACQ is a special case, becaus unlike 'server', 'local',
            // 'workstation', the schema ('acq') is the root of the path.
            this.persistKeyPfx = '';
        }

        Object.keys(this.idl.classes).forEach(class_ => {
            const classDef = this.idl.classes[class_];
            if (classDef.table === table) {
                this.idlClass = class_;
                this.classLabel = classDef.label;
            }
        });

        if (!this.idlClass) {
            throw new Error('Unable to find IDL class for table ' + table);
        }
    }
}


