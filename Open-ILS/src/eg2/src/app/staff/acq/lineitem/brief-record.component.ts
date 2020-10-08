import {Component, OnInit, Input, Output} from '@angular/core';
import {ActivatedRoute, Router, ParamMap} from '@angular/router';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {AuthService} from '@eg/core/auth.service';

const MARC_NS = 'http://www.loc.gov/MARC21/slim';

const MARC_XML_BASE = `
<record xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns="http://www.loc.gov/MARC21/slim"
    xmlns:marc="http://www.loc.gov/MARC21/slim"
    xsi:schemaLocation="http://www.loc.gov/MARC21/slim http://www.loc.gov/ standards/marcxml/schema/MARC21slim.xsd">
    <leader>00000nam a22000007a 4500</leader>
</record>
`;

@Component({
  templateUrl: 'brief-record.component.html',
  selector: 'eg-lineitem-brief-record'
})
export class BriefRecordComponent implements OnInit {

    targetPicklist: number;
    targetPo: number;

    attrs: IdlObject[] = [];
    values: {[attr: string]: string} = {};

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private idl: IdlService,
        private auth: AuthService,
        private net: NetService,
        private pcrud: PcrudService
    ) { }

    ngOnInit() {

        this.route.parent.paramMap.subscribe((params: ParamMap) => {
            this.targetPicklist = +params.get('picklistId');
            this.targetPo = +params.get('poId');
        });

        this.pcrud.retrieveAll('acqlimad')
        .subscribe(attr => this.attrs.push(attr));
    }

    compile(): string {

        const doc = new DOMParser().parseFromString(MARC_XML_BASE, 'text/xml');

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

            const dfNode = doc.createElementNS(MARC_NS, 'marc:datafield');
            const sfNode = doc.createElementNS(MARC_NS, 'marc:subfield');

            // Append fields to the document
            dfNode.setAttribute('tag', '' + tags[0]);
            dfNode.setAttribute('ind1', ' ');
            dfNode.setAttribute('ind2', ' ');
            sfNode.setAttribute('code', '' + subfields[0]);
            const tNode = doc.createTextNode(value);

            sfNode.appendChild(tNode);
            dfNode.appendChild(sfNode);
            doc.documentElement.appendChild(dfNode);
        });

        return new XMLSerializer().serializeToString(doc);
    }

    save() {
        const xml = this.compile();

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
        ).toPromise().then(_ => {
            this.router.navigate(['../'], {
                relativeTo: this.route,
                queryParamsHandling: 'merge'
            });
        });
    }
}

