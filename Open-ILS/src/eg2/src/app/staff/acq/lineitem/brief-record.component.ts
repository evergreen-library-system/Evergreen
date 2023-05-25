import {Component, OnInit, OnDestroy, ViewChild} from '@angular/core';
import {ActivatedRoute, Router, ParamMap} from '@angular/router';
import {firstValueFrom, Observable, of} from 'rxjs';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemService} from './lineitem.service';
import {ComboboxComponent, ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {Subscription} from 'rxjs';
import {ServerStoreService} from '@eg/core/server-store.service';

const MARC_NS = 'http://www.loc.gov/MARC21/slim';

const MARC_XML_BASE = `
<record xmlns="${MARC_NS}">
    <leader>00000nam a22000007a 4500</leader>
    <controlfield tag="008">                                        </controlfield>
</record>
`;

@Component({
    templateUrl: 'brief-record.component.html',
    selector: 'eg-lineitem-brief-record'
})
export class BriefRecordComponent implements OnInit, OnDestroy {

    @ViewChild('MARCTemplateSelector', { static: true }) MARCTemplateSelector: ComboboxComponent;

    targetPicklist: number;
    targetPo: number;
    targetSub: Subscription;

    attrs: IdlObject[] = [];
    values: {[attr: string]: string} = {};

    // From the inline PL selector
    selectedPl: ComboboxEntry;
    selectedPo: ComboboxEntry;
    MARCTemplateList: ComboboxEntry[] = [];
    selectedMARCTemplate: ComboboxEntry = {
        id: '__blank__',
        label: $localize`Blank Record`,
        userdata: of(MARC_XML_BASE)
    };

    isSaving = false;

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

        this.targetSub =
        this.route.parent.paramMap.subscribe((params: ParamMap) => {
            this.targetPicklist = +params.get('picklistId');
            this.targetPo = +params.get('poId');
        });

        this.pcrud.retrieveAll('acqlimad')
            .subscribe(attr => this.attrs.push(attr));

        this.net.request(
            'open-ils.cat',
            'open-ils.cat.marc_template.types.retrieve'
        ).subscribe(name_list => {
            this.MARCTemplateList = [this.selectedMARCTemplate].concat(
                name_list.sort().map(
                    n => {return {id:n, label:n};}
                )
            );

            this.MARCTemplateList.forEach(t => {
                if (!t.userdata) {
                    t.userdata = this.net.request(
                        'open-ils.cat',
                        'open-ils.cat.biblio.marc_template.retrieve',
                        t.id
                    );
                }
            });

            this.store.getItem('acq.default_bib_marc_template').then(v => {
                const defaultTemplate = this.MARCTemplateList.find(t => t.id == v);
                if (defaultTemplate) {
                    this.MARCTemplateSelector.selectedId = defaultTemplate.id;
                    this.selectedMARCTemplate = defaultTemplate;
                }
            });
        });
    }

    ngOnDestroy(): void {
        this.targetSub.unsubscribe();
    }

    compile(): Promise<string> {

        function makeArrayFromElementList(list) {
            const output = [];
            for (let i = 0; i < list.length; i++) {
                output.push(list[i]);
            }
            return output;
        }

        function replaceMARCXMLField(record, new_field) {
            const field_list = makeArrayFromElementList(record.getElementsByTagName(new_field.localName));

            if (field_list.length == 0) {
                return null;
            }

            const new_tag = new_field.getAttribute('tag');
            const existing = makeArrayFromElementList(
                field_list.filter(f => f.getAttribute('tag') == new_tag)
            );

            // we only let one remain
            const target_field = existing.shift();
            existing.forEach(f => record.removeChild(f));

            if (!target_field) {
                return null;
            }

            if (new_field.localName === 'controlfield') {
                return record.replaceChild(new_field, target_field);
            }

            const target_subfields = makeArrayFromElementList(target_field.getElementsByTagName('subfield'));
            const unused_target_subfields = target_subfields.filter( sf => !sf.textContent && new_field.querySelectorAll(`[code="${sf.getAttribute('code')}"]`).length == 0);

            unused_target_subfields.forEach(sf => target_field.removeChild(sf));

            // for each new subfield, replace the first existing one if it's there, or add it to the end if not
            makeArrayFromElementList(new_field.getElementsByTagName('subfield')).forEach(new_sf => {
                const existing_first_sf = target_field.querySelector(`[code="${new_sf.getAttribute('code')}"]`);
                if (existing_first_sf) {
                    target_field.replaceChild(new_sf, existing_first_sf);
                } else {
                    target_field.appendChild(new_sf);
                }
            });

            return target_field;
        }

        function stripEmptyMARCXMLFields(record) {
            makeArrayFromElementList(record.getElementsByTagName('controlfield')).concat(
                makeArrayFromElementList(record.getElementsByTagName('datafield'))
            ).forEach(f => {
                if (f.localName == 'controlfield' && !f.textContent) {
                    record.removeChild(f);
                } else if (f.localName == 'datafield') {
                    const sf = makeArrayFromElementList(f.getElementsByTagName('subfield'));
                    const empty_sf = sf.filter(s => !s.textContent);
                    if (sf.length == empty_sf.length) { // delete the whole field
                        record.removeChild(f);
                    } else { // delete just the empty ones
                        empty_sf.forEach(s => f.removeChild(s));
                    }
                }
            });
        }

        function insertOrderedMARCXMLField(record, new_field) {
            const ldr = record.getElementsByTagName('leader')[0];
            const field_list = makeArrayFromElementList(record.getElementsByTagName('controlfield')).concat(
                makeArrayFromElementList(record.getElementsByTagName('datafield'))
            );

            if (field_list.length == 0) {
                return ldr.after(new_field);
            }

            const new_tag = new_field.getAttribute('tag');
            const target_field = field_list.filter(f => f.getAttribute('tag') > new_tag)[0];
            if (!target_field) {
                return record.appendChild(new_field);
            }

            return target_field.before(new_field);
        }


        return this.selectedMARCTemplate.userdata.toPromise().then( xml => {
            const doc = new DOMParser().parseFromString(xml, 'text/xml');

            this.attrs.forEach(attr => {
                const value = this.values[attr.id()];
                if (value === undefined) { return; }

                const expr = attr.xpath();

                // Logic copied from openils/MarcXPathParser.js
                // Any 3 numbers are a 'tag'.
                // Any letters are a subfield.
                // Always use the first.
                const tags = expr.match(/\d{3}/g);
                let subfields = expr.match(/['"]([a-z]+)['"]/);
                if (subfields) { subfields = subfields[1].split(''); }


                if (tags[0] < '010') {
                    const cfNode = doc.createElement('controlfield');

                    cfNode.setAttribute('tag', '' + tags[0]);
                    cfNode.appendChild(doc.createTextNode(value));

                    replaceMARCXMLField(doc.documentElement, cfNode) || insertOrderedMARCXMLField(doc.documentElement, cfNode);
                } else {
                    const dfNode = doc.createElement('datafield');
                    const sfNode = doc.createElement('subfield');

                    // Append fields to the document
                    dfNode.setAttribute('tag', '' + tags[0]);
                    if (attr.code() === 'upc') {
                        dfNode.setAttribute('ind1', '1');
                    } else {
                        dfNode.setAttribute('ind1', ' ');
                    }
                    dfNode.setAttribute('ind2', ' ');
                    sfNode.setAttribute('code', '' + subfields[0]);
                    const tNode = doc.createTextNode(value);

                    sfNode.appendChild(tNode);
                    dfNode.appendChild(sfNode);

                    replaceMARCXMLField(doc.documentElement, dfNode) || insertOrderedMARCXMLField(doc.documentElement, dfNode);
                }

                stripEmptyMARCXMLFields(doc.documentElement);
            });

            return new XMLSerializer().serializeToString(doc);
        });
    }

    save() {
        if (this.isSaving) {return;}
        this.isSaving = true;
        this.saveManualPicklist()
            .then(ok => { if (ok) { return this.createLineitem(); } })
            .finally(() => this.isSaving = false);
    }

    setWSDefaultTemplate () {
        if (this.selectedMARCTemplate?.id) {
            return this.store.setItem('acq.default_bib_marc_template', this.selectedMARCTemplate.id);
        }
    }

    canSave(): boolean {
        return (!!this.targetPo || !!this.targetPicklist
                    || (this.selectedPo && this.selectedPo.label)
                    || (this.selectedPl && this.selectedPl.label)
        ) && Object.keys(this.values)
            .filter(k => Boolean(this.values[k]))
            .length > 0;
    }

    saveManualPicklist(): Promise<boolean> {
        if (this.targetPo) { return Promise.resolve(true); }
        if (this.targetPicklist) { return Promise.resolve(true); }
        if (!this.selectedPl && !this.selectedPo) { return Promise.resolve(false); }

        if (this.selectedPo) {
            this.targetPo = this.selectedPo.id;
            return Promise.resolve(true);
        } else if (!this.selectedPl.freetext) {
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

    createLineitem() {

        this.compile().then( xml => {

            const li = this.idl.create('jub');
            li.marc(xml);

            if (this.targetPicklist) {
                li.picklist(this.targetPicklist);
            } else if (this.targetPo) {
                li.purchase_order(this.targetPo);
            }

            li.selector(this.auth.user().id());
            li.creator(this.auth.user().id());
            li.editor(this.auth.user().id());

            this.net.request('open-ils.acq',
                'open-ils.acq.lineitem.create', this.auth.token(), li
            ).toPromise().then(liId => {

                const evt = this.evt.parse(liId);
                if (evt) { alert(evt); return; }

                this.liService.activateStateChange.emit();

                if (this.selectedPl) {
                    // Brief record was added to a picklist that is not
                    // currently focused in the UI.  Jump to it.
                    const url = `/staff/acq/picklist/${this.targetPicklist}`;
                    this.router.navigate([url], {fragment: liId});
                } else if (this.selectedPo) {
                    // Brief record was added to a PO that is not
                    // currently focused in the UI.  Jump to it.
                    const url = `/staff/acq/po/${this.targetPo}`;
                    this.router.navigate([url], {fragment: liId});
                } else {

                    this.router.navigate(['../'], {
                        relativeTo: this.route,
                        queryParamsHandling: 'merge'
                    });
                }
            });
        });
    }
}

