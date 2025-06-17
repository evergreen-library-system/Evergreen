import { Injectable } from '@angular/core';
import { Router, ActivatedRoute } from '@angular/router';
import { BucketStateService } from '@eg/staff/share/buckets/bucket-state.service';
import { RecordBucketService } from './record-bucket.service';
import { AuthService } from '@eg/core/auth.service';
import { IdlService } from '@eg/core/idl.service';
import { NetService } from '@eg/core/net.service';
import { PcrudService } from '@eg/core/pcrud.service';
import { BucketConfigService } from '@eg/staff/share/buckets/bucket-config.service';
import { BucketService } from '@eg/staff/share/buckets/bucket.service';

@Injectable()
export class RecordBucketStateService extends BucketStateService {
  constructor(
    router: Router,
    auth: AuthService,
    idl: IdlService,
    pcrud: PcrudService,
    net: NetService,
    bucketService: BucketService,
    bucketConfig: BucketConfigService,
    private recordBucketService: RecordBucketService
  ) {
    super(router, auth, idl, pcrud, net, bucketService, bucketConfig);
    
    // Initialize the state service for the 'biblio' bucket class with caching
    this.initialize('biblio', {
      defaultView: 'user',
      baseRoute: '',
      cacheTimeout: 5 * 60 * 1000 // 5 minutes cache timeout
    });
  }
}