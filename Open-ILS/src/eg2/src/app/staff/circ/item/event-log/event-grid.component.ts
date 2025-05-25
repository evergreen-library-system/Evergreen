import {Component, Input, OnChanges, OnInit, ViewChild} from '@angular/core';
import {Router} from '@angular/router';
import {Observable} from 'rxjs';
import {AuthService} from '@eg/core/auth.service';
import {FormatService} from '@eg/core/format.service';
import {GridComponent} from '@eg/share/grid/grid.component';
import {GridDataSource} from '@eg/share/grid/grid';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {EventService} from '@eg/core/event.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {Pager} from '@eg/share/util/pager';
import {ToastService} from '@eg/share/toast/toast.service';
import {NetService} from '@eg/core/net.service';
import {OrgService} from '@eg/core/org.service';
import {BibRecordService} from '@eg/share/catalog/bib-record.service';

// A filterable grid of A/T events for circ or ahr hook core types

@Component({
    selector: 'eg-item-event-grid',
    templateUrl: './event-grid.component.html'
})

export class ItemEventGridComponent implements OnChanges, OnInit {

    @Input() item: number;
    @Input() event_type: string;

    gridSource: GridDataSource;
    numRowsSelected: number;

    act_on_events: (action: string, rows: IdlObject[]) => void;
    noRowSelected: (rows: IdlObject[]) => boolean;

    @ViewChild('grid', { static: true }) grid: GridComponent;

    constructor(
        private idl: IdlService,
        private auth: AuthService,
        private bib: BibRecordService,
        private format: FormatService,
        private pcrud: PcrudService,
        private router: Router,
        private toast: ToastService,
        private net: NetService,
        private evt: EventService,
        private org: OrgService
    ) {

    }

    ngOnInit() {
        this.gridSource = new GridDataSource();

        this.gridSource.getRows = (pager: Pager, sort: any[]): Observable<IdlObject> => {
        // TODO: why is this getting called twice on page load?

            const orderBy: any = {atoul: 'id'};
            if (sort.length) {
                orderBy.atoul = sort[0].name + ' ' + sort[0].dir;
            }

            // base query to grab everything
            const base: Object = {};
            base[this.idl.classes['atoul'].pkey] = {'!=' : null};
            base['context_item'] = (this.item ? this.item : {'>' : 0});

            // circs or holds?
            if (this.event_type === 'circ') {
                base['target_circ'] = { '>' : 0 };
            } else {
                base['target_hold'] = { '>' : 0 };
            }

            const query: any = new Array();
            query.push(base);

            // and add any filters
            Object.keys(this.gridSource.filters).forEach(key => {
                Object.keys(this.gridSource.filters[key]).forEach(key2 => {
                    query.push(this.gridSource.filters[key][key2]);
                });
            });

            return this.pcrud.search('atoul',
                query, {
                    flesh: 3,
                    flesh_fields: {
                        atoul: ['context_user', 'context_item'],
                        au: ['card']
                    },
                    offset: pager.offset,
                    limit: pager.limit,
                    order_by: orderBy
                });
        };

        this.act_on_events = (action: string, rows: IdlObject[]) => {
            this.net.request(
                'open-ils.actor',
                'open-ils.actor.user.event.' + action + '.batch',
                this.auth.token(), rows.map( event => event.id() )
            ).subscribe(
                { next: (res) => {
                    if (this.evt.parse(res)) {
                        console.error('parsed error response', res);
                    } else {
                        console.log('success', res);
                    }
                }, error: (err: unknown) => {
                    console.error('error', err);
                }, complete: () => {
                    console.log('finis');
                    this.grid.reload();
                } }
            );
        };

        this.noRowSelected = (rows: IdlObject[]) => (rows.length === 0);
    }

    ngOnChanges() { this.reloadGrid(); }

    reloadGrid() { this.grid.reload(); }
}
