import {Injectable} from '@angular/core';
import {Router} from '@angular/router';
import {Observable, of, mergeMap, switchMap, tap} from 'rxjs';
import {IdlObject} from '@eg/core/idl.service';
import {AuthService} from '@eg/core/auth.service';
import {PrintService} from '@eg/share/print/print.service';
import {PcrudService} from '@eg/core/pcrud.service';

// Some grid actions that are shared across booking grids

export interface CaptureInformation {
    captured: number;
    reservation: IdlObject;
    mvr?: IdlObject;
    new_copy_status?: number;
    transit?: IdlObject;
    resource?: IdlObject;
    type?: IdlObject;
    staff?: IdlObject;
    workstation?: string;
}

@Injectable({providedIn: 'root'})
export class ReservationActionsService {

    constructor(
        private auth: AuthService,
        private pcrud: PcrudService,
        private printer: PrintService,
        private router: Router,
    ) {
    }

    manageReservationsByResource = (barcode: string) => {
        this.router.navigate(['/staff', 'booking', 'manage_reservations', 'by_resource', barcode]);
    };

    printCaptureSlip = (templateData: CaptureInformation) => {
        templateData.staff = this.auth.user();
        templateData.workstation = this.auth.workstation();
        this.printer.print({
            templateName: 'booking_capture',
            contextData: templateData,
            printContext: 'receipt'
        });
    };

    reprintCaptureSlip = (ids: number[]): Observable<CaptureInformation> => {
        return this.fetchDataForCaptureSlip$(ids)
            .pipe(tap((data) => this.printCaptureSlip(data)));
    };

    viewItemStatus = (barcode: string) => {
        this.pcrud.search('acp', { 'barcode': barcode }, { limit: 1 })
            .subscribe((acp) => {
                window.open('/eg/staff/cat/item/' + acp.id());
            });
    };

    notOneUniqueSelected = (ids: number[]) => {
        return (new Set(ids).size !== 1);
    };

    private fetchDataForCaptureSlip$ = (ids: number[]): Observable<CaptureInformation> => {
        return this.pcrud.search('bresv', {'id': ids}, {
            flesh: 2,
            flesh_fields : {
                'bresv': ['usr', 'current_resource', 'type'],
                'au': ['card'],
                'brsrc': ['type']
            }
        }).pipe(mergeMap((reservation: IdlObject) => this.assembleDataForCaptureSlip$(reservation)));
    };

    private assembleDataForCaptureSlip$ = (reservation: IdlObject): Observable<CaptureInformation> => {
        let observable$ = of({
            reservation: reservation,
            captured: 1
        });
        if (reservation.pickup_lib() === this.auth.user().ws_ou()) {
            observable$ = this.pcrud.search('artc', {'reservation': reservation.id()}, {limit: 1})
                .pipe(switchMap(transit => {
                    return of({
                        reservation: reservation,
                        captured: 1,
                        transit: transit
                    });
                }));
        }
        return observable$;
    };

}

