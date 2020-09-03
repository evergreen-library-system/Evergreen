BEGIN;

SELECT evergreen.upgrade_deps_block_check('1219', :eg_version);

CREATE VIEW acq.li_state_label AS
  SELECT *
  FROM (VALUES
          ('new', 'New'),
          ('selector-ready', 'Selector-Ready'),
          ('order-ready', 'Order-Ready'),
          ('approved', 'Approved'),
          ('pending-order', 'Pending-Order'),
          ('on-order', 'On-Order'),
          ('received', 'Received'),
          ('cancelled', 'Cancelled')
       ) AS t (id,label);

CREATE VIEW acq.po_state_label AS
  SELECT *
  FROM (VALUES
          ('new', 'New'),
          ('pending', 'Pending'), 
          ('on-order', 'On-Order'),
          ('received', 'Received'),
          ('cancelled', 'Cancelled')
       ) AS t (id,label);

COMMIT;
