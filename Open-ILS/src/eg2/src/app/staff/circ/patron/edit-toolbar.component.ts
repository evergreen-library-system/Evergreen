import {Component, OnInit, Input, Output, EventEmitter} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PatronContextService} from './patron.service';
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

    dupeSearches: DupeSearch[] = [];

    constructor(
        private org: OrgService,
        private net: NetService,
        private auth: AuthService,
        private patronService: PatronService,
        public context: PatronContextService
    ) {}

    ngOnInit() {
        // Emitted by our editor component.
        this.disableSaveStateChanged.subscribe(d => this.disableSave = d);
    }

    changeFields(v: VisibilityLevel) {
        this.visibilityLevel = v;
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
            const count = ids.length;

            if (count > 0) {
                const existing =
                    this.dupeSearches.filter(s => s.category === category)[0];
                if (existing) {
                    existing.search = search;
                    existing.count = count;
                } else {
                    this.dupeSearches.push({
                        category: category as SearchCategory,
                        search: search,
                        count: count
                    });
                }
            } else {
                this.dupeSearches =
                    this.dupeSearches.filter(s => s.category !== category);
            }
        });
    }
}

