import { Component, OnInit, inject } from '@angular/core';
import {ActivatedRoute, ParamMap} from '@angular/router';
import {tap} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {LineitemService} from './lineitem.service';
import { CommonModule } from '@angular/common';
import { NgbNavModule } from '@ng-bootstrap/ng-bootstrap';
import { MarcHtmlComponent } from '@eg/share/catalog/marc-html.component';
import { MarcEditorComponent } from '@eg/staff/share/marc-edit/editor.component';

@Component({
    templateUrl: 'detail.component.html',
    imports: [
        CommonModule,
        MarcEditorComponent,
        MarcHtmlComponent,
        NgbNavModule,
    ]
})
export class LineitemDetailComponent implements OnInit {
    private route = inject(ActivatedRoute);
    private liService = inject(LineitemService);


    lineitemId: number;
    lineitem: IdlObject;
    tab: string;

    ngOnInit() {

        this.route.paramMap.subscribe((params: ParamMap) => {
            const id = +params.get('lineitemId');
            if (id !== this.lineitemId) {
                this.lineitemId = id;
                if (id) { this.load(); }
            }
        });

        this.liService.getLiAttrDefs();
    }

    load() {
        this.lineitem = null;
        // Avoid pulling from cache since li's do not have marc()
        // fleshed by default.
        return this.liService.getFleshedLineitems([this.lineitemId], {
            toCache: true, // OK to cache with marc()
            fleshMore: {clear_marc: false}
        }).pipe(tap(liStruct => this.lineitem = liStruct.lineitem)).toPromise();
    }

    attrLabel(attr: IdlObject): string {
        if (!this.liService.liAttrDefs) { return; }

        const def = this.liService.liAttrDefs.filter(
            d => d.id() === attr.definition())[0];

        return def ? def.description() : '';
    }

    saveMarcChanges(changes) { // MarcSavedEvent
        const xml = changes.marcXml;
        this.lineitem.marc(xml);
        this.liService.updateLineitems([this.lineitem]).toPromise()
            .then(_ => this.load());
    }
}


