import { Component, Input, ViewChild, OnInit, inject } from '@angular/core';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {IdlObject} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {Pager} from '@eg/share/util/pager';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import { GridModule } from '@eg/share/grid/grid.module';

@Component({
    selector: 'eg-edi-attr-set-providers',
    templateUrl: './edi-attr-set-providers.component.html',
    imports: [GridModule]
})

export class EdiAttrSetProvidersComponent
    extends DialogComponent implements OnInit {
    private pcrud = inject(PcrudService);
    private modal: NgbModal;


    @Input() attrSetId: number;
    @ViewChild('grid', { static: false }) grid: GridComponent;
    attrSet: IdlObject;
    dataSource: GridDataSource;
    cellTextGenerator: GridCellTextGenerator;

    constructor() {
        const modal = inject(NgbModal);

        super(modal);
        this.modal = modal;

        this.dataSource = new GridDataSource();
    }

    ngOnInit() {
        this.attrSet = null;
        this._initRecord();
        this.cellTextGenerator = {
            name: row => row.name()
        };
    }

    private _initRecord() {
        this.attrSet = null;
        let providerIds = [];
        this.pcrud.retrieve('aeas', this.attrSetId, {
            flesh: 1,
            flesh_fields: { aeas: ['edi_accounts'] }
        }).subscribe(res => {
            this.attrSet = res;
            providerIds = res.edi_accounts().map(r => r.provider());
            this.dataSource.getRows = (pager: Pager, sort: any[]) => {

                const idlClass = 'acqpro';
                const orderBy: any = {};
                if (sort.length) {
                    // Sort specified from grid
                    orderBy[idlClass] = sort[0].name + ' ' + sort[0].dir;
                }

                const searchOps = {
                    offset: pager.offset,
                    limit: pager.limit,
                    order_by: orderBy,
                    flesh: 1,
                    flesh_fields: {
                        acqpro: ['owner']
                    }
                };
                const reqOps = { };

                const search: any = new Array();
                search.push({ id: providerIds });
                const orgFilter: any = {};

                Object.keys(this.dataSource.filters).forEach(key => {
                    Object.keys(this.dataSource.filters[key]).forEach(key2 => {
                        search.push(this.dataSource.filters[key][key2]);
                    });
                });

                return this.pcrud.search(idlClass, search, searchOps, reqOps);
            };
            this.grid.reload();
        });
    }

}
