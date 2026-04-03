import { TestBed } from '@angular/core/testing';
import { AuthService } from '@eg/core/auth.service';
import { IdlService } from '@eg/core/idl.service';
import { NetService } from '@eg/core/net.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { StoreService } from '@eg/core/store.service';
import { MockGenerators } from 'test_data/mock_generators';
import { BucketService } from './bucket.service';

describe('BucketService', () => {
    describe('addBibsToRecordBucket()', () => {
        it('resolves to an array of ids', async () => {
            TestBed.configureTestingModule({providers: [
                { provide: BucketService },
                { provide: IdlService,
                    useValue: {
                        create: () => {
                            return {
                                bucket: () => {},
                                target_biblio_record_entry: () => {}
                            };
                        }
                    }
                },
                {
                    provide: PcrudService,
                    useValue: MockGenerators.pcrudService({create: [
                        MockGenerators.idlObject({id: 123}),
                        MockGenerators.idlObject({id: 456})
                    ]})
                },
                {provide: StoreService, useValue: {}},
                {provide: NetService, useValue: {}},
                {provide: AuthService, useValue: {}}
            ]});

            const service = TestBed.inject(BucketService);
            const result = await service.addBibsToRecordBucket(1, [2, 3]);
            expect(result).toEqual([123, 456]);
        });
    });
});
