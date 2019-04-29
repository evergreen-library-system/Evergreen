import {Component, OnInit, TemplateRef, ElementRef, Renderer2} from '@angular/core';
import {PrintService, PrintRequest} from './print.service';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {HatchService, HatchMessage} from './hatch.service';

@Component({
    selector: 'eg-print',
    templateUrl: './print.component.html'
})

export class PrintComponent implements OnInit {

    // Template that requires local processing
    template: TemplateRef<any>;

    // Context data used for processing the template.
    context: any;

    // Insertion point for externally-compiled templates
    htmlContainer: Element;

    isPrinting: boolean;

    printQueue: PrintRequest[];

    constructor(
        private renderer: Renderer2,
        private elm: ElementRef,
        private store: StoreService,
        private serverStore: ServerStoreService,
        private hatch: HatchService,
        private printer: PrintService) {
        this.isPrinting = false;
        this.printQueue = [];
    }

    ngOnInit() {
        this.printer.onPrintRequest$.subscribe(
            printReq => this.handlePrintRequest(printReq));

        this.htmlContainer =
            this.renderer.selectRootElement('#eg-print-html-container');
    }

    handlePrintRequest(printReq: PrintRequest) {

        if (this.isPrinting) {
            // Avoid print collisions by queuing requests as needed.
            this.printQueue.push(printReq);
            return;
        }

        this.isPrinting = true;

        this.applyTemplate(printReq);

        // Give templates a chance to render before printing
        setTimeout(() => {
            this.dispatchPrint(printReq);
            this.reset();
        });
    }

    applyTemplate(printReq: PrintRequest) {

        if (printReq.template) {
            // Inline template.  Let Angular do the interpolationwork.
            this.template = printReq.template;
            this.context = {$implicit: printReq.contextData};
            return;
        }

        if (printReq.text && !this.useHatch()) {
            // Insert HTML into the browser DOM for in-browser printing only.

            if (printReq.contentType === 'text/plain') {
                // Wrap text/plain content in pre's to prevent
                // unintended html formatting.
                printReq.text = `<pre>${printReq.text}</pre>`;
            }

            this.htmlContainer.innerHTML = printReq.text;
        }
    }

    // Clear the print data
    reset() {
        this.isPrinting = false;
        this.template = null;
        this.context = null;
        this.htmlContainer.innerHTML = '';

        if (this.printQueue.length) {
            this.handlePrintRequest(this.printQueue.pop());
        }
    }

    dispatchPrint(printReq: PrintRequest) {

        if (!printReq.text) {
            // Sometimes the results come from an externally-parsed HTML
            // template, other times they come from an in-page template.
            printReq.text = this.elm.nativeElement.innerHTML;
        }

        // Retain a copy of each printed document in localStorage
        // so it may be reprinted.
        this.store.setLocalItem('eg.print.last_printed', {
            content: printReq.text,
            context: printReq.printContext,
            content_type: printReq.contentType,
            show_dialog: printReq.showDialog
        });

        if (this.useHatch()) {
            this.printViaHatch(printReq);
        } else {
            // Here the needed HTML is already in the page.
            window.print();
        }
    }

    useHatch(): boolean {
        return this.store.getLocalItem('eg.hatch.enable.printing')
            && this.hatch.connect();
    }

    printViaHatch(printReq: PrintRequest) {

        // Send a full HTML document to Hatch
        const html = `<html><body>${printReq.text}</body></html>`;

        this.serverStore.getItem(`eg.print.config.${printReq.printContext}`)
        .then(config => {

            const msg = new HatchMessage({
                action: 'print',
                content: html,
                settings: config || {},
                contentType: 'text/html',
                showDialog: printReq.showDialog
            });

            this.hatch.sendRequest(msg).then(
                ok  => console.debug('Print request succeeded'),
                err => console.warn('Print request failed', err)
            );
        });
    }
}

