import { Component, inject, OnInit, ViewChild } from '@angular/core';
import { StoreService } from '@eg/core/store.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import { NetService } from '@eg/core/net.service';
import { lastValueFrom } from 'rxjs';
import { MarcRecord } from '@eg/staff/share/marc-edit/marcrecord';
import { MarcEditorComponent, MarcSavedEvent } from '@eg/staff/share/marc-edit/editor.component';
import { StaffBannerComponent } from '../share/staff-banner.component';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { FastAddSelectorComponent } from '../share/marc-edit/fast-add-selector.component';
import { HoldingsService } from '../share/holdings/holdings.service';
import { AuthService } from '@eg/core/auth.service';

@Component({
    selector: 'eg-create-marc',
    templateUrl: './create-marc.component.html',
    standalone: true,
    imports: [
        StaffBannerComponent, 
        FormsModule, 
        MarcEditorComponent,
        FastAddSelectorComponent
    ]
})
export class CreateMarcComponent implements OnInit{
    private net = inject(NetService);
    private serverStore = inject(ServerStoreService);
    private localStore = inject(StoreService);
    private router = inject(Router);
    private holdings = inject(HoldingsService);
    private auth = inject(AuthService);

    protected recordSource: string = ''
    protected fastAddChecked: boolean = true;
    have_template = false;
    template_list = [];
    template_name = '';
    default_template_name = '';
    new_bib_id = 0;
    marc_template = '';
    record: MarcRecord;
    marc_xml: string;
    
    @ViewChild('fastAdd') fastAdd!: FastAddSelectorComponent;

    constructor( 
    ) {
        this.getDefaultTemplateName();
        this.getTemplateTypes();
    }

    ngOnInit(): void {
        this.recordSource = this.localStore.getLocalItem('eg.cat.last_record_source');
        this.fastAddChecked = Boolean(this.localStore.getLocalItem('eg.cat.fast_add_item') ?? true);
    }

    getDefaultTemplateName() {
        this.serverStore.getItem('cat.default_bib_marc_template').then(template => {
            this.default_template_name = template || '';
            this.template_name = this.default_template_name;
        });
    }

    getTemplateTypes() {
        lastValueFrom(this.net.request(
            'open-ils.cat',
            'open-ils.cat.marc_template.types.retrieve'
        )).then(types => {
            this.template_list = types.sort();
        });
    }

    loadTemplate() {
        if (this.template_name) {
            lastValueFrom(this.net.request(
                'open-ils.cat',
                'open-ils.cat.biblio.marc_template.retrieve',
                this.template_name
            )).then(template_xml => {
                this.record = new MarcRecord(template_xml);
                // same logic as staff/share/marc-edit/editor-context.ts insertReplace008(),
                // without the undo/redo tracking:

                // regenerate 008, changing the date to now() and preserving everything else
                const field = this.record.newField({
                    tag : '008', data : this.record.generate008()});
                
                // delete all of the old 008s that were in the template
                [].concat(this.record.field('008', true)).forEach(f => {
                    this.record.deleteFields(f);
                });
                
                // insert the newly generated 008 into the new record
                this.record.insertOrderedFields(field);

                // convert new record to XML string for loading into the editor in the HTML
                this.marc_template = this.record.toXml();

                if (this.marc_template) {
                    this.have_template = true;
                }
            });
        }
    }

    setDefaultTemplate() {
        this.default_template_name = this.template_name;
        if (this.template_name) {
            this.serverStore.setItem('cat.default_bib_marc_template', this.template_name);
        } else {
            this.serverStore.removeItem('cat.default_bib_marc_template');
        }
    }

    trackByTemplateName(index, template) {
        return template;
    }

    onRecordSaved(event: MarcSavedEvent) {
        // The editor ain't gonna do it because the item ain't valid. But we're doing it here because the box is ticked at all.
        if (this.fastAdd.showFields && !event.fastItem && event.recordId) {
            this.holdings.spawnAddHoldingsUi(event.recordId, undefined, [{owner: this.auth.user().ws_ou()}]);
        }
        // And we don't need to add a version with a defined fastItem, because the marc-edit-component is doing that for us.

        if (event.recordId) {
            this.router.navigate(['staff', 'catalog', 'record', event.recordId, 'marc_edit'], {relativeTo: null});
        }
    }

    onRecordSourceChanged(id: number) {
        this.localStore.setLocalItem("eg.cat.last_record_source", id);
    }

}
