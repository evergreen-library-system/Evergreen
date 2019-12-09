importScripts('/js/ui/default/staff/build/js/lovefield.min.js');

// Collection of schema tracking objects.
var schemas = {};

// Create the DB schema / tables
// synchronous
function createSchema(schemaName) {
    if (schemas[schemaName]) return;

    var meta = lf.schema.create(schemaName, 2);
    schemas[schemaName] = {name: schemaName, meta: meta};

    switch (schemaName) {
        case 'cache':
            createCacheTables(meta);
            break;
        case 'offline':
            createOfflineTables(meta);
            break;
        default:
            console.error('No schema definition for ' + schemaName);
    }
}

// Offline cache tables are globally available in the staff client
// for on-demand caching.
function createCacheTables(meta) {

    meta.createTable('Setting').
        addColumn('name', lf.Type.STRING).
        addColumn('value', lf.Type.STRING).
        addPrimaryKey(['name']);

    meta.createTable('Object').
        addColumn('type', lf.Type.STRING).         // class hint
        addColumn('id', lf.Type.STRING).           // obj id
        addColumn('object', lf.Type.OBJECT).
        addPrimaryKey(['type','id']);

    meta.createTable('CacheDate').
        addColumn('type', lf.Type.STRING).          // class hint
        addColumn('cachedate', lf.Type.DATE_TIME).  // when was it last updated
        addPrimaryKey(['type']);

    meta.createTable('StatCat').
        addColumn('id', lf.Type.INTEGER).
        addColumn('value', lf.Type.OBJECT).
        addPrimaryKey(['id']);
}

// Offline transaction and block list tables.  These can be bulky and
// are only used in the offline UI.
function createOfflineTables(meta) {

    meta.createTable('OfflineXact').
        addColumn('seq', lf.Type.INTEGER).
        addColumn('value', lf.Type.OBJECT).
        addPrimaryKey(['seq'], true);

    meta.createTable('OfflineBlocks').
        addColumn('barcode', lf.Type.STRING).
        addColumn('reason', lf.Type.STRING).
        addPrimaryKey(['barcode']);
}

// Connect to the database for a given schema
function connect(schemaName) {

    var schema = schemas[schemaName];
    if (!schema) {
        return Promise.reject('createSchema(' +
            schemaName + ') call required');
    }

    if (schema.db) { // already connected.
        return Promise.resolve();
    }

    return new Promise(function(resolve, reject) {
        try {
            schema.meta.connect().then(
                function(db) {
                    schema.db = db;
                    resolve();
                },
                function(err) {
                    reject('Error connecting to schema ' +
                        schemaName + ' : ' + err);
                }
            );
        } catch (E) {
            reject('Error connecting to schema ' + schemaName + ' : ' + E);
        }
    });
}

function getTableInfo(schemaName, tableName) {
    var schema = schemas[schemaName];
    var info = {};

    if (!schema) {
        info.error = 'createSchema(' + schemaName + ') call required';

    } else if (!schema.db) {
        info.error = 'connect(' + schemaName + ') call required';

    } else {
        info.schema = schema;
        info.table = schema.meta.getSchema().table(tableName);

        if (!info.table) {
            info.error = 'no such table ' + tableName;
        }
    }

    return info;
}

// Returns a promise resolved with true on success
// Note insert .exec() returns rows, but that can get bulky on large
// inserts, hence the boolean return;
function insertOrReplace(schemaName, tableName, objects) {

    var info = getTableInfo(schemaName, tableName);
    if (info.error) { return Promise.reject(info.error); }

    var rows = objects.map(function(r) { return info.table.createRow(r) });
    return info.schema.db.insertOrReplace().into(info.table)
        .values(rows).exec().then(function() { return true; });
}

// Returns a promise resolved with true on success
// Note insert .exec() returns rows, but that can get bulky on large
// inserts, hence the boolean return;
function insert(schemaName, tableName, objects) {

    var info = getTableInfo(schemaName, tableName);
    if (info.error) { return Promise.reject(info.error); }

    var rows = objects.map(function(r) { return info.table.createRow(r) });
    return info.schema.db.insert().into(info.table)
        .values(rows).exec().then(function() { return true; });
}

// Returns rows where the selected field equals the provided value.
function selectWhereEqual(schemaName, tableName, field, value) {

    var info = getTableInfo(schemaName, tableName);
    if (info.error) { return Promise.reject(info.error); }

    return info.schema.db.select().from(info.table)
        .where(info.table[field].eq(value)).exec();
}

// Returns rows where the selected field equals the provided value.
function selectWhereIn(schemaName, tableName, field, value) {

    var info = getTableInfo(schemaName, tableName);
    if (info.error) { return Promise.reject(info.error); }

    return info.schema.db.select().from(info.table)
        .where(info.table[field].in(value)).exec();
}

// Returns all rows in the selected table
function selectAll(schemaName, tableName) {

    var info = getTableInfo(schemaName, tableName);
    if (info.error) { return Promise.reject(info.error); }

    return info.schema.db.select().from(info.table).exec();
}

// Deletes all rows in the selected table.
function deleteAll(schemaName, tableName) {

    var info = getTableInfo(schemaName, tableName);
    if (info.error) { return Promise.reject(info.error); }

    return info.schema.db.delete().from(info.table).exec();
}

// Delete rows from selected table where field equals value
function deleteWhereEqual(schemaName, tableName, field, value) {
    var info = getTableInfo(schemaName, tableName);
    if (info.error) { return Promise.reject(info.error); }

    return info.schema.db.delete().from(info.table)
        .where(info.table[field].eq(value)).exec();
}

// Resolves to true if the selected table contains any rows.
function hasRows(schemaName, tableName) {

    var info = getTableInfo(schemaName, tableName);
    if (info.error) { return Promise.reject(info.error); }

    return info.schema.db.select().from(info.table).limit(1).exec()
        .then(function(rows) { return rows.length > 0 });
}


// Prevent parallel block list building calls, since it does a lot.
var buildingBlockList = false;

// Fetches the offline block list and rebuilds the offline blocks
// table from the new data.
function populateBlockList(authtoken) {

    if (buildingBlockList) {
        return Promise.reject('Block list download already in progress');
    }

    buildingBlockList = true;

    var url = '/standalone/list.txt?ses=' + 
        authtoken + '&' + new Date().getTime();

    console.debug('Fetching offline block list from: ' + url);

    return new Promise(function(resolve, reject) {

        var xhttp = new XMLHttpRequest();
        xhttp.onreadystatechange = function() {
            if (this.readyState === 4) {
                if (this.status === 200) {
                    var blocks = xhttp.responseText;
                    var lines = blocks.split('\n');
                    insertOfflineBlocks(lines).then(
                        function() {
                            buildingBlockList = false;
                            resolve();
                        },
                        function(e) {
                            buildingBlockList = false;
                            reject(e);
                        }
                    );
                } else {
                    buildingBlockList = false;
                    reject('Error fetching offline block list');
                }
            }
        };

        xhttp.open('GET', url, true);
        xhttp.send();
    });
}

// Rebuild the offline blocks table with the provided blocks, one per line.
function insertOfflineBlocks(lines) {
    console.debug('Fetched ' + lines.length + ' blocks');

    // Clear the table first
    return deleteAll('offline', 'OfflineBlocks').then(
        function() { 

            console.debug('Cleared existing offline blocks');

            // Create a single batch of rows for insertion.
            var chunks = [];
            var currentChunk = [];
            var chunkSize = 10000;
            var seen = {bc: {}}; // for easier delete

            chunks.push(currentChunk);
            lines.forEach(function(line) {
                // slice/substring instead of split(' ') to handle barcodes
                // with trailing spaces.
                var barcode = line.slice(0, -2);
                var reason = line.substring(line.length - 1);
                
                // Trim duplicate barcodes, since only one version of each 
                // block per barcode is kept in the offline block list
                if (seen.bc[barcode]) return;
                seen.bc[barcode] = true;

                if (currentChunk.length >= chunkSize) {
                    currentChunk = [];
                    chunks.push(currentChunk);
                }

                currentChunk.push({barcode: barcode, reason: reason});
            });

            delete seen.bc; // allow this hunk to be reclaimed

            console.debug('offline data broken into ' + 
                chunks.length + ' chunks of size ' + chunkSize);

            return new Promise(function(resolve, reject) {
                insertOfflineChunks(chunks, 0, resolve, reject);
            });
        }, 

        function(err) {
            console.error('Error clearing offline table: ' + err);
            return Promise.reject(err);
        }
    );
}

function insertOfflineChunks(chunks, offset, resolve, reject) {
    var chunk = chunks[offset];
    if (!chunk || chunk.length === 0) {
        console.debug('Block list store completed');
        return resolve();
    }

    insertOrReplace('offline', 'OfflineBlocks', chunk).then(
        function() { 
            console.debug('Block list successfully stored chunk ' + offset);
            insertOfflineChunks(chunks, offset + 1, resolve, reject);
        },
        reject
    );
}


// Routes inbound WebWorker message to the correct handler.
// Replies include the original request plus added response info.
function dispatchRequest(port, data) {

    console.debug('Lovefield worker received', 
        'action=' + (data.action || ''), 
        'schema=' + (data.schema || ''), 
        'table=' + (data.table || ''),
        'field=' + (data.field || ''),
        'value=' + (data.value || '')
    );

    function replySuccess(result) {
        data.status = 'OK';
        data.result = result;
        port.postMessage(data);
    }

    function replyError(err) {
        console.error('shared worker replying with error', err);
        data.status = 'ERR';
        port.postMessage(data);
    }

    switch (data.action) {
        case 'createSchema':
            // Schema creation is synchronous and apparently throws
            // no exceptions, at least until connect() is called.
            createSchema(data.schema);
            replySuccess();
            break;

        case 'connect':
            connect(data.schema).then(replySuccess, replyError);
            break;

        case 'insertOrReplace':
            insertOrReplace(data.schema, data.table, data.rows)
                .then(replySuccess, replyError);
            break;

        case 'insert':
            insert(data.schema, data.table, data.rows)
                .then(replySuccess, replyError);
            break;

        case 'selectWhereEqual':
            selectWhereEqual(data.schema, data.table, data.field, data.value)
                .then(replySuccess, replyError);
            break;

        case 'selectWhereIn':
            selectWhereIn(data.schema, data.table, data.field, data.value)
                .then(replySuccess, replyError);
            break;

        case 'selectAll':
            selectAll(data.schema, data.table).then(replySuccess, replyError);
            break;

        case 'deleteAll':
            deleteAll(data.schema, data.table).then(replySuccess, replyError);
            break;

        case 'deleteWhereEqual':
            deleteWhereEqual(data.schema, data.table, data.field, data.value)
                .then(replySuccess, replyError);
            break;

        case 'hasRows':
            hasRows(data.schema, data.table).then(replySuccess, replyError);
            break;

        case 'populateBlockList':
            populateBlockList(data.authtoken).then(replySuccess, replyError);
            break;

        default:
            console.error('no such DB action ' + data.action);
    }
}

onconnect = function(e) {
    var port = e.ports[0];
    port.addEventListener('message',
        function(e) {dispatchRequest(port, e.data);});
    port.start();
}



