import { Injectable, inject } from '@angular/core';
import {EventService} from '@eg/core/event.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';

@Injectable()
export class AsnService {
    private evt = inject(EventService);
    private net = inject(NetService);
    private auth = inject(AuthService);
}

