import {Component, Input, ViewChild, OnInit} from '@angular/core';
import {tap, concatMap} from 'rxjs';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {OrgService} from '@eg/core/org.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringComponent} from '@eg/share/string/string.component';
import {StringService} from '@eg/share/string/string.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
    templateUrl: './copy-loc-order.component.html',
    styleUrls: ['copy-loc-order.component.css']
})
export class CopyLocOrderComponent implements OnInit {

    @ViewChild('editString') editString: StringComponent;
    /*
    @ViewChild('errorString') errorString: StringComponent;
    @ViewChild('delConfirm') delConfirm: ConfirmDialogComponent;
    */

    locations: {[id: number]: IdlObject} = {};
    entries: IdlObject[] = [];
    contextOrg: number;
    selectedEntry: number;

    constructor(
        private idl: IdlService,
        private org: OrgService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private strings: StringService,
        private toast: ToastService
    ) {}

    ngOnInit() {
        this.contextOrg = Number(this.auth.user().ws_ou());
        this.load();
    }

    load(): Promise<any> {

        this.entries = [];
        this.locations = {};

        return this.pcrud.search('acpl',
            {owning_lib: this.org.ancestors(this.contextOrg, true)})
            .pipe(tap(loc => this.locations[loc.id()] = loc))
            .toPromise()

            .then(_ => {

                return this.pcrud.search('acplo',
                    {org: this.contextOrg},
                    {order_by: {acplo: 'position'}},
                    {authoritative: true}
                )
                    .pipe(tap(e => {
                        e.position(Number(e.position()));
                        e.location(this.locations[e.location()]);
                        this.entries.push(e);
                    }))
                    .toPromise();
            })

            .then(_ => {

                // Ensure we have an entry for every in-range copy location.

                const locs = Object.values(this.locations)
                    .sort((o1, o2) => o1.name() < o2.name() ? -1 : 1);

                let pos = this.entries.length;

                locs.forEach(loc => {
                    pos++;

                    let entry = this.entries.filter(e => e.location().id() === loc.id())[0];
                    if (entry) { return; }

                    // Either we have no entries or we encountered a new copy
                    // location added since the last time entries were saved.

                    entry = this.idl.create('acplo');
                    entry.isnew(true);
                    entry.id(-pos); // local temp ID
                    entry.location(loc);
                    entry.position(pos);
                    entry.org(this.contextOrg);
                    this.entries.push(entry);
                });
            });
    }

    orgChanged(org: IdlObject) {
        if (org && org.id() !== this.contextOrg) {
            this.contextOrg = org.id();
            this.load();
        }
    }

    orgSn(id: number): string {
        return this.org.get(id).shortname();
    }

    setPositions() {
        let pos = 1;
        this.entries.forEach(e => {
            if (e.position() !== pos) {
                e.ischanged(true);
                e.position(pos);
            }
            pos++;
        });
    }

    up(toTop?: boolean) {
        if (!this.selectedEntry) { return; }

        for (let idx = 0; idx < this.entries.length; idx++) {
            const entry = this.entries[idx];

            if (entry.id() === this.selectedEntry) {

                if (toTop) {
                    this.entries.splice(idx, 1);
                    this.entries.unshift(entry);

                } else {

                    if (idx === 0) {
                        // We're already at the top of the list.
                        // No where to go but down.
                        return;
                    }

                    // Swap places with the preceding entry
                    this.entries[idx] = this.entries[idx - 1];
                    this.entries[idx - 1] = entry;
                }

                break;
            }
        }

        this.setPositions();
    }

    down(toBottom?: boolean) {
        if (!this.selectedEntry) { return; }

        for (let idx = 0; idx < this.entries.length; idx++) {
            const entry = this.entries[idx];

            if (entry.id() === this.selectedEntry) {

                if (toBottom) {
                    this.entries.splice(idx, 1);
                    this.entries.push(entry);

                } else {

                    if (idx === this.entries.length - 1) {
                        // We're already at the bottom of the list.
                        // No where to go but up.
                        return;
                    }

                    this.entries[idx] = this.entries[idx + 1];
                    this.entries[idx + 1] = entry;
                }
                break;
            }
        }

        this.setPositions();
    }

    changesPending(): boolean {
        return this.entries.filter(e => (e.isnew() || e.ischanged())).length > 0;
    }

    selected(): IdlObject {
        return this.entries.filter(e => e.id() === this.selectedEntry)[0];
    }

    save() {
        // Scrub our temp ID's
        this.entries.forEach(e => { if (e.isnew()) { e.id(null); } });

        this.pcrud.autoApply(this.entries).toPromise()
            .then(_ => {
                this.selectedEntry = null;
                this.load().then(__ => this.toast.success(this.editString.text));
            });
    }
}


