import {Component, OnInit, Input, Output, EventEmitter} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronSearchFieldSet} from '@eg/staff/share/patron/search.component';

export enum VisibilityLevel {
    ALL_FIELDS = 0,
    SUGGESTED_FIELDS = 1,
    REQUIRED_FIELDS = 2
}

type SearchCategory = 'name' | 'email' | 'phone' | 'ident' | 'address';

interface DupeSearch {
    category: SearchCategory;
    count: number;
    search: PatronSearchFieldSet;
    json: string;
}

@Component({
  templateUrl: 'edit-toolbar.component.html',
  selector: 'eg-patron-edit-toolbar'
})
export class EditToolbarComponent implements OnInit {

    @Input() patronId: number;

    disableSave = false;
    visibilityLevel: VisibilityLevel = VisibilityLevel.ALL_FIELDS;

    disableSaveStateChanged: EventEmitter<boolean> = new EventEmitter<boolean>();

    saveClicked: EventEmitter<void> = new EventEmitter<void>();
    saveCloneClicked: EventEmitter<void> = new EventEmitter<void>();
    printClicked: EventEmitter<void> = new EventEmitter<void>();

    searches: {[category: string]: DupeSearch} = {};
    addressAlerts: IdlObject[] = [];

    constructor(
        private org: OrgService,
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService,
        private patronService: PatronService
    ) {}

    ngOnInit() {
        // Emitted by our editor component.
        this.disableSaveStateChanged.subscribe(d => this.disableSave = d);
    }

    changeFields(v: VisibilityLevel) {
        this.visibilityLevel = v;
    }

    dupesFound(): DupeSearch[] {
        return Object.values(this.searches).filter(dupe => dupe.count > 0);
    }

    checkDupes(category: string, search: PatronSearchFieldSet) {

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.patron.search.advanced',
            this.auth.token(),
            search,
            1000, // limit
            null, // sort
            true  // as id
        ).subscribe(ids => {
            ids = ids.filter(id => Number(id) !== this.patronId);
            this.searches[category] = {
                category: category as SearchCategory,
                count: ids.length,
                search: search,
                json: JSON.stringify(search)
            };
        });
    }

    checkAddressAlerts(patron: IdlObject, addr: IdlObject) {
        const addrHash = this.idl.toHash(addr);
        console.log('CHECKING ADDR', addrHash);
        addrHash.mailing_address = addr.id() === patron.mailing_address().id();
        addrHash.billing_address = addr.id() === patron.billing_address().id();
        this.net.request(
            'open-ils.actor',
            'open-ils.actor.address_alert.test',
            this.auth.token(), this.auth.user().ws_ou(), addrHash
        ).subscribe(alerts => this.addressAlerts = alerts);
    }
}

