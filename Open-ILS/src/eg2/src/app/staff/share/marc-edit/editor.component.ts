import {Component, Input, Output, OnInit, EventEmitter, ViewChild} from '@angular/core';
import {IdlService} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {StringComponent} from '@eg/share/string/string.component';
import {MarcRecord} from './marcrecord';
import {ComboboxEntry, ComboboxComponent
  } from '@eg/share/combobox/combobox.component';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {MarcEditContext} from './editor-context';
import {NgbTabset, NgbTabChangeEvent} from '@ng-bootstrap/ng-bootstrap';

interface MarcSavedEvent {
    marcXml: string;
    bibSource?: number;
}

/**
 * MARC Record editor main interface.
 */

@Component({
  selector: 'eg-marc-editor',
  templateUrl: './editor.component.html'
})

export class MarcEditorComponent implements OnInit {

    editorTab: 'rich' | 'flat';
    sources: ComboboxEntry[];
    context: MarcEditContext;

    @Input() recordType: 'biblio' | 'authority' = 'biblio';

    @Input() set recordId(id: number) {
        if (!id) { return; }
        if (this.record && this.record.id === id) { return; }
        this.fromId(id);
    }

    @Input() set recordXml(xml: string) {
        if (xml) {
            this.fromXml(xml);
        }
    }

    get record(): MarcRecord {
        return this.context.record;
    }

    // Tell us which record source to select by default.
    // Useful for new records and in-place editing from bare XML.
    @Input() recordSource: number;

    // If true, saving records to the database is assumed to
    // happen externally.  IOW, the record editor is just an
    // in-place MARC modification interface.
    @Input() inPlaceMode: boolean;

    // In inPlaceMode, this is emitted in lieu of saving the record
    // in th database.  When inPlaceMode is false, this is emitted after
    // the record is successfully saved.
    @Output() recordSaved: EventEmitter<MarcSavedEvent>;

    @ViewChild('sourceSelector', { static: true }) sourceSelector: ComboboxComponent;
    @ViewChild('confirmDelete', { static: true }) confirmDelete: ConfirmDialogComponent;
    @ViewChild('confirmUndelete', { static: true }) confirmUndelete: ConfirmDialogComponent;
    @ViewChild('cannotDelete', { static: true }) cannotDelete: ConfirmDialogComponent;
    @ViewChild('successMsg', { static: true }) successMsg: StringComponent;
    @ViewChild('failMsg', { static: true }) failMsg: StringComponent;

    constructor(
        private evt: EventService,
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService,
        private org: OrgService,
        private pcrud: PcrudService,
        private toast: ToastService,
        private store: ServerStoreService
    ) {
        this.sources = [];
        this.recordSaved = new EventEmitter<MarcSavedEvent>();
        this.context = new MarcEditContext();
    }

    ngOnInit() {

        this.context.recordType = this.recordType;

        this.store.getItem('cat.marcedit.flateditor').then(
            useFlat => this.editorTab = useFlat ? 'flat' : 'rich');

        this.pcrud.retrieveAll('cbs').subscribe(
            src => this.sources.push({id: +src.id(), label: src.source()}),
            _ => {},
            () => {
                this.sources = this.sources.sort((a, b) =>
                    a.label.toLowerCase() < b.label.toLowerCase() ? -1 : 1
                );

                if (this.recordSource) {
                    this.sourceSelector.applyEntryId(this.recordSource);
                }
            }
        );
    }

    // Remember the last used tab as the preferred tab.
    tabChange(evt: NgbTabChangeEvent) {

        // Avoid undo persistence across tabs since that could result
        // in changes getting lost.
        this.context.resetUndos();

        if (evt.nextId === 'flat') {
            this.store.setItem('cat.marcedit.flateditor', true);
        } else {
            this.store.removeItem('cat.marcedit.flateditor');
        }
    }

    saveRecord(): Promise<any> {
        const xml = this.record.toXml();

        let sourceName: string = null;
        let sourceId: number = null;

        if (this.sourceSelector.selected) {
            sourceName = this.sourceSelector.selected.label;
            sourceId = this.sourceSelector.selected.id;
        }

        if (this.inPlaceMode) {
            // Let the caller have the modified XML and move on.
            this.recordSaved.emit({marcXml: xml, bibSource: sourceId});
            return Promise.resolve();
        }

        if (this.record.id) { // Editing an existing record

            const method = 'open-ils.cat.biblio.record.xml.update';

            return this.net.request('open-ils.cat', method,
                this.auth.token(), this.record.id, xml, sourceName
            ).toPromise().then(response => {

                const evt = this.evt.parse(response);
                if (evt) {
                    console.error(evt);
                    this.failMsg.current().then(msg => this.toast.warning(msg));
                    return;
                }

                this.successMsg.current().then(msg => this.toast.success(msg));
                this.recordSaved.emit({marcXml: xml, bibSource: sourceId});
                return response;
            });

        } else {
            // TODO: create a new record
        }
    }

    fromId(id: number): Promise<any> {
        return this.pcrud.retrieve('bre', id)
        .toPromise().then(bib => {
            this.context.record = new MarcRecord(bib.marc());
            this.record.id = id;
            this.record.deleted = bib.deleted() === 't';
            if (bib.source()) {
                this.sourceSelector.applyEntryId(+bib.source());
            }
        });
    }

    fromXml(xml: string) {
        this.context.record = new MarcRecord(xml);
        this.record.id = null;
    }

    deleteRecord(): Promise<any> {

        return this.confirmDelete.open().toPromise()
        .then(yes => {
            if (!yes) { return; }

            return this.net.request('open-ils.cat',
                'open-ils.cat.biblio.record_entry.delete',
                this.auth.token(), this.record.id).toPromise()

            .then(resp => {

                const evt = this.evt.parse(resp);
                if (evt) {
                    if (evt.textcode === 'RECORD_NOT_EMPTY') {
                        return this.cannotDelete.open().toPromise();
                    } else {
                        console.error(evt);
                        return alert(evt);
                    }
                }
                return this.fromId(this.record.id)
                .then(_ => this.recordSaved.emit(
                    {marcXml: this.record.toXml()}));
            });
        });
    }

    undeleteRecord(): Promise<any> {

        return this.confirmUndelete.open().toPromise()
        .then(yes => {
            if (!yes) { return; }

            return this.net.request('open-ils.cat',
                'open-ils.cat.biblio.record_entry.undelete',
                this.auth.token(), this.record.id).toPromise()

            .then(resp => {

                const evt = this.evt.parse(resp);
                if (evt) { console.error(evt); return alert(evt); }

                return this.fromId(this.record.id)
                .then(_ => this.recordSaved.emit(
                    {marcXml: this.record.toXml()}));
            });
        });
    }
}

