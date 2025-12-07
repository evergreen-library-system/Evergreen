
import {Component, OnInit, Input, EventEmitter} from '@angular/core';
import {tap} from 'rxjs';
import {OrgService} from '@eg/core/org.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronSearchFieldSet} from '@eg/staff/share/patron/search.component';
import {ServerStoreService} from '@eg/core/server-store.service';

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
    selector: 'eg-patron-edit-toolbar',
    styles: [
        '.pointer-not-allowed:hover { cursor: not-allowed }'
    ]
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
        private store: ServerStoreService,
        private auth: AuthService,
        private patronService: PatronService
    ) {}

    ngOnInit() {
        // Check if suggested fields should be the default.
        // (cached by resolver)
        this.store.getItem('ui.patron.edit.default_suggested')
            .then(value => {
                if (value) {
                    this.changeFields(VisibilityLevel.SUGGESTED_FIELDS);
                }
            });

        // Emitted by our editor component.
        this.disableSaveStateChanged.subscribe(d => this.disableSave = d);
    }

    changeFields(v: VisibilityLevel) {
        this.visibilityLevel = v;
    }

    dupesFound(): DupeSearch[] {
        return Object.values(this.searches).filter(dupe => dupe.count > 0);
    }

    checkDupes(category: string, search: PatronSearchFieldSet): Promise<any> {

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.patron.search.advanced',
            this.auth.token(),
            search,
            1000, // limit
            null, // sort
            true  // as id
        ).pipe(tap(ids => {
            ids = ids.filter(id => Number(id) !== this.patronId);
            this.searches[category] = {
                category: category as SearchCategory,
                count: ids.length,
                search: search,
                json: JSON.stringify(search)
            };
        })).toPromise();
    }

    checkAddressAlerts(patron: IdlObject, addr: IdlObject) {
        const addrHash = this.idl.toHash(addr);
        if (patron.mailing_address()) {
            addrHash.mailing_address = addr.id() === patron.mailing_address().id();
        }
        if (patron.billing_address()) {
            addrHash.billing_address = addr.id() === patron.billing_address().id();
        }
        this.net.request(
            'open-ils.actor',
            'open-ils.actor.address_alert.test',
            this.auth.token(), this.auth.user().ws_ou(), addrHash
        ).subscribe(alerts => this.addressAlerts = alerts);
    }
}

