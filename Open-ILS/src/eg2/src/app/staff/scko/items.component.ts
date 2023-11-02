import {Component, OnInit, ViewEncapsulation} from '@angular/core';
import {Router, ActivatedRoute, NavigationEnd} from '@angular/router';
import {of, from} from 'rxjs';
import {switchMap, tap} from 'rxjs/operators';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NetService} from '@eg/core/net.service';
import {IdlObject} from '@eg/core/idl.service';
import {SckoService, ActionContext} from './scko.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {PrintService} from '@eg/share/print/print.service';

@Component({
  templateUrl: 'items.component.html'
})

export class SckoItemsComponent implements OnInit {

    circs: IdlObject[] = [];
    selected: {[id: number]: boolean} = {};

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private printer: PrintService,
        public  scko: SckoService
    ) {}

    ngOnInit() {

        if (!this.scko.patronSummary) {
            this.router.navigate(['/staff/selfcheck']);
            return;
        }

        this.scko.resetPatronTimeout();

        this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.checked_out.authoritative',
            this.auth.token(), this.scko.patronSummary.id).toPromise()

        .then(data => {
            const ids = data.out.concat(data.overdue).concat(data.long_overdue);
            return this.scko.getFleshedCircs(ids).pipe(tap(circ => {
                this.circs.push(circ);
                this.selected[circ.id()] = true;
            })).toPromise();
        });
    }

    printList() {

        const data = this.circs.map(c => {
            return {
                circ: c,
                copy: c.target_copy(),
                title: this.scko.getCircTitle(c),
                author: this.scko.getCircAuthor(c)
            };
        });

        this.printer.print({
            templateName: 'scko_items_out',
            contextData: {
                checkouts: data,
                user: this.scko.patronSummary.patron
            },
            printContext: 'default'
        });
    }

    toggleSelect() {
        const selectMe =
            Object.values(this.selected).filter(v => v).length < this.circs.length;
        Object.keys(this.selected).forEach(key => this.selected[key] = selectMe);
    }

    renewSelected() {

        const renewList = this.circs.filter(c => this.selected[c.id()]);
        if (renewList.length === 0) { return; }

        const contexts: ActionContext[] = [];

        from(renewList).pipe(switchMap(circ => {
            return of(
                this.scko.renew(circ.target_copy().barcode())
                .then(ctx => {
                    contexts.push(ctx);

                    if (!ctx.newCirc) { return; }

                    // Replace the renewed circ with the new circ.
                    const circs = [];
                    this.circs.forEach(c => {
                        if (c.id() === circ.id()) {
                            circs.push(ctx.newCirc);
                        } else {
                            circs.push(c);
                        }
                    });
                    this.circs = circs;
                })
            );
        })).toPromise().then(_ => {

            // Create one ActionContext to represent the batch for
            // notification purposes.  Avoid popups and audio on batch
            // renewals.

            const notifyCtx: ActionContext = {
                displayText: 'scko.batch_renew.result',
                renewSuccessCount: contexts.filter(c => c.newCirc).length,
                renewFailCount: contexts.filter(c => !c.newCirc).length
            };

            this.scko.notifyPatron(notifyCtx);
        });
    }
}



