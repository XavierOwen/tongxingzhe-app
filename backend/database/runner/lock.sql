-- 同一数据库一次只允许一个迁移器前进；锁在本事务结束时自动释放。
SELECT pg_advisory_xact_lock(
  hashtextextended('tongxingzhe_schema_migrations', 0)
);
