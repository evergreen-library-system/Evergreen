import {Injectable} from '@angular/core';
import {Router} from '@angular/router';
import {PcrudService} from '@eg/core/pcrud.service';

// Some grid actions that are shared across booking grids

@Injectable({providedIn: 'root'})
export class ReservationActionsService {

    constructor(
        private pcrud: PcrudService,
        private router: Router,
    ) {
    }

    manageReservationsByResource = (barcode: string) => {
        this.router.navigate(['/staff', 'booking', 'manage_reservations', 'by_resource', barcode]);
    }

    viewItemStatus = (barcode: string) => {
        this.pcrud.search('acp', { 'barcode': barcode }, { limit: 1 })
        .subscribe((acp) => {
            window.open('/eg/staff/cat/item/' + acp.id());
        });
    }

    notOneUniqueSelected = (ids: number[]) => {
        return (new Set(ids).size !== 1);
    }

}

