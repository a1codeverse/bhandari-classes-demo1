-- Explicit grants + indexes for the Bhandari Classes LMS.
-- Row Level Security remains the final authorization layer.
grant usage on schema public to authenticated;
grant select on public.profiles to authenticated;
grant update(full_name, avatar_url) on public.profiles to authenticated;
grant select, insert, update, delete on public.courses to authenticated;
grant select, insert, update, delete on public.lessons to authenticated;
grant select, insert, update, delete on public.enrollments to authenticated;
grant select, insert, update, delete on public.payments to authenticated;
grant select, insert, update, delete on public.quizzes to authenticated;
grant select, insert, update, delete on public.quiz_questions to authenticated;
grant select, insert, update, delete on public.quiz_attempts to authenticated;
grant select, insert, update, delete on public.daily_questions to authenticated;
grant select on public.audit_logs to authenticated;
create index if not exists profiles_role_idx on public.profiles(role);
create index if not exists courses_published_created_idx on public.courses(is_published, created_at desc);
create index if not exists lessons_course_published_sort_idx on public.lessons(course_id, is_published, sort_order, created_at);
create index if not exists enrollments_user_status_expiry_idx on public.enrollments(user_id, status, expires_at);
create index if not exists enrollments_course_user_status_idx on public.enrollments(course_id, user_id, status);
create index if not exists payments_user_status_created_idx on public.payments(user_id, status, created_at desc);
create index if not exists quiz_questions_quiz_sort_idx on public.quiz_questions(quiz_id, sort_order);
create index if not exists quiz_attempts_user_quiz_submitted_idx on public.quiz_attempts(user_id, quiz_id, submitted_at desc);
create index if not exists daily_questions_publish_idx on public.daily_questions(is_published, publish_at desc);
