import { Component } from '@angular/core';
import { StoreService } from '@eg/core/store.service';
import { ServerStoreService } from '@eg/core/server-store.service';
import { NetService } from '@eg/core/net.service';
import { lastValueFrom } from 'rxjs';
import { MarcRecord } from '@eg/staff/share/marc-edit/marcrecord';
import { MarcEditorComponent } from '@eg/staff/share/marc-edit/editor.component';

@Component({
    selector: 'eg-create-marc',
    templateUrl: './create-marc.component.html'
})
export class CreateMarcComponent {
    have_template = false;
    template_list = [];
    template_name = '';
    default_template_name = '';
    new_bib_id = 0;
    marc_template = '';
    record: MarcRecord;
    marc_xml: string;

    constructor(
    private net: NetService,
    private serverStore: ServerStoreService,
    private localStore: StoreService
    ) {
        this.getDefaultTemplateName();
        this.getTemplateTypes();
    }

    getDefaultTemplateName() {
        this.serverStore.getItem('cat.default_bib_marc_template').then(template => {
            this.default_template_name = template;
            // console.debug('Default template received:', this.default_template_name);
        }).then(() => {
            this.getLastBibTemplate();
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

    getLastBibTemplate() {
        this.template_name = this.localStore.getLocalItem('eg.cat.last_bib_marc_template');
        if (!this.template_name) {
            this.template_name = this.default_template_name;
            this.localStore.setLocalItem('eg.cat.last_bib_marc_template', this.template_name);
        }
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
                    this.localStore.setLocalItem('eg.cat.last_bib_marc_template', this.template_name);
                }
            });
        }
    }

    setDefaultTemplate() {
        if (this.template_name) {
            this.serverStore.setItem('cat.default_bib_marc_template', this.template_name);
        } else {
            this.serverStore.removeItem('cat.default_bib_marc_template');
        }
    }

    trackByTemplateName(index, template) {
        return template;
    }

}
