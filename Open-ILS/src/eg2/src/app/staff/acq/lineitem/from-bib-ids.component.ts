import {Component, OnInit, Input, Output} from '@angular/core';
import {ActivatedRoute, Router, ParamMap} from '@angular/router';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemService} from './lineitem.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {ServerStoreService} from '@eg/core/server-store.service';

@Component({
    templateUrl: 'from-bib-ids.component.html',
    selector: 'eg-lineitem-from-bib-ids',
    styleUrls: ['./from-bib-ids.component.css']
})
export class LineitemFromBibIdsComponent implements OnInit {

    targetPicklist: number;
    targetPo: number;

    bibIdMap: object = {};

    // From the inline PL selector
    selectedPl: ComboboxEntry;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private idl: IdlService,
        private auth: AuthService,
        private net: NetService,
        private evt: EventService,
        private pcrud: PcrudService,
        private store: ServerStoreService,
        private liService: LineitemService
    ) { }

    ngOnInit() {

        this.route.parent.paramMap.subscribe((params: ParamMap) => {
            const pl = +params.get('picklistId');
            if (pl) {this.targetPicklist = pl;}
            const po = +params.get('poId');
            if (po) {this.targetPo = po;}
        });

    }

    bibIdMapKeys(): string[] {
        return Object.keys(this.bibIdMap).filter(k => Boolean(k));
    }

    save() {
        this.saveManualPicklist()
            .then(ok => { if (ok) { this.createLineitems(); } });
    }

    listIsEmpty(): boolean {
        let count = 0;
        this.bibIdMapKeys().forEach(k => count += this.bibIdMap[k].length);
        return !!(count === 0);
    }

    listFromMap(): number[] {
        let list = [];
        this.bibIdMapKeys().forEach(
            k => list = list.concat(this.bibIdMap[k].filter(v => !list.includes(v)))
        );

        return list;
    }

    canSave(): boolean {
        if (this.listIsEmpty()) {return false;}
        if (this.targetPo) {return true;}
        return !!(this.targetPicklist || this.selectedPl?.label);
    }

    saveManualPicklist(): Promise<boolean> {
        if (this.targetPo) { return Promise.resolve(true); }
        if (this.targetPicklist) { return Promise.resolve(true); }
        if (!this.selectedPl) { return Promise.resolve(false); }

        if (!this.selectedPl.freetext) {
            // An existing PL was selected
            this.targetPicklist = this.selectedPl.id;
            return Promise.resolve(true);
        }

        const pl = this.idl.create('acqpl');
        pl.name(this.selectedPl.label);
        pl.owner(this.auth.user().id());

        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.picklist.create', this.auth.token(), pl).toPromise()

            .then(plId => {
                const evt = this.evt.parse(plId);
                if (evt) { alert(evt); return false; }
                this.targetPicklist = plId;
                return true;
            });
    }

    removeFile(fname) {
        delete this.bibIdMap[fname];
    }

    fileSelected($event) {
        for (let ind = 0; ind < $event.target.files.length; ind++) {
            const f = $event.target.files[ind];
            if (f && f.name) {
                this.bibIdMap[f.name] = []; // keyed by file name, can replace currently loaded!
		        const reader = new FileReader();
        		reader.onloadend = (e) => {
                    this.bibIdMap[f.name] = (e.target.result as string). // text content
                        split('\n'). // split to lines
            	        filter(o => Boolean(o.length > 0)). // line isn't empty
        	            map(l => l.replace('\r','').split(',')[0]). // take first field
            	        filter(o => Boolean(o.length > 0)). // first field has content
                        map(o => o.match(/^".+"$/) ? o.slice(1,-1) : o). // remove quotes
                        filter(o => Boolean(o.match(/^\d+$/))). // and it's a number
                        filter((v,i,s) => s.indexOf(v) === i); // but just one instance of each value
                };
        		reader.readAsText(f);
            }
        }

        $event.target.value='';
    }

    createLineitems() {
        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.biblio.create_by_id',
            this.auth.token(),
            this.listFromMap(),
            { reuse_picklist: this.targetPicklist }
        ).subscribe(
            output => {
            	const evt = this.evt.parse(output);
	            if (evt) { throw(evt); return; }
            },
            (err: unknown) => alert(err),
            () => {
            	if (this.selectedPl) {
	                // catalog records were added to a picklist that is not
    	            // currently focused in the UI.  Jump to it.
        	        const url = `/staff/acq/picklist/${this.targetPicklist}`;
            	    this.router.navigate([url]);
	            } else {

    	            this.router.navigate(['../'], {
        	            relativeTo: this.route,
            	        queryParamsHandling: 'merge'
	                });
    	        }
        	}
        );
    }
}

