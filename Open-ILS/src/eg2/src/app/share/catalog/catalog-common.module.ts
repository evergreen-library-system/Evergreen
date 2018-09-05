import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {CatalogService} from './catalog.service';
import {CatalogUrlService} from './catalog-url.service';
import {BibRecordService} from './bib-record.service';
import {UnapiService} from './unapi.service';
import {MarcHtmlComponent} from './marc-html.component';


@NgModule({
    declarations: [
        MarcHtmlComponent
    ],
    imports: [
        EgCommonModule
    ],
    exports: [
        MarcHtmlComponent
    ],
    providers: [
        CatalogService,
        CatalogUrlService,
        UnapiService,
        BibRecordService
    ]
})

export class CatalogCommonModule {}
