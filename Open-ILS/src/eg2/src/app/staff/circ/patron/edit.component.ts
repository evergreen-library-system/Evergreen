import {Component, OnInit, Input} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';

const COMMON_USER_SETTING_TYPES = [
  'circ.holds_behind_desk',
  'circ.collections.exempt',
  'opac.hold_notify',
  'opac.default_phone',
  'opac.default_pickup_location',
  'opac.default_sms_carrier',
  'opac.default_sms_notify'
];

const FLESH_PATRON_FIELDS = {
  flesh: 1,
  flesh_fields: {
    au: ['card', 'mailing_address', 'billing_address', 'addresses']
  }
};

@Component({
  templateUrl: 'edit.component.html',
  selector: 'eg-patron-edit',
  styleUrls: ['edit.component.css']
})
export class EditComponent implements OnInit {

    @Input() patronId: number;
    @Input() cloneId: number;
    @Input() stageUsername: string;

    patron: IdlObject;
    changeHandlerNeeded = false;
    nameTab = 'primary';
    loading = false;

    identTypes: ComboboxEntry[];
    userSettingTypes: {[name: string]: IdlObject} = {};
    optInSettingTypes: {[name: string]: IdlObject} = {};

    constructor(
        private org: OrgService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private idl: IdlService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {
        this.load();
    }

    load(): Promise<any> {
        this.loading = true;
        return this.loadPatron()
        .then(_ => this.setIdentTypes())
        .then(_ => this.setOptInSettings())
        .finally(() => this.loading = false);
    }

    setIdentTypes(): Promise<any> {
        return this.patronService.getIdentTypes()
        .then(types => {
            this.identTypes = types.map(t => ({id: t.id(), label: t.name()}));
        });
    }

    setOptInSettings(): Promise<any> {

        const orgIds = this.org.ancestors(this.auth.user().ws_ou(), true);

        const query = {
            '-or' : [
                {name : COMMON_USER_SETTING_TYPES},
                {name : { // opt-in notification user settings
                    'in': {
                        select : {atevdef : ['opt_in_setting']},
                        from : 'atevdef',
                        // we only care about opt-in settings for
                        // event_defs our users encounter
                        where : {'+atevdef' : {owner : orgIds}}
                    }
                }}
            ]
        };

        return this.pcrud.search('cust', query, {}, {atomic : true})
        .toPromise().then(types => {

            types.forEach(stype => {
                this.userSettingTypes[stype.name()] = stype;
                if (!COMMON_USER_SETTING_TYPES.includes(stype.name())) {
                    this.optInSettingTypes[stype.name()] = stype;
                }
            });
        });
    };


    loadPatron(): Promise<any> {
        if (this.patronId) {
            return this.patronService.getById(this.patronId, FLESH_PATRON_FIELDS)
            .then(patron => this.patron = patron);
        } else {
            return Promise.resolve(this.createNewPatron());
        }
    }

    createNewPatron() {
        const patron = this.idl.create('au');
        patron.isnew(true);

        const card = this.idl.create('ac');
        card.isnew(true);
        card.usr(-1);
        patron.card(card);

        this.patron = patron;
    }

    objectFromPath(path: string): IdlObject {
        return path ? this.patron[path]() : this.patron;
    }

    getFieldLabel(idlClass: string, field: string, override?: string): string {
        return override ? override :
            this.idl.classes[idlClass].field_map[field].label;
    }

    // With this, the 'cls' specifier is only needed in the template
    // when it's not 'au', which is the base/common class.
    getClass(cls: string): string {
        return cls || 'au';
    }

    getFieldValue(path: string, field: string): any {
        return this.objectFromPath(path)[field]();
    }

    fieldValueChange(path: string, field: string, value: any) {
        if (typeof value === 'boolean') { value = value ? 't' : 'f'; }

        this.changeHandlerNeeded = true;
        this.objectFromPath(path)[field](value);
    }

    fieldMaybeModified(path: string, field: string) {
        if (!this.changeHandlerNeeded) { return; } // no changes applied

        // TODO: set dirty = true

        this.changeHandlerNeeded = false;

        // check stuff here..

        const obj = path ? this.patron[path]() : this.patron;
        const value = obj[field]();

        console.debug(`Modifying field path=${path} field=${field} value=${value}`);
    }

    fieldRequired(idlClass: string, field: string): boolean {
        // TODO
        return false;
    }

    fieldPattern(idlClass: string, field: string): string {
        // TODO
        return null;
    }

    generatePassword() {
        this.fieldValueChange(null,
          'passwd', Math.floor(Math.random()*9000) + 1000);

        // Normally this is called on (blur), but the input is not
        // focused when using the generate button.
        this.fieldMaybeModified(null, 'passwd');
    }
}

