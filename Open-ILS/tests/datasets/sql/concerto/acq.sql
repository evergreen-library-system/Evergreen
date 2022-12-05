
-- note: using hard-coded ID's for most objects or this 
-- would require 3 times as much SQL.

INSERT INTO acq.funding_source (id, owner, name, currency_type, code) VALUES
    (1, 1, 'LSTA', 'USD', 'LSTA'),
    (2, 2, 'State', 'USD', 'ST'),
    (3, 4, 'Foundation', 'USD', 'FNTN');

SELECT SETVAL('acq.funding_source_id_seq'::TEXT, 3);

INSERT INTO acq.funding_source_credit (amount, funding_source) VALUES
    ('10000',1), ('5000', 2), ('5000', 3);

INSERT INTO acq.fund (id, org, year, currency_type, name, code) VALUES
    (1,  1, EXTRACT(year FROM now()), 'USD', 'Adult', 'AD'),
    (2,  2, EXTRACT(year FROM now()), 'USD', 'AV', 'AV'),
    (3,  3, EXTRACT(year FROM now()), 'USD', 'AV', 'AV'),
    (4,  4, EXTRACT(year FROM now()), 'USD', 'Juvenile', 'JUV'),
    (5,  5, EXTRACT(year FROM now()), 'USD', 'Young Adult', 'YA'),
    (6,  6, EXTRACT(year FROM now()), 'USD', 'Juvenile', 'JUV'),
    (7,  7, EXTRACT(year FROM now()), 'USD', 'Young Adult', 'YA'),
    (8,  2, EXTRACT(year FROM now()), 'USD', 'Reference', 'RF'),
    (9,  2, EXTRACT(year FROM now()), 'USD', 'Fiction Print', 'FP'),
    (10, 2, EXTRACT(year FROM now()), 'USD', 'Fiction Non-Print', 'FNP'),
    (11, 3, EXTRACT(year FROM now()), 'USD', 'Fiction Print', 'FP'),
    (12, 3, EXTRACT(year FROM now()), 'USD', 'Fiction Non-Print', 'FNP');

SELECT SETVAL('acq.fund_id_seq'::TEXT, 12);

INSERT INTO acq.fund_allocation 
    (funding_source, fund, amount, allocator) VALUES
    (1, 1,  '3000', 1),
    (1, 2,  '3000', 1),
    (1, 3,  '3000', 1),
    (2, 9,  '500',  1),
    (2, 10, '500',  1),
    (3, 4,  '2000', 1);

INSERT INTO acq.provider 
    (id, name, owner, currency_type, code, holding_tag, san) VALUES
    (1, 'Ingram', 1, 'USD', 'INGRAM', '970', '1697978'),
    (2, 'Brodart', 2, 'USD', 'BRODART', '970', '1697684'),
    (3, 'Baker & Taylor', 1, 'USD', 'BT', '970', '3349659'),
    (4, 'Initech', 4, 'USD', 'IT', '970', '1001001');

SELECT SETVAL('acq.provider_id_seq'::TEXT, 4);

INSERT INTO acq.provider_holding_subfield_map (provider, name, subfield) VALUES
    (1, 'quantity',         'q'),
    (1, 'estimated_price',  'p'),
    (1, 'owning_lib',       'o'),
    (1, 'call_number',      'n'),
    (1, 'fund_code',        'f'),
    (1, 'circ_modifier',    'm'),
    (1, 'note',             'z'),
    (1, 'copy_location',    'l'),
    (1, 'barcode',          'b'),
    (1, 'collection_code',  'c');

-- give every provider the same holding subfield maps
INSERT INTO acq.provider_holding_subfield_map (provider, name, subfield)
    SELECT 2, name, subfield
        FROM acq.provider_holding_subfield_map
        WHERE provider = 1;

INSERT INTO acq.provider_holding_subfield_map (provider, name, subfield)
    SELECT 3, name, subfield
        FROM acq.provider_holding_subfield_map
        WHERE provider = 1;

INSERT INTO acq.provider_holding_subfield_map (provider, name, subfield)
    SELECT 4, name, subfield
        FROM acq.provider_holding_subfield_map
        WHERE provider = 1;

INSERT INTO acq.purchase_order (id, owner, creator, 
    editor, ordering_agency, provider, state, order_date) VALUES
    (1, 1, 1, 1, 4, 1, 'pending', NULL),
    (2, 1, 1, 1, 4, 2, 'on-order', NOW());

SELECT SETVAL('acq.purchase_order_id_seq'::TEXT, 2);

INSERT INTO acq.lineitem (id, creator, editor, selector, 
        provider, purchase_order, state, cancel_reason, 
        estimated_unit_price, eg_bib_id, marc) VALUES
    (1, 1, 1, 1, 1, 1, 'new', NULL, '25.00', 1,
        (SELECT marc FROM biblio.record_entry WHERE id = 1)),
    (2, 1, 1, 1, 1, 1, 'new', NULL, '15.00', 2,
        (SELECT marc FROM biblio.record_entry WHERE id = 2)),
    (3, 1, 1, 1, 1, 2, 'on-order', NULL, '12.00', 3,
        (SELECT marc FROM biblio.record_entry WHERE id = 3)),
    (4, 1, 1, 1, 1, 2, 'cancelled', 1283, '18.50', 4,
        (SELECT marc FROM biblio.record_entry WHERE id = 4)),
    (5, 1, 1, 1, 1, 2, 'cancelled', 1, '22.00', 5,
        (SELECT marc FROM biblio.record_entry WHERE id = 5));

SELECT SETVAL('acq.lineitem_id_seq'::TEXT, 5);

INSERT INTO acq.fund_debit (id, fund, origin_amount, 
    origin_currency_type, amount, debit_type) VALUES
    (1, 1, '12.00', 'USD', '12.00', 'purchase'),
    (2, 1, '12.00', 'USD', '12.00', 'purchase'),
    (3, 1, '18.50', 'USD', '12.00', 'purchase');

SELECT SETVAL('acq.fund_debit_id_seq'::TEXT, 4);

INSERT INTO acq.lineitem_detail (lineitem, fund, fund_debit, eg_copy_id,
   barcode, cn_label, owning_lib, location, cancel_reason) VALUES
   (3, 1, 1, 3, 'ACQ0001', 'ACQ001', 4, 113, NULL),
   (3, 1, 2, 103, 'ACQ0002', 'ACQ002', 5, 125, NULL),
   (4, 1, 3, 4, 'ACQ0002', 'ACQ002', 4, 118, 1),
   (5, 1, NULL, 5, 'ACQ0002', 'ACQ002', 4, 123, 1283);


