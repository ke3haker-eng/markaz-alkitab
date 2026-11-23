اختبارات اختيارية (للمطوّر فقط — لا تُنشر مع التطبيق):

1) SQL على PostgreSQL 16 + pgcrypto: أنشئ قاعدة، شغّل tests/sql/baseline_noroles.sql (أو baseline_enum.sql لحالة ENUM) ثم
   sql/01_security_setup.sql ثم 03_part1..6 ثم 04_part1..3 ثم tests/sql/t_functional.sql و t_competitions.sql و t_chat2.sql
   (بين اختبار وآخر فرّغ الجداول كما في أول كل ملف اختبار).
2) تكامل: npm i jsdom pg ، قاعدة باسم t3 مبنية من tests/sql/baseline_e2e.sql + 01 + 02 + 03_part1..6 + 04_part1..3 (انظر الاتصال في e2e_lib.js)
   ثم: node e2e.js && node e2e2.js && node e2e3.js && node e2e4.js && node e2e5.js
   (التطبيق يعمل داخل jsdom مع عميل Supabase مزيّف يتصل بقاعدة PostgreSQL بدور anon).
