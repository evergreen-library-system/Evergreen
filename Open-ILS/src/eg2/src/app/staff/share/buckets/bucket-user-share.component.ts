
import {Component, Input, OnInit, ViewChild} from '@angular/core';
import {GridContext, GridDataSource, GridCellTextGenerator} from '@eg/share/grid/grid';
import {GridComponent} from '@eg/share/grid/grid.component';
import {IdlObject} from '@eg/core/idl.service';

@Component({
    selector: 'eg-bucket-user-share',
    templateUrl: './bucket-user-share.component.html'
})

export class BucketUserShareComponent
implements OnInit {

    @Input() cellTextGenerator: GridCellTextGenerator;
    @Input() dataSource: GridDataSource = new GridDataSource();
    @Input() trickery: Function;
    @Input() addUsers: Function;
    @Input() removeUsers: Function;
    @Input() onRowActivate: Function;

    @ViewChild('userGrid', { static: true }) userGrid: GridComponent;

    noSelectedRows = false;
    oneSelectedRow = false;

    constructor() {}

    async ngOnInit() {
        console.debug('BucketUserShareComponent, this',this);
        if (this.trickery) {
            console.debug('found trickery');
            this.trickery( this );
        } else {
            console.error('no trickery');
        }
    }

    getGrid() {
        return this.userGrid;
    }

    reload() {
        this.userGrid.reload();
    }

    gridSelectionChange(keys: string[]) {
        this.updateSelectionState(keys);
    }

    updateSelectionState(keys: string[]) {
        this.noSelectedRows = (keys.length === 0);
        this.oneSelectedRow = (keys.length === 1);
    }
}
