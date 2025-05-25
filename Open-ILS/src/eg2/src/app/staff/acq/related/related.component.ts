import {Component, OnInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {tap} from 'rxjs';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {PromptDialogComponent} from '@eg/share/dialog/prompt.component';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
    templateUrl: 'related.component.html'
})
export class RelatedComponent implements OnInit {

    recordId: number;
    addingToPl = false;
    addingToPo = false;
    selectedPl: ComboboxEntry;
    selectedPo: ComboboxEntry;

    @ViewChild('newPlDialog') newPlDialog: PromptDialogComponent;
    @ViewChild('plNameExists') plNameExists: AlertDialogComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private idl: IdlService,
        private evt: EventService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService
    ) {}

    ngOnInit() {
        this.route.paramMap.subscribe((params: ParamMap) => {
            this.recordId = +params.get('recordId');
        });
    }

    isBasePage(): boolean {
        return !this.route.firstChild ||
            this.route.firstChild.snapshot.url.length === 0;
    }

    // Create a new selection list
    // Create and add the lineitem.
    // Navigate to the new SL
    createPicklist() {

        this.newPlDialog.open().toPromise()
            .then(name => {
                if (!name) { return; }

                return this.pcrud.search('acqpl',
                    {owner: this.auth.user().id(), name: name}, null, {idlist: true}
                ).toPromise().then(existing => {
                    return {existing: existing, name: name};
                });

            }).then(info => {
                if (!info) { return; }

                if (info.existing) {
                // Alert the user the requested name is already in
                // use and reopen the create dialog.
                    this.plNameExists.open().toPromise().then(_ => this.createPicklist());
                    return;
                }

                const pl = this.idl.create('acqpl');
                pl.name(info.name);
                pl.owner(this.auth.user().id());

                return this.net.request(
                    'open-ils.acq',
                    'open-ils.acq.picklist.create', this.auth.token(), pl
                ).toPromise();

            }).then(plId => {
                if (!plId) { return; }

                const evt = this.evt.parse(plId);
                if (evt) { alert(evt); return; }

                this.addToPicklist(plId);
            });
    }

    createLineitem(options?: any): Promise<IdlObject> {

        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.biblio.create_by_id',
            this.auth.token(), [this.recordId], options

        ).pipe(tap(resp => {

            if (Number(resp) > 0) {
                // The API first responds with the picklist ID.
                // Avoid navigating away from this page until the API
                // completes and we know the lineitem has been created.
                return;
            }

            const evt = this.evt.parse(resp);
            if (evt) {
                alert(evt);

            } else {
                return resp;
            }

        })).toPromise();
    }

    // Add a lineitem based on our bib record to the selected
    // picklist by ID then navigate to that picklist's page.
    addToPicklist(plId: number) {
        if (!plId) { return; }

        this.createLineitem({reuse_picklist: plId})
            .then(li => {
                if (li) {
                    this.router.navigate(['/staff/acq/picklist', plId]);
                }
            });
    }

    // Create the lineitem, then send the user to the new PO UI.
    createPo() {
        this.createLineitem().then(li => {
            if (li) {
                this.router.navigate(
                    ['/staff/acq/po/create'], {queryParams: {li: li.id()}});
            }
        });
    }

    addToPo(poId: number) {
        if (!poId) { return; }

        this.createLineitem().then(li => {
            if (!li) { return null; }

            return this.net.request(
                'open-ils.acq',
                'open-ils.acq.purchase_order.add_lineitem',
                this.auth.token(), poId, li.id()

            ).toPromise();

        }).then(resp => {
            if (!resp) { return; }
            const evt = this.evt.parse(resp);
            if (evt) {
                alert(evt);
            } else {
                this.router.navigate(['/staff/acq/po/', poId]);
            }
        });
    }
}

