# Bhandari Classes — production foundation

This branch contains a Next.js application foundation. The existing GitHub Pages demo remains on the main branch and is not overwritten.

## Implemented
- Next.js App Router public landing page and responsive layout.
- Supabase SSR email/password sign-up and sign-in.
- Student dashboard that only lists active course enrollments.
- Admin-only course creation and publish/unpublish controls.
- Admin-only browser-to-private-R2 video upload using 10-minute signed PUT URLs.
- Server verifies the uploaded object in R2 before creating a lesson record.
- Playback route checks the logged-in user and active enrollment before issuing a 15-minute HMAC media token.
- Cloudflare Worker streams private MP4/WebM from R2 with HTTP byte-range support.
- Player refreshes short-lived playback tokens and displays a moving student watermark.
- SQL schema with RLS for profiles, courses, lessons, enrollments, payments, quizzes, attempts, daily questions and audit logs.
- Basic security response headers.

## Important limitations
This is a deployable LMS foundation, not yet a finished commercial LMS.

- Razorpay order creation, payment signature verification and idempotent webhooks are NOT implemented. Do not take real course payments yet.
- Enrollments currently need to be created by an admin until the verified payment webhook is built.
- Quiz builder, daily-question editor, live-class scheduling, refund workflow, reports, notifications and visual website page editor are not yet implemented.
- R2 playback uses private MP4/WebM byte-range delivery, expiring HMAC tokens and watermarks. It is NOT DRM and cannot guarantee screenshot or screen-recording prevention.
- This Worker is not an adaptive-bitrate HLS transcoding pipeline and has not been load-tested for 500 or 10,000 simultaneous viewers.
- Single-part browser upload is capped at 4GB. Multipart upload is needed for larger files.
- The media token is a bearer token valid for 15 minutes. Treat it as sensitive; use HTTPS and never put it into analytics or logs.

## 1. Deploy the Next.js app to Vercel
1. Import GitHub repository a1codeverse/bhandari-classes-demo1 into Vercel.
2. Select branch production as the Production Branch. Framework preset: Next.js. Root Directory: repository root.
3. Add the environment variables from .env.example in Vercel Project Settings → Environment Variables.
4. Deploy. The GitHub Pages demo on main remains separate; Vercel serves the production branch.

## 2. Create the Supabase project
1. Create a Supabase project. Add the Project URL and Publishable Key as NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY.
2. Apply both SQL files in filename order in the Supabase SQL Editor: 0001_lms.sql followed by 0002_permissions_indexes.sql.
3. In Authentication → URL Configuration, set the Site URL to your Vercel/custom domain and add the login redirect URL.
4. Create the owner account at /signup. Then promote only that verified owner account in SQL Editor:

    update public.profiles
    set role = 'admin'
    where id = (select id from auth.users where email = 'OWNER_EMAIL_HERE');

Never expose a public admin-signup option.

## 3. Create the private Cloudflare R2 bucket
1. Cloudflare Dashboard → R2 → create a bucket named bhandari-private-videos.
2. Keep the bucket PRIVATE. Do not enable public bucket access.
3. Create R2 API credentials with Object Read & Write, restricted to this bucket only.
4. Add R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY and R2_BUCKET_NAME to Vercel.
5. Apply cloudflare/r2-cors.json after replacing example origins with the exact Vercel and production domain origins. Allow only domains you control.

## 4. Deploy the Cloudflare media Worker
1. Install Wrangler: npm install -g wrangler.
2. In the cloudflare folder, run npx wrangler login and npx wrangler deploy.
3. Set a random secret of at least 32 characters in Cloudflare:

    npx wrangler secret put MEDIA_TOKEN_SECRET

4. Put the exact same MEDIA_TOKEN_SECRET in Vercel. Never expose it as a NEXT_PUBLIC variable.
5. Set CORS_ORIGIN in cloudflare/wrangler.toml to your exact website origin, then redeploy the Worker.
6. Set MEDIA_WORKER_URL in Vercel to the Worker HTTPS origin, for example https://bhandari-private-media.ACCOUNT.workers.dev, and redeploy Next.js.

## 5. Verify the upload and playback flow
1. Sign up at /signup.
2. Promote the owner profile to role admin using the SQL above.
3. Sign in and open /admin.
4. Create a course, upload a short MP4, then publish the course and lesson.
5. Create a test student account and add an active enrollment only for a legitimate test purchase:

    insert into public.enrollments(user_id, course_id, status)
    select (select id from auth.users where email='STUDENT_EMAIL_HERE'),
           (select id from public.courses where slug='YOUR_COURSE_SLUG'), 'active';

6. Sign in as the student, open the course and play the lesson.
7. Open the playback URL in a signed-out/private browser session; it must not play.

## 6. Before accepting real payments or launching to 10K viewers
- Implement Razorpay server-side order creation, signature verification and idempotent webhook processing before creating enrollments.
- Implement admin UI for quizzes, daily questions, live classes, notices and course editing.
- Add rate limits, alerting, automated database backups/PITR as needed, restore drills, privacy policy, terms, refund and data deletion workflows.
- Configure and test a strict Content Security Policy after confirming all required origins.
- Run dependency/security scans and an independent penetration test.
- Transcode video masters to adaptive-bitrate HLS (multiple renditions) and deliver segments through a cacheable media edge. The present Worker is a starter MP4 Range implementation, not a 10K-readiness certification.
- Obtain written concurrent-viewer capacity and SLA from Cloudflare/provider. Run realistic 500-viewer load tests first, then repeat at 10,000 with join bursts.
- Review device limits, session revocation and abuse controls before selling protected content.

## Environment variables
See .env.example. All R2 credentials and MEDIA_TOKEN_SECRET must remain server-side. Never commit .env.local.
