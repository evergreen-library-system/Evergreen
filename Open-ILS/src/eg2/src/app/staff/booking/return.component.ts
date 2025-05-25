import {Component, OnInit, OnDestroy, QueryList, ViewChildren, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {FormGroup, FormControl, Validators} from '@angular/forms';
import {NgbNav, NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {Observable, from, of, Subscription, single, switchMap, tap, debounceTime } from 'rxjs';
import {PatronService} from '@eg/staff/share/patron/patron.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlObject} from '@eg/core/idl.service';
import {ReservationsGridComponent} from './reservations-grid.component';
import {ServerStoreService} from '@eg/core/server-store.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {PatronBarcodeValidator} from '@eg/share/validators/patron_barcode_validator.directive';


@Component({
    templateUrl: './return.component.html'
})

export class ReturnComponent implements OnInit, OnDestroy {
    patronId: number;
    findPatron: FormGroup;
    subscriptions: Subscription[] = [];
    patronTab: any;

    noSelectedRows: (rows: IdlObject[]) => boolean;
    handleNavChange: ($event: NgbNavChangeEvent) => void;
    @ViewChild('tabs', { static: true }) tabs: NgbNav;
    @ViewChildren(ReservationsGridComponent) grids: QueryList<ReservationsGridComponent>;

    constructor(
        private pcrud: PcrudService,
        private patron: PatronService,
        private pbv: PatronBarcodeValidator,
        private route: ActivatedRoute,
        private router: Router,
        private store: ServerStoreService,
        private toast: ToastService
    ) {
    }


    ngOnInit() {
        this.route.paramMap.pipe(switchMap((params: ParamMap) => {
            return this.handleParams$(params);
        })).subscribe();

        this.patronTab =
            this.store.getItem('eg.booking.return.tab')
            || 'patron_tab';

        this.findPatron = new FormGroup({
            'patronBarcode': new FormControl(null,
                [Validators.required],
                [this.pbv.validate]),
            'resourceBarcode': new FormControl(null,
                [Validators.required])
        });

        const debouncing = 1500;
        this.subscriptions.push(
            this.patronBarcode.valueChanges.pipe(
                debounceTime(debouncing),
                switchMap((val) => {
                    if ('INVALID' === this.patronBarcode.status) {
                        this.toast.danger('No patron found with this barcode');
                        return of();
                    } else {
                        return this.patron.bcSearch(val).pipe(
                            single(),
                            tap((resp) => { this.router.navigate(['/staff', 'booking', 'return', 'by_patron', resp[0].id]); })
                        );
                    }
                })
            )
                .subscribe());

        this.subscriptions.push(
            this.resourceBarcode.valueChanges.pipe(
                debounceTime(debouncing),
                switchMap((val) => {
                    if ('INVALID' !== this.resourceBarcode.status) {
                        return this.pcrud.search('brsrc', {'barcode': val}, {
                            order_by: {'curr_rsrcs': 'pickup_time DESC'},
                            limit: 1,
                            flesh: 1,
                            flesh_fields: {'brsrc': ['curr_rsrcs']},
                            select: {'curr_rsrcs': {'return_time': null, 'pickup_time': {'!=': null}}}
                        }).pipe(tap((resp) => {
                            if (resp.curr_rsrcs()[0].usr()) {
                                this.tabs.select('resource');
                                this.patronId = resp.curr_rsrcs()[0].usr();
                                this.refreshGrids();
                            }
                        }));
                    } else {
                        return of();
                    }
                })
            ).subscribe()
        );
        this.noSelectedRows = (rows: IdlObject[]) => (rows.length === 0);

        this.handleNavChange = ($event) => {
            this.store.setItem('eg.booking.return.tab', $event.nextId)
                .then(() => {
                    this.router.navigate(['/staff', 'booking', 'return']);
                    this.findPatron.patchValue({resourceBarcode: ''});
                    this.patronId = null;
                });
        };
    }

    handleParams$ = (params: ParamMap): Observable<any> => {
        this.patronId = +params.get('patron_id');
        if (this.patronId) {
            return this.pcrud.search('au', {
                'id': this.patronId,
            }, {
                limit: 1,
                flesh: 1,
                flesh_fields: {'au': ['card']}
            }).pipe(tap(
                { next: (resp) => {
                    this.tabs.select('patron_tab');
                    this.findPatron.patchValue({patronBarcode: resp.card().barcode()});
                    this.refreshGrids();
                }, error: (err: unknown) => { console.debug(err); } }
            ));
        } else {
            return from(this.store.getItem('eg.booking.return.tab'))
                .pipe(tap(tab => {
                    if (tab) { this.tabs.select(tab); }
                }));
        }
    };
    refreshGrids = (): void => {
        this.grids.forEach (grid => grid.reloadGrid());
    };
    get patronBarcode() {
        return this.findPatron.get('patronBarcode');
    }
    get resourceBarcode() {
        return this.findPatron.get('resourceBarcode');
    }

    ngOnDestroy(): void {
        this.subscriptions.forEach((subscription) => {
            subscription.unsubscribe();
        });
    }
}
