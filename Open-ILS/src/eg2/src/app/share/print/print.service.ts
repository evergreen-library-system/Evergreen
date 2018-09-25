import {Injectable, EventEmitter, TemplateRef} from '@angular/core';
import {StoreService} from '@eg/core/store.service';

export interface PrintRequest {
    template?: TemplateRef<any>;
    contextData?: any;
    text?: string;
    printContext: string;
    contentType?: string; // defaults to text/html
    showDialog?: boolean;
}

@Injectable()
export class PrintService {

    onPrintRequest$: EventEmitter<PrintRequest>;

    constructor(private store: StoreService) {
        this.onPrintRequest$ = new EventEmitter<PrintRequest>();
    }

    print(printReq: PrintRequest) {
        this.onPrintRequest$.emit(printReq);
    }

    reprintLast() {
        const prev = this.store.getLocalItem('eg.print.last_printed');

        if (prev) {
            const req: PrintRequest = {
                text: prev.content,
                printContext: prev.context || 'default',
                contentType: prev.content_type || 'text/html',
                showDialog: Boolean(prev.show_dialog)
            };

            this.print(req);
        }
    }
}

