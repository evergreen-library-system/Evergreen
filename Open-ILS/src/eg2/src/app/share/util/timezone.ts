import * as moment from 'moment';

export class Timezone {
    values() {
        return moment.tz.names();
    }
}
