import {Injectable} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {Observable} from 'rxjs';


@Injectable()
export class PatronService {
    constructor(
        private net: NetService,
        private auth: AuthService
    ) {}

    bcSearch(barcode: string): Observable<any> {
        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.get_barcodes',
            this.auth.token(), this.auth.user().ws_ou(),
           'actor', barcode.trim());
    }

}

