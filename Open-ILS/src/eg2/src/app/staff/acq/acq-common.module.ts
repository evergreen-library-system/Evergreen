import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {UploadComponent} from './picklist/upload.component';
import {LineitemService} from './lineitem/lineitem.service';
import {PoService} from './po/po.service';
import {PoLabelComponent} from './po/label.component';
import {InvoiceService} from './invoice/invoice.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {EventService} from '@eg/core/event.service';
import {IdlService} from '@eg/core/idl.service';
import {PcrudService} from '@eg/core/pcrud.service';

@NgModule({
    declarations: [
        UploadComponent,
        PoLabelComponent,
    ],
    exports: [
        UploadComponent,
        PoLabelComponent,
    ],
    imports: [
        StaffCommonModule,
    ],
    providers: [
        LineitemService,
        PoService,
        {
            provide: InvoiceService,
            useFactory: (
                evt: EventService,
                net: NetService,
                pcrud: PcrudService,
                auth: AuthService,
                poService: PoService,
                liService: LineitemService,
                idl: IdlService
            ) => {
                const invoiceService = new InvoiceService(evt, net, pcrud, auth, poService, liService, idl);
                // Initialize the service before providing it
                invoiceService.initialize().then();
                return invoiceService;
            },
            deps: [EventService, NetService, PcrudService, AuthService, PoService, LineitemService, IdlService],
        },
    ]
})

export class AcqCommonModule {
}
