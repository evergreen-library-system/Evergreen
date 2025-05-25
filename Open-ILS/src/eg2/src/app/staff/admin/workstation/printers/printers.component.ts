import {Component, OnInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute} from '@angular/router';
import {from, concatMap} from 'rxjs';
import {ServerStoreService} from '@eg/core/server-store.service';
import {NetService} from '@eg/core/net.service';
import {PermService} from '@eg/core/perm.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {EventService} from '@eg/core/event.service';
import {HatchService, PrintContext, PrintConfig, PRINT_CONTEXTS} from '@eg/core/hatch.service';
import {PrintService, PrintRequest} from '@eg/share/print/print.service';
import {NgbNavChangeEvent} from '@ng-bootstrap/ng-bootstrap';
import {StringComponent} from '@eg/share/string/string.component';

@Component({
    templateUrl: 'printers.component.html'
})
export class PrintersComponent implements OnInit {

    printers: any[];
    printerName: string;
    context: PrintContext = 'default';
    showTestView = false;
    printConfigs: {[ctx: string]: PrintConfig} = {};
    printerOptions: any = {};
    useHatchPrinting: boolean = null;
    testTab = 'text';

    marginLeft: number;
    marginRight: number;
    marginTop: number;
    marginBottom: number;

    textPrintContent = '';
    htmlPrintContent = '';

    testText = `1234567890

12345678901234567890

123456789012345678901234567890

1234567890123456789012345678901234567890

12345678901234567890123456789012345678901234567890

12345678901234567890123456789012345678901234567890123456790`;

    testHtml = `<div style="padding: 10px;">
  <style>p { color: var(--bs-blue-700) }</style>
  <h2>Test HTML Print</h2>
  <br/>
  <p><b>More Content</b></p>
  <br/>
</div>`;


    @ViewChild('fileWriter') private fileWriter: StringComponent;
    @ViewChild('browserPrinting') private browserPrinting: StringComponent;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private evt: EventService,
        private net: NetService,
        private serverStore: ServerStoreService,
        private auth: AuthService,
        private org: OrgService,
        private hatch: HatchService,
        private printer: PrintService,
        private perm: PermService
    ) {}

    ngOnInit() {

        this.serverStore.getItem('eg.hatch.enable.printing')
            .then(use => this.useHatchPrinting = Boolean(use));

        this.hatch.getPrinters()
            .then(printers => {

                this.printers = printers;

                return from(PRINT_CONTEXTS).pipe(concatMap(ctx => {
                    return from(
                        this.getPrintConfig(ctx).then(conf => {
                            if (conf) {
                                this.printConfigs[ctx] = conf;
                            } else {
                                this.resetConfig(ctx);
                            }
                        })
                    );
                })).toPromise();
            })
            .then(_ => this.setContext('default'));
    }

    hatchConnected(): boolean {
        return this.hatch.isAvailable;
    }

    hatchPrintChange(val: boolean) {
        this.serverStore.setItem('eg.hatch.enable.printing', val);
    }

    getPrinterLabel(name: string): string {
        switch (name) {
            case 'hatch_file_writer':
                return this.fileWriter ? this.fileWriter.text : '';
            case 'hatch_browser_printing':
                return this.browserPrinting ? this.browserPrinting.text : '';
            default:
                if (this.printers) {
                    const p = this.printers.filter(p2 => p2.name === name)[0];
                    return p ? p.name : '';
                } else {
                    return '';
                }
        }
    }

    virtualPrinter(): boolean {
        const conf = this.printConfigs[this.context];
        return conf && (
            conf.printer === 'hatch_file_writer' ||
            conf.printer === 'hatch_browser_printing'
        );
    }

    setContext(c: PrintContext) {
        this.context = c;
        this.showTestView = false;

        const conf = this.printConfigs[c as string];
        if (conf) { this.setPrinter(conf.printer); }
    }

    getPrinterOptions(name: string): Promise<any> {
        return this.hatch.getPrinterOptions(name).then(ops => {
            this.printerOptions = ops;
        });
    }

    resetConfig(c: PrintContext) {
        this.printConfigs[c] = {
            context: 'default',
            printer: '',
            autoMargins: true,
            allPages: true,
            pageRanges: []
        };
    }

    saveConfig(context: PrintContext): Promise<any> {
        return this.setPrintConfig(context, this.printConfigs[context]);
    }

    setPrinter(name: string, reset?: boolean): Promise<any> {
        if (reset) { this.resetConfig(this.context); }

        this.printerName = name;
        this.printConfigs[this.context].printer = name;

        return this.getPrinterOptions(name);
    }

    testPrint(withDialog: boolean) {
        const req: PrintRequest = {
            printContext: this.context,
            showDialog: withDialog,
            contentType: this.testTab === 'text' ? 'text/plain' : 'text/html',
            text: this.testTab === 'text' ? this.testText : this.testHtml
        };

        this.printer.print(req);
    }

    useFileWriter(): boolean {
        return (
            this.printConfigs[this.context] &&
            this.printConfigs[this.context].printer === 'hatch_file_writer'
        );
    }

    useBrowserPrinting(): boolean {
        return (
            this.printConfigs[this.context] &&
            this.printConfigs[this.context].printer === 'hatch_browser_printing'
        );
    }

    beforeTabChange(evt: NgbNavChangeEvent) {
        if (evt.nextId === 'test') {
            this.showTestView = true;
        } else {
            this.showTestView = false;
            this.setContext(evt.nextId as PrintContext);
        }
    }

    beforeTestTabChange(evt: NgbNavChangeEvent) {
        this.testTab = evt.nextId;
    }

    setPrintConfig(context: PrintContext, config: PrintConfig): Promise<any> {
        return this.serverStore.setItem('eg.print.config.' + context, config);
    }

    getPrintConfig(context: PrintContext): Promise<PrintConfig> {
        return this.serverStore.getItem(`eg.print.config.${context}`);
    }
}


