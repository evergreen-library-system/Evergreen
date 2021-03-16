import {Component, OnInit, Input} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';

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

    constructor(
        private org: OrgService,
        private net: NetService,
        private idl: IdlService,
        public patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {

        if (this.patronId) {
            this.patronService.getById(this.patronId, FLESH_PATRON_FIELDS)
            .then(patron => this.patron = patron);
        } else {
            this.createNewPatron();
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

    fieldValueChange(path: string, field: string, value: any) {
        this.changeHandlerNeeded = true;
        this.objectFromPath(path)[field](value);
    }

    fieldMaybeModified(path: string, field: string) {
        if (!this.changeHandlerNeeded) { return; } // no changes applied

        // TODO: set dirty = true

        this.changeHandlerNeeded = false;

        console.debug(`Modifying field path=${path} field=${field}`);

        // check stuff here..

        const obj = path ? this.patron[path]() : this.patron;
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

