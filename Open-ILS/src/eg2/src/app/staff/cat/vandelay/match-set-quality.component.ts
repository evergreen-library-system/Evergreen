import {Component, OnInit, ViewChild, AfterViewInit, Input} from '@angular/core';
import {Observable, of} from 'rxjs';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {Pager} from '@eg/share/util/pager';
import {MatchSetNewPointComponent} from './match-set-new-point.component';

@Component({
  selector: 'eg-match-set-quality',
  templateUrl: 'match-set-quality.component.html'
})
export class MatchSetQualityComponent implements OnInit {

    // Match set arrives from parent async.
    matchSet_: IdlObject;
    @Input() set matchSet(ms: IdlObject) {
        this.matchSet_ = ms;
        if (ms) {
            this.matchSetType = ms.mtype();
            if (this.grid) {
                this.grid.reload();
            }
        }
    }

    newPointType: string;
    matchSetType: string;
    dataSource: GridDataSource;
    @ViewChild('newPoint') newPoint: MatchSetNewPointComponent;
    @ViewChild('grid') grid: GridComponent;
    deleteSelected: (rows: IdlObject[]) => void;

    constructor(
        private idl: IdlService,
        private pcrud: PcrudService,
        private net: NetService,
        private auth: AuthService,
        private org: OrgService
    ) {

        this.dataSource = new GridDataSource();
        this.dataSource.getRows = (pager: Pager, sort: any[]) => {

            if (!this.matchSet_) {
                return of();
            }

            const orderBy: any = {};
            if (sort.length) {
                orderBy.vmsq = sort[0].name + ' ' + sort[0].dir;
            }

            const searchOps = {
                offset: pager.offset,
                limit: pager.limit,
                order_by: orderBy
            };

            const search = {match_set: this.matchSet_.id()};
            return this.pcrud.search('vmsq', search, searchOps);
        };

        this.deleteSelected = (rows: any[]) => {
            this.pcrud.remove(rows).subscribe(
                ok  => console.log('deleted ', ok),
                err => console.error(err),
                ()  => this.grid.reload()
            );
        };
    }

    ngOnInit() {}

    addQuality() {
        const quality = this.idl.create('vmsq');
        const values = this.newPoint.values;

        quality.match_set(this.matchSet_.id());
        quality.quality(values.matchScore);
        quality.value(values.value);

        if (values.recordAttr) {
            quality.svf(values.recordAttr);
        } else {
            quality.tag(values.marcTag);
            quality.subfield(values.marcSf);
        }

        this.pcrud.create(quality).subscribe(
            ok  => console.debug('created ', ok),
            err => console.error(err),
            ()  => {
                this.newPointType = null;
                this.grid.reload();
            }
        );
    }
}

