import {Component, OnInit, AfterViewInit} from '@angular/core';
import {Observable} from 'rxjs';
import {map, take} from 'rxjs/operators';
import {ActivatedRoute, ParamMap} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {PrintService} from '@eg/share/print/print.service';
import {BroadcastService} from '@eg/share/util/broadcast.service';
import {PoService} from './po.service';

@Component({
  templateUrl: 'print.component.html'
})
export class PrintComponent implements OnInit, AfterViewInit {

    poId: number;
    outlet: Element;
    po: IdlObject;
    printing: boolean;
    closing: boolean;
    initDone = false;

    constructor(
        private route: ActivatedRoute,
        private idl: IdlService,
        private org: OrgService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private poService: PoService,
        private broadcaster: BroadcastService,
        private printer: PrintService) {
    }

    ngOnInit() {
        this.route.parent.paramMap.subscribe((params: ParamMap) => {
            const poId = +params.get('poId');
            if (poId !== this.poId) {
                this.poId = poId;
                if (poId && this.initDone) { this.load(); }
            }
        });

        this.load();
    }

    ngAfterViewInit() {
        this.outlet = document.getElementById('print-outlet');
    }

    load() {
        if (!this.poId) { return; }

        this.po = null;
        this.poService.getFleshedPo(this.poId, {
            flesh_provider_addresses: true,
            flesh_lineitems: true,
            flesh_lineitem_attrs: true,
            flesh_lineitem_notes: true,
            flesh_lineitem_details: true,
            clear_marc: true,
            flesh_notes: true
        }, true)
        .then(po => this.po = po)
        .then(_ => this.populatePreview())
        .then(_ => this.initDone = true);
    }

    populatePreview(): Promise<any> {

        return this.printer.compileRemoteTemplate({
            templateName: 'purchase_order',
            printContext: 'default',
            contextData: {po: this.po}

        }).then(response => {
            this.outlet.innerHTML = response.content;
        });
    }

    addLiPrintNotes(): Promise<any> {

        const notes = [];
        this.po.lineitems().forEach(li => {
            const note = this.idl.create('acqlin');
            note.isnew(true);
            note.lineitem(li.id());
            note.value('printed: ' + this.auth.user().usrname());
            notes.push(note);
        });

        return this.net.request('open-ils.acq',
            'open-ils.acq.lineitem_note.cud.batch', this.auth.token(), notes)
        .toPromise().then(_ => {
            this.broadcaster.broadcast(
                'eg.acq.lineitem.notes.update', {
                lineitems: notes.map(n => Number(n.lineitem()))
            });
        });
    }

    printPo(closeTab?: boolean) {
        this.addLiPrintNotes().then(_ => this.printPo2(closeTab));
    }

    printPo2(closeTab?: boolean) {
        if (closeTab || this.closing) {
            const sub: any = this.printer.printJobQueued$.subscribe(req => {
                if (req.templateName === 'purchase_order') {
                    setTimeout(() => {
                        window.close();
                        sub.unsubscribe();
                    }, 2000); // allow for a time cushion past queueing.
                }
            });
        }

        this.printer.print({
            templateName: 'purchase_order',
            printContext: 'default',
            contextData: {po: this.po}
        });
    }
}

