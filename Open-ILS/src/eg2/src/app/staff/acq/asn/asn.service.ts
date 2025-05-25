import {Injectable} from '@angular/core';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';

@Injectable()
export class AsnService {

    constructor(
        private evt: EventService,
        private net: NetService,
        private auth: AuthService
    ) {}
}

