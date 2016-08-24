BEGIN;

SELECT evergreen.upgrade_deps_block_check('0995', :eg_version);

INSERT INTO rating.badge (name, description, scope, weight, horizon_age, importance_age, importance_interval, importance_scale, recalc_interval, popularity_parameter, percentile)
   VALUES('Top Holds Over Last 5 Years', 'The top 97th percentile for holds requested over the past five years on all materials. More weight is given to holds requested over the last year, with importance decreasing for every year after that.', 1, 3, '5 years', '5 years', '1 year', 2, '1 day', 2, 97);

COMMIT;
