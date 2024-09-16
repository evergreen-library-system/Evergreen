import {Component, Input, Output, OnInit, OnDestroy, ViewChild, EventEmitter} from '@angular/core';
import {FormGroup, FormControl, Validators} from '@angular/forms';
// import {Router} from '@angular/router';
import {Subscription, Observable, of} from 'rxjs';
import {switchMap, single, startWith, tap} from 'rxjs/operators';
import {NgbModal} from '@ng-bootstrap/ng-bootstrap';
import {AuthService} from '@eg/core/auth.service';
// import {FormatService} from '@eg/core/format.service';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {EventService} from '@eg/core/event.service';
// import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {DialogComponent} from '@eg/share/dialog/dialog.component';
import {PatronBarcodeValidator} from '@eg/share/validators/patron_barcode_validator.directive';
import {PatronSearchDialogComponent} from '@eg/staff/share/patron/search-dialog.component';
import {ToastService} from '@eg/share/toast/toast.service';
import {AlertDialogComponent} from '@eg/share/dialog/alert.component';
import {BucketActionSummaryDialogComponent} from './bucket-action-summary-dialog.component';

@Component({
    selector: 'eg-bucket-transfer-dialog',
    templateUrl: './bucket-transfer-dialog.component.html'
})

export class BucketTransferDialogComponent
    extends DialogComponent implements OnInit, OnDestroy {

    subscriptions: Subscription[] = []; // unsubscribed from in ngOnDestroy

    @Input() patronId: number;
    destinationPatronId: number;
    @Input() containerType = 'biblio';
    @Input() containerObjects: any[];
    @Output() transferRequestCompleted: EventEmitter<boolean>;
    containerTransferResultMap = {};

    patron$: Observable<{first_given_name: string, second_given_name: string, family_name: string}>;

    @ViewChild('fail', { static: true }) fail: AlertDialogComponent;
    @ViewChild('results', { static: true }) results: BucketActionSummaryDialogComponent;
    @ViewChild('patronSearch') patronSearch: PatronSearchDialogComponent;

    constructor(
        private auth: AuthService,
        // private format: FormatService,
        private net: NetService,
        private evt: EventService,
        // private org: OrgService,
        private pcrud: PcrudService,
        // private router: Router,
        private modal: NgbModal,
        private pbv: PatronBarcodeValidator,
        private toast: ToastService
    ) {
        super(modal);
        this.transferRequestCompleted = new EventEmitter<boolean>();
    }

    ngOnInit() {
        console.debug('bucketTransferDialogComponent, this',this);

        if (this.patronId) {
            this.pcrud.search('au', {id: this.patronId}, {
                flesh: 1,
                flesh_fields: {'au': ['card']}
            }).subscribe((usr) => {
                this.destinationPatronId = usr.id();
                this.patron$ = of({first_given_name: usr.first_given_name(),
                    second_given_name: usr.second_given_name(), family_name: usr.family_name()});
            });
        } else {
            this.patron$ = of({first_given_name: '', second_given_name: '', family_name: ''});
        }
    }

    ngOnDestroy() {
        this.subscriptions.forEach((subscription) => {
            subscription.unsubscribe();
        });
    }

    transferOwner$ = () => {
        this.containerTransferResultMap = {};
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.containers.transfer',
            this.auth.token(),
            this.destinationPatronId,
            this.containerType,
            this.containerObjects.map( o => o.id )
        ).pipe(
            tap({
                next: (response) => {
                    const evt = this.evt.parse(response);
                    if (evt) {
                        console.error(evt.toString());
                        this.fail.dialogBody = evt.toString();
                        this.fail.open();
                    } else {
                        Object.entries(response).map(([id, result]) => {
                            let pass_or_fail = $localize`Success`;
                            const evt2 = this.evt.parse(result);
                            if (evt2) {
                                pass_or_fail = evt2.toString();
                            }
                            this.containerTransferResultMap[id] = pass_or_fail;
                        });
                        console.debug(this.containerTransferResultMap);
                        this.results.open(this.containerObjects, this.containerTransferResultMap).subscribe({ complete: () => {
                            this.close(this.containerTransferResultMap);
                        }});
                    }
                },
                error: (response: unknown) => {
                    console.error(response);
                    this.fail.open();
                    this.transferRequestCompleted.emit(false);
                },
                complete: () => {
                    this.transferRequestCompleted.emit(true);
                    this.close(this.containerTransferResultMap);
                }
            })
        );
    };

    transferBucketOwner() {
        this.subscriptions.push(this.transferOwner$().subscribe());
    }

    searchPatrons() {
        this.patronSearch.open({size: 'xl'}).toPromise().then(
            patrons => {
                if (!patrons || patrons.length === 0) { return; }
                const usr = patrons[0];
                this.destinationPatronId = usr.id();
                this.patron$ = of({first_given_name: usr.first_given_name(),
                    second_given_name: usr.second_given_name(), family_name: usr.family_name()});
            }
        );
    }
}

