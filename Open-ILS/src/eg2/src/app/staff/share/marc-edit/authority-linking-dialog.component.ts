import {Component, Input, Output, OnInit, EventEmitter} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {MarcField} from './marcrecord';
import {Pager} from '@eg/share/util/pager';

/**
 * MARC Authority Linking Dialog
 */

@Component({
  selector: 'eg-authority-linking-dialog',
  templateUrl: './authority-linking-dialog.component.html'
})

export class AuthorityLinkingDialogComponent
    extends DialogComponent implements OnInit {

    @Input() bibField: MarcField;
    @Input() thesauri: string = null;
    @Input() controlSet: number = null;
    @Input() pager: Pager;

    browseData: any[] = [];

    // If false, show the raw MARC field data.
    showAs: 'heading' | 'marc' = 'heading';

    authMeta: any;

    selectedSubfields: string[] = [];

    constructor(
        private modal: NgbModal,
        private pcrud: PcrudService,
        private net: NetService) {
        super(modal);
    }

    ngOnInit() {
        if (!this.pager) {
            this.pager = new Pager();
            this.pager.limit = 5;
        }

        this.onOpen$.subscribe(_ => this.initData());
    }

    fieldHash(field?: MarcField): any {
        if (!field) { field = this.bibField; }

        return {
            tag: field.tag,
            ind1: field.ind1,
            ind2: field.ind2,
            subfields: field.subfields.map(sf => [sf[0], sf[1]])
        };
    }

    initData() {

       this.pager.offset = 0;

       this.pcrud.search('acsbf',
            {tag: this.bibField.tag},
            {flesh: 1, flesh_fields: {acsbf: ['authority_field']}},
            {atomic:  true, anonymous: true}

        ).subscribe(bibMetas => {
            if (bibMetas.length === 0) { return; }

            let bibMeta;
            if (this.controlSet) {
                bibMeta = bibMetas.filter(b =>
                    this.controlSet === +b.authority_field().control_set());
            } else {
                bibMeta = bibMetas[0];
            }

            if (bibMeta) {
                this.authMeta = bibMeta.authority_field();
                this.bibField.subfields.forEach(sf =>
                    this.selectedSubfields[sf[0]] =
                        this.isControlledBibSf(sf[0])
                );
            }

            this.getPage(0);
        });
    }

    getPage(direction: number) {
        this.browseData = [];

        if (direction > 0) {
            this.pager.offset++;
        } else if (direction < 0) {
            this.pager.offset--;
        } else {
            this.pager.offset = 0;
        }

        const hash = this.fieldHash();

        // Only search the selected subfields
        hash.subfields =
            hash.subfields.filter(sf => this.selectedSubfields[sf[0]]);

        if (hash.subfields.length === 0) { return; }

        this.net.request(
            'open-ils.cat',
            'open-ils.cat.authority.bib_field.linking_browse',
            hash, this.pager.limit,
            this.pager.offset, this.thesauri
        ).subscribe(entry => this.browseData.push(entry));
    }

    applyHeading(authField: MarcField) {
        this.net.request(
            'open-ils.cat',
            'open-ils.cat.authority.bib_field.overlay_authority',
            this.fieldHash(), this.fieldHash(authField), this.controlSet
        ).subscribe(field => this.close(field));
    }

    isControlledBibSf(sf: string): boolean {
        return this.authMeta ?
            this.authMeta.sf_list().includes(sf) : false;
    }
}

