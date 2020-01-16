import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {CatalogService} from './catalog.service';
import {BasketService} from './basket.service';
import {CatalogUrlService} from './catalog-url.service';
import {BibRecordService} from './bib-record.service';
import {UnapiService} from './unapi.service';
import {MarcHtmlComponent} from './marc-html.component';
import {BibDisplayFieldComponent} from './bib-display-field.component';


@NgModule({
    declarations: [
        MarcHtmlComponent,
        BibDisplayFieldComponent
    ],
    imports: [
        EgCommonModule
    ],
    exports: [
        MarcHtmlComponent,
        BibDisplayFieldComponent
    ],
    providers: [
        CatalogService,
        CatalogUrlService,
        UnapiService,
        BibRecordService,
        BasketService
    ]
})

export class CatalogCommonModule {}
