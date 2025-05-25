import {Component, OnInit, AfterViewInit, Input, Output, EventEmitter} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {tap} from 'rxjs';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemService, BatchLineitemStruct} from './lineitem.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
    templateUrl: 'detail.component.html'
})
export class LineitemDetailComponent implements OnInit {

    lineitemId: number;
    lineitem: IdlObject;
    tab: string;

    constructor(
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService,
        private liService: LineitemService
    ) {}

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


