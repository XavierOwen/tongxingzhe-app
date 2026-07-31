-- synthetic fixture：在回滚事务内证明部署身份能建表、runtime 只能做获准 DML。
-- 这里没有真实姓名、邮箱、位置或接触资料。
BEGIN;

CREATE TABLE app_data.synthetic_runtime_probe (
  probe_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  label text NOT NULL CHECK (length(label) > 0)
);

SET LOCAL ROLE tongxingzhe_runtime;

INSERT INTO app_data.synthetic_runtime_probe (label)
VALUES ('synthetic-ci-fixture');

DO $fixture$
BEGIN
  IF (
    SELECT count(*)
    FROM app_data.synthetic_runtime_probe
    WHERE label = 'synthetic-ci-fixture'
  ) <> 1 THEN
    RAISE EXCEPTION 'runtime probe did not round-trip exactly one row';
  END IF;
END
$fixture$;

ROLLBACK;
