اختبارات اختيارية (للمطوّر فقط — لا تُنشر مع التطبيق):

1) SQL:   PostgreSQL 16 + pgcrypto. أنشئ قاعدة، شغّل baseline.sql ثم sql/01_security_setup.sql ثم sql/tests/t_functional.sql
2) تكامل: npm i jsdom pg ، قاعدة بيانات باسم t3 مبنية من baseline_e2e.sql + 01 + 02 (انظر المسار والاتصال في e2e_lib.js)
   ثم: node e2e.js && node e2e2.js && node e2e3.js
   (التطبيق يعمل داخل jsdom مع عميل Supabase مزيّف يتصل بقاعدة PostgreSQL بدور anon).
