import {Component, OnInit, AfterViewInit, ViewChild, ChangeDetectorRef, OnDestroy} from '@angular/core';
import {filter, takeUntil, Subject, Observable, of} from 'rxjs';
import {NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {Router, ActivatedRoute, NavigationEnd} from '@angular/router';
import {IdlService} from '@eg/core/idl.service';
import {AcqProviderSummaryPaneComponent} from './summary-pane.component';
import {ProviderDetailsComponent} from './provider-details.component';
import {ProviderHoldingsComponent} from './provider-holdings.component';
import {ProviderResultsComponent} from './provider-results.component';
import {ProviderRecordService} from './provider-record.service';
import {FmRecordEditorComponent} from '@eg/share/fm-editor/fm-editor.component';
import {StringComponent} from '@eg/share/string/string.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {AuthService} from '@eg/core/auth.service';
import {StoreService} from '@eg/core/store.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';

@Component({
    templateUrl: './acq-provider.component.html'
})

export class AcqProviderComponent implements OnInit, AfterViewInit, OnDestroy {

    activeTab = '';
    showSearchForm = false;
    id = null;
    validTabTypes = ['details', 'addresses', 'contacts', 'attributes', 'holdings', 'edi_accounts', 'purchase_orders', 'invoices'];
    defaultTabType = 'details';
    @ViewChild('acqSearchProviderSummary', { static: true }) providerSummaryPane: AcqProviderSummaryPaneComponent;
    @ViewChild('acqProviderResults', { static: true }) acqProviderResults: ProviderResultsComponent;
    @ViewChild('providerDetails', { static: false }) providerDetails: ProviderDetailsComponent;
    @ViewChild('providerHoldings', { static: false }) providerHoldings: ProviderHoldingsComponent;
    @ViewChild('createDialog', { static: true }) createDialog: FmRecordEditorComponent;
    @ViewChild('createString', { static: false }) createString: StringComponent;
    @ViewChild('createErrString', { static: false }) createErrString: StringComponent;
    @ViewChild('leaveConfirm', { static: true }) leaveConfirm: ConfirmDialogComponent;

    onNavChange: ($event: NgbNavChangeEvent) => void;

    onDesireSummarize: ($event: number, updateSummaryOnly?: boolean, hideSearchForm?: boolean) => void;
    onSummaryToggled: ($event: boolean) => void;

    previousUrl: string = null;
    public destroyed = new Subject<any>();
    _alreadyDeactivated = false;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private auth: AuthService,
        private idl: IdlService,
        public providerRecord: ProviderRecordService,
        private toast: ToastService,
        private store: StoreService,
        private changeDetector: ChangeDetectorRef
    ) {
        this.router.events.pipe(
            filter((event): event is NavigationEnd => event instanceof NavigationEnd),
            takeUntil(this.destroyed)
        ).subscribe(routeEvent => {
            if (routeEvent instanceof NavigationEnd) {
                // eslint-disable-next-line eqeqeq
                if (this.previousUrl != null &&
                    routeEvent.url === '/staff/acq/provider') {
                    this.acqProviderResults.resetSearch();
                    this.showSearchForm = true;
                    this.id = null;
                }
                this.previousUrl = routeEvent.url;
            }
        });
    }

    ngOnInit() {
        const self = this;

        const tabTypeParam = this.route.snapshot.paramMap.get('tab');
        const idParam = this.route.snapshot.paramMap.get('id');

        this.defaultTabType =
            this.store.getLocalItem('eg.acq.provider.default_tab') || 'details';

        // eslint-disable-next-line no-prototype-builtins
        const keepSearchForm = history.state.hasOwnProperty('keepSearchForm') ?
            history.state.keepSearchForm :
            false;
        if (keepSearchForm) {
            this.showSearchForm = true;
        }

        if (idParam) {
            if (!keepSearchForm) {
                this.showSearchForm = false;
            }
            this.id = idParam;
            if (!tabTypeParam) {
                this.activeTab = this.defaultTabType;
                this.router.navigate(['/staff', 'acq', 'provider', this.id, this.activeTab]);
            }
        }

        if (tabTypeParam) {
            if (!keepSearchForm) {
                this.showSearchForm = false;
            }
            if (this.validTabTypes.includes(tabTypeParam)) {
                this.activeTab = tabTypeParam;
            } else {
                this.activeTab = this.defaultTabType;
                this.router.navigate(['/staff', 'acq', 'provider', this.id, this.activeTab]);
            }
        } else {
            this.showSearchForm = true;
        }

        this.onNavChange = ($event) => {
            $event.preventDefault();
            this.canDeactivate().subscribe(canLeave => {
                if (!canLeave) { return; }
                this._alreadyDeactivated = true; // don't trigger again on the route change
                if (this.validTabTypes.includes($event.nextId)) {
                    this.activeTab = $event.nextId;
                    const id = this.route.snapshot.paramMap.get('id');
                    this.router.navigate(['/staff', 'acq', 'provider', this.id, $event.nextId]);
                }
            });
        };

        this.onDesireSummarize = ($event, updateSummaryOnly = false, hideSearchForm = true) => {
            this.id = $event;
            this.providerRecord.fetch(this.id).then(() => {
                // $event is a provider ID
                this.providerSummaryPane.update($event);
                if (this.providerDetails) {
                    this.providerDetails.refresh();
                }
                if (updateSummaryOnly) {
                    return;
                }
                this.providerRecord.announceProviderUpdated();
                if (hideSearchForm) {
                    this.showSearchForm = false;
                }
                this.activeTab = this.defaultTabType;
                this.router.navigate(
                    ['/staff', 'acq', 'provider', this.id, this.activeTab],
                    { state: { keepSearchForm: !hideSearchForm } }
                );
            });
        };

        this.onSummaryToggled = ($event) => {
            // in case this is useful for a better implementation of reflowing the UI
        };
    }

    ngAfterViewInit() {
        this.changeDetector.detectChanges();
    }

    ngOnDestroy(): void {
        this.destroyed.next(null);
        this.destroyed.complete();
    }

    setDefaultTab() {
        this.defaultTabType = this.activeTab;
        this.store.setLocalItem('eg.acq.provider.default_tab', this.activeTab);
    }

    createNew() {
        this.createDialog.mode = 'create';
        const provider = this.idl.create('acqpro');
        provider.active(true);
        provider.owner(this.auth.user().ws_ou());
        provider.default_copy_count(1);
        this.createDialog.record = provider;
        this.createDialog.recordId = null;
        this.createDialog.open({size: 'lg'}).subscribe(
            { next: ok => {
                this.createString.current()
                    .then(str => this.toast.success(str));
                this.onDesireSummarize(ok.id());
            }, error: (rejection: any) => {
                if (!rejection.dismissed) {
                    this.createErrString.current()
                        .then(str => this.toast.danger(str));
                }
            } }
        );
    }

    canDeactivate(): Observable<boolean> {
        if (this._alreadyDeactivated) {
            // one freebie
            this._alreadyDeactivated = false;
            return of(true);
        }
        if ((this.providerHoldings && this.providerHoldings.isDirty()) ||
            (this.providerDetails && this.providerDetails.isDirty())) {
            return this.leaveConfirm.open();
        } else {
            return of(true);
        }
    }
}
