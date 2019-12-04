import {Component, Input, OnInit} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {GridDataSource} from '@eg/share/grid/grid';
import {Pager} from '@eg/share/util/pager';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlObject, IdlService } from '@eg/core/idl.service';

@Component({
    templateUrl: './edit-floating-group.component.html'
})

export class EditFloatingGroupComponent implements OnInit {

    dataSource: GridDataSource;

    // defaultNewRecord is used when creating a new entry to give a default floating_group
    defaultNewRecord: IdlObject;

    // This is the ID of the floating group being edited currently
    currentId: number;

    constructor(
        private route: ActivatedRoute,
        private pcrud: PcrudService,
        private idl: IdlService,
    ) {
    }

    ngOnInit() {
        this.currentId = parseInt(this.route.snapshot.paramMap.get('id'), 10);
        this.defaultNewRecord = this.idl.create('cfgm');
        this.defaultNewRecord.floating_group(this.currentId);
        this.dataSource = new GridDataSource();

        this.dataSource.getRows = (pager: Pager, sort: any[]) => {
            const orderBy: any = {};
            if (sort.length) {
                orderBy.cfgm = sort[0].name + ' ' + sort[0].dir;
            }

            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };

            return this.pcrud.search('cfgm',
                {floating_group: this.currentId}, searchOps);
        };
    }
}
