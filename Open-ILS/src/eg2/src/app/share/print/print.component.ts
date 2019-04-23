import {Component, OnInit, TemplateRef, ElementRef, Renderer2} from '@angular/core';
import {PrintService, PrintRequest} from './print.service';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {HatchService, HatchMessage} from '@eg/core/hatch.service';
import {ToastService} from '@eg/share/toast/toast.service';
import {StringService} from '@eg/share/string/string.service';

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

    useHatch: boolean;

    constructor(
        private renderer: Renderer2,
        private elm: ElementRef,
        private store: StoreService,
        private serverStore: ServerStoreService,
        private hatch: HatchService,
        private toast: ToastService,
        private strings: StringService,
        private printer: PrintService) {
        this.isPrinting = false;
        this.printQueue = [];
    }

    ngOnInit() {
        this.printer.onPrintRequest$.subscribe(
            printReq => this.handlePrintRequest(printReq));

        this.htmlContainer =
            this.renderer.selectRootElement('#eg-print-html-container');

        this.serverStore.getItem('eg.hatch.enable.printing')
            .then(use => this.useHatch = use);
    }

    handlePrintRequest(printReq: PrintRequest) {

        if (this.isPrinting) {
            // Avoid print collisions by queuing requests as needed.
            this.printQueue.push(printReq);
            return;
        }

        this.isPrinting = true;

        this.applyTemplate(printReq).then(() => {
            // Give templates a chance to render before printing
            setTimeout(() => {
                this.dispatchPrint(printReq);
                this.reset();
            });
        });
    }

    applyTemplate(printReq: PrintRequest): Promise<any> {

        if (printReq.template) {
            // Local Angular template.
            this.template = printReq.template;
            this.context = {$implicit: printReq.contextData};
            return Promise.resolve();
        }

        let promise;

        // Precompiled text
        if (printReq.text) {
            promise = Promise.resolve();

        } else if (printReq.templateName || printReq.templateId) {
            // Server-compiled template

            promise = this.printer.compileRemoteTemplate(printReq).then(
                response => {
                    printReq.text = response.content;
                    printReq.contentType = response.contentType;
                },
                err => {

                    if (err && err.notFound) {

                        this.strings.interpolate(
                            'eg.print.template.not_found',
                            {name: printReq.templateName}
                        ).then(msg => this.toast.danger(msg));

                    } else {

                        console.error('Print generation failed', printReq);

                        this.strings.interpolate(
                            'eg.print.template.error',
                            {name: printReq.templateName, id: printReq.templateId}
                        ).then(msg => this.toast.danger(msg));
                    }

                    return Promise.reject(new Error(
                        'Error compiling server-hosted print template'));
                }
            );

        } else {
            console.error('Cannot find template', printReq);
            return Promise.reject(new Error('Cannot find print template'));
        }

        return promise.then(() => {

            // Insert HTML into the browser DOM for in-browser printing.
            if (printReq.text && !this.useHatch()) {

                if (printReq.contentType === 'text/plain') {
                // Wrap text/plain content in pre's to prevent
                // unintended html formatting.
                    printReq.text = `<pre>${printReq.text}</pre>`;
                }

                this.htmlContainer.innerHTML = printReq.text;
            }
        });
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

        if (this.useHatch) {
            this.printViaHatch(printReq);
        } else {
            // Here the needed HTML is already in the page.
            window.print();
        }
    }

    printViaHatch(printReq: PrintRequest) {

        // Send a full HTML document to Hatch
        let html = printReq.text;
        if (printReq.contentType === 'text/html') {
            html = `<html><body>${printReq.text}</body></html>`;
        }

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

